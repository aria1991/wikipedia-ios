
import Foundation
import SafariServices

@objc protocol LoadingFlowControllerFetchDelegate: class {
    func loadEmbedFetch(url: URL, successHandler: @escaping (LoadingFlowControllerArticle, URL) -> Void, errorHandler: @escaping (NSError) -> Void) -> URLSessionTask?
    func linkPushFetch(url: URL, successHandler: @escaping (LoadingFlowControllerArticle, URL) -> Void, errorHandler: @escaping (NSError) -> Void) -> URLSessionTask?
}

protocol LoadingFlowControllerTaskTrackingDelegate: LoadingFlowControllerFetchDelegate {
    func linkPushFetch(url: URL, successHandler: @escaping (LoadingFlowControllerArticle, URL) -> Void, errorHandler: @escaping (NSError, URL) -> Void) -> (cancellationKey: String, fetcher: Fetcher)?
}

@objc protocol LoadingFlowControllerChildProtocol: class {
    var reachabilityNotifier: ReachabilityNotifier? { get }
    func handleCustomSuccess(article: LoadingFlowControllerArticle, url: URL) -> Bool
    func showDefaultEmbedFailure(error: NSError)
    func showDefaultLinkFailure(error: NSError)
    var loadingFlowController: LoadingFlowController? { get }
    @objc optional var customNavAnimationHandler: UIViewController? { get }
}

class LoadingFlowController: UIViewController {
    
    enum ProcessSource {
        case loadEmbed
        case linkPush
    }
    
    let flowChild: LoadingFlowControllerChildProtocol
    private let fetchDelegate: LoadingFlowControllerFetchDelegate
    private let url: URL
    private let dataStore: MWKDataStore
    private let theme: Theme
    private let embedOnLoad: Bool
    
    private let loadingAnimationViewController = LoadingAnimationViewController(nibName: "LoadingAnimationViewController", bundle: nil)
    
    init(dataStore: MWKDataStore, theme: Theme, fetchDelegate: LoadingFlowControllerFetchDelegate, flowChild: LoadingFlowControllerChildProtocol, url: URL, embedOnLoad: Bool) {
        self.dataStore = dataStore
        self.theme = theme
        self.fetchDelegate = fetchDelegate
        self.flowChild = flowChild
        self.url = url
        self.embedOnLoad = embedOnLoad
        super.init(nibName: nil, bundle: nil)
    }
    
    @objc init(articleViewController: WMFArticleViewController, embedOnLoad: Bool) {
        self.dataStore = articleViewController.dataStore
        self.theme = articleViewController.theme
        //todo: remove the as!
        self.fetchDelegate = articleViewController as! LoadingFlowControllerFetchDelegate
        self.flowChild = articleViewController as! LoadingFlowControllerChildProtocol
        self.url = articleViewController.articleURL
        self.embedOnLoad = embedOnLoad
        super.init(nibName: nil, bundle: nil)
        articleViewController.loadingFlowController = self
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        apply(theme: theme)
        
        if (embedOnLoad) {
            let task = fetchDelegate.loadEmbedFetch(url: url, successHandler: { [weak self] (article, url) in
                
                guard let self = self else { return }
                
                self.hideLoading()
                self.processSuccess(article: article, url: url, source: .loadEmbed)
            }) { [weak self] (error) in
                
                guard let self = self else { return }
                
                self.hideLoading()
                self.processFailure(error: error, source: .loadEmbed, url: self.url)
            }
            
            loadingAnimationViewController.cancelBlock = { [weak self] in
                self?.hideLoading()
                task?.cancel()
                self?.navigationController?.popViewController(animated: true)
            }
            
            scheduleLoadingAnimation()
        }
    }
    
    @objc func tappedLink(url: URL) {
        
        if let taskTrackingDelegate = fetchDelegate as? LoadingFlowControllerTaskTrackingDelegate {
            let result = taskTrackingDelegate.linkPushFetch(url: url, successHandler: { [weak self] (article, url) in
                
                guard let self = self else { return }
                
                self.hideLoading()
                self.processSuccess(article: article, url: url, source: .linkPush)
            }) { [weak self] (error, url) in
                
                guard let self = self else { return }
                
                self.hideLoading()
                self.processFailure(error: error, source: .linkPush, url: url)
            }
            
            loadingAnimationViewController.cancelBlock = { [weak self] in
                
                self?.hideLoading()
                
                if let result = result {
                    result.fetcher.cancel(taskFor: result.cancellationKey)
                }
                
            }
            
            scheduleLoadingAnimation()
            return
        }
        
        let task = fetchDelegate.linkPushFetch(url: url, successHandler: { [weak self] (article, url) in
            
            guard let self = self else { return }
            
            self.hideLoading()
            self.processSuccess(article: article, url: url, source: .linkPush)
            
        }, errorHandler: { [weak self] (error) in
            
            guard let self = self else { return }
            
            self.hideLoading()
            self.processFailure(error: error, source: .linkPush, url: url)
            
        })
        
        loadingAnimationViewController.cancelBlock = { [weak self] in
            self?.hideLoading()
            task?.cancel()
        }
        
        scheduleLoadingAnimation()
    }
    
    private func scheduleLoadingAnimation() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showLoading), object: nil)
        perform(#selector(showLoading), with: nil, afterDelay: 0.5)
    }
    
    @objc private func showLoading() {
        
        if let customAnimationContainer = flowChild.customNavAnimationHandler as? UIViewController {
            customAnimationContainer.wmf_add(childController: loadingAnimationViewController, andConstrainToEdgesOfContainerView: customAnimationContainer.view)
        } else {
            wmf_add(childController: loadingAnimationViewController, andConstrainToEdgesOfContainerView: view)
        }
        
    }
    
    @objc private func hideLoading() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showLoading), object: nil)
        loadingAnimationViewController.willMove(toParent: nil)
        loadingAnimationViewController.view.removeFromSuperview()
        loadingAnimationViewController.removeFromParent()
    }
    
    private func processSuccess(article: LoadingFlowControllerArticle, url: URL, source: ProcessSource) {
        
        if flowChild.handleCustomSuccess(article: article, url: url) {
            return
        }
        
        switch article.namespace {
        case PageNamespace.main.rawValue:
            showArticleViewController(article: article, url: url, source: source)
        case PageNamespace.userTalk.rawValue:
            showTalkPage(url: url, source: source)
        default:
            showExternal(url: url, source: source)
        }
    }
    
    private func processFailure(error: NSError, source: ProcessSource, url: URL) {
        
        if error.isCancelledError { //error came via cancelled fetch, no need to propogate to user
            return
        }
        
        if let cachedFallbackArticle = error.cachedFallbackArticle {
            
            if let cachedFallbackURL = cachedFallbackArticle.loadingFlowURL {
                switch cachedFallbackArticle.namespace {
                case PageNamespace.main.rawValue:
                    showArticleViewController(article: cachedFallbackArticle, url: cachedFallbackURL, source: source)
                    
                    if !error.wmf_isNetworkConnectionError() {
                        WMFAlertManager.sharedInstance.showErrorAlert(error, sticky: false, dismissPreviousAlerts: false)
                    }
                    
                case PageNamespace.userTalk.rawValue:
                    showTalkPage(url: cachedFallbackURL, source: source)
                default:
                    showExternal(url: cachedFallbackURL, source: source)
                    
                }
            } else {
                if !error.wmf_isNetworkConnectionError() {
                    WMFAlertManager.sharedInstance.showErrorAlert(error, sticky: false, dismissPreviousAlerts: false)
                }
            }
        } else if error.isUnexpectedResponseError || error.isInvalidParameterError {
            
            showExternal(url: url, source: source)
            
        } else {
            
            switch source {
            case .loadEmbed:
                flowChild.showDefaultEmbedFailure(error: error)

                if error.wmf_isNetworkConnectionError() {
                    flowChild.reachabilityNotifier?.start()
                }
            case .linkPush:
                flowChild.showDefaultLinkFailure(error: error)
            }
            
        }
    }
    
    private func showExternal(url: URL, source: ProcessSource) {
        
        switch source {
        case .loadEmbed:
            let safariVC = SFSafariViewController(url: url)
            safariVC.delegate = self
            wmf_add(childController: safariVC, andConstrainToEdgesOfContainerView: view)
        case .linkPush:
            if let customNavHandler = flowChild.customNavAnimationHandler as? UIViewController {
                customNavHandler.wmf_openExternalUrl(url)
            } else {
                wmf_openExternalUrl(url)
            }
        }
    }
    
    private func showArticleViewController(article: LoadingFlowControllerArticle, url: URL, source: ProcessSource) {

        switch source {
        case .loadEmbed:
            if let articleVC = flowChild as? WMFArticleViewController,
                let mwkArticle = article as? MWKArticle {
                articleVC.skipFetchOnViewDidAppear = true
                wmf_add(childController: articleVC, andConstrainToEdgesOfContainerView: view)
                articleVC.article = mwkArticle
                articleVC.kickoffProgressView()
            } else {
                assertionFailure("Issue pushing article view controller")
            }
        case .linkPush:
            
            //todo: fix the as!
            let articleVC = WMFArticleViewController(articleURL: url, dataStore: dataStore, theme: theme)
            let loadingFlowController = LoadingFlowController(dataStore: dataStore, theme: theme, fetchDelegate: articleVC as! LoadingFlowControllerFetchDelegate, flowChild: articleVC as! LoadingFlowControllerChildProtocol, url: url, embedOnLoad: true)
            articleVC.loadingFlowController = loadingFlowController
            
            if let mwkArticle = article as? MWKArticle {
                articleVC.viewDidLoadCompletion = {
                    articleVC.article = mwkArticle
                }
                
                articleVC.skipFetchOnViewDidAppear = true
            }
            
            wmf_push(loadingFlowController, animated: true)
        }
    }
    
    private func showTalkPage(url: URL, source: ProcessSource) {
        
        guard let siteURL = url.wmf_site else {
            assertionFailure("Issue determining siteURL for talk page.")
            return
        }
        
        var title = url.lastPathComponent
        
        if let firstColon = title.range(of: ":") {
            title.removeSubrange(title.startIndex..<firstColon.upperBound)
        }
        
        let titleWithTalkPageNamespace = TalkPageType.user.titleWithCanonicalNamespacePrefix(title: title, siteURL: siteURL)
        
        switch source {
        case .loadEmbed:
            let talkPageVC = TalkPageContainerViewController(title: titleWithTalkPageNamespace, siteURL: siteURL, type: .user, dataStore: dataStore)
            wmf_add(childController: talkPageVC, andConstrainToEdgesOfContainerView: view)
        case .linkPush:
            let containerVC = TalkPageContainerViewController.containedTalkPageContainer(title: titleWithTalkPageNamespace, siteURL: siteURL, dataStore: dataStore, type: .user, theme: theme)
            self.navigationController?.pushViewController(containerVC, animated: true)
        }
    }
}

extension LoadingFlowController: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        self.navigationController?.popViewController(animated: true)
    }
}

extension LoadingFlowController: Themeable {
    func apply(theme: Theme) {
        view.backgroundColor = theme.colors.paperBackground
        loadingAnimationViewController.theme = theme
    }
}

//MARK: Error Handling

extension NSError {
    
    var cachedFallbackArticle: LoadingFlowControllerArticle? {
        if let cachedFallback = userInfo[WMFArticleFetcherErrorCachedFallbackArticleKey] as? LoadingFlowControllerArticle {
            return cachedFallback
        } else {
            return nil
        }
    }
    
    var isUnexpectedResponseError: Bool {
        return domain == Fetcher.unexpectedResponseError.domain && code == Fetcher.unexpectedResponseError.code
    }
    
    var isCancelledError: Bool {
        return domain == NSURLErrorDomain &&
        code == NSURLErrorCancelled
    }
    
    var isInvalidParameterError: Bool {
        return self == Fetcher.invalidParametersError
    }
}

//MARK: LoadingFlowControllerArticle

@objc protocol LoadingFlowControllerArticle {
    var namespace: Int { get }
    var loadingFlowURL: URL! { get }
}

extension MWKArticle: LoadingFlowControllerArticle {
    var namespace: Int {
        return ns
    }
    
    var loadingFlowURL: URL! {
        return url
    }
}

extension WMFArticle: LoadingFlowControllerArticle {
    public var namespace: Int {
        return pageNamespace?.rawValue ?? -1
    }
    
    var loadingFlowURL: URL! {
        return url
    }
}
