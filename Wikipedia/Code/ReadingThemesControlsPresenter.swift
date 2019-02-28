//
//  ReadingThemesControlsPresenter.swift
//  Wikipedia
//
//  Created by Toni Sevener on 2/27/19.
//  Copyright © 2019 Wikimedia Foundation. All rights reserved.
//

import Foundation

protocol ReadingThemesControlsPresenting: WMFReadingThemesControlsViewControllerDelegate, UIPopoverPresentationControllerDelegate {
    var readingThemesControlsViewController: ReadingThemesControlsViewController { get }
    var readingThemesControlsToolbarItem: UIBarButtonItem { get }
    var shouldPassthroughNavBar: Bool { get }
    var showsSyntaxHighlighting: Bool { get }
    func updateWebViewTextSize(textSize: Int)
}

extension ReadingThemesControlsPresenting {
    
    var fontSizeMultipliers: [Int] {

        return [WMFFontSizeMultiplier.extraSmall.rawValue,
                WMFFontSizeMultiplier.small.rawValue,
                WMFFontSizeMultiplier.medium.rawValue,
                WMFFontSizeMultiplier.large.rawValue,
                WMFFontSizeMultiplier.extraLarge.rawValue,
                WMFFontSizeMultiplier.extraExtraLarge.rawValue,
                WMFFontSizeMultiplier.extraExtraExtraLarge.rawValue]
    }
    
    var indexOfCurrentFontSize: Int {
        get {
            let fontSize = UserDefaults.wmf.wmf_articleFontSizeMultiplier()
            let index = fontSizeMultipliers.firstIndex(of: fontSize.intValue) ?? fontSizeMultipliers.count / 2
            return index
        }
    }
    
    func showReadingThemesControlsPopup(on viewController: UIViewController, theme: Theme) {
        
        let fontSizes = fontSizeMultipliers
        let index = indexOfCurrentFontSize
        
        readingThemesControlsViewController.modalPresentationStyle = .popover
        readingThemesControlsViewController.popoverPresentationController?.delegate = self
        
        readingThemesControlsViewController.delegate = self
        readingThemesControlsViewController.setValuesWithSteps(fontSizes.count, current: index)
        readingThemesControlsViewController.showsSyntaxHighlighting = showsSyntaxHighlighting
        
        apply(presentationTheme: theme)
        
        let popoverPresenter = readingThemesControlsViewController.popoverPresentationController
        popoverPresenter?.barButtonItem = readingThemesControlsToolbarItem
        popoverPresenter?.permittedArrowDirections = [.down, .up]
        
        if let navBar = viewController.navigationController?.navigationBar,
            shouldPassthroughNavBar {
            popoverPresenter?.passthroughViews = [navBar]
        }
        
        viewController.present(readingThemesControlsViewController, animated: true, completion: nil)
    }
    
    func dismissReadingThemesPopoverIfActive(from viewController: UIViewController) {
        if viewController.presentedViewController is ReadingThemesControlsViewController {
            viewController.dismiss(animated: true, completion: nil)
        }
    }
    
    //MARK: WMFReadingThemesControlsViewControllerDelegate
    
    func fontSizeSliderValueChangedInController(_ controller: ReadingThemesControlsViewController, value: Int) {
        let fontSizes = fontSizeMultipliers
        
        if value > fontSizes.count {
            return
        }
        
        let multiplier = fontSizeMultipliers[value]
        let nsNumber = NSNumber(value: multiplier)
        UserDefaults.wmf.wmf_setArticleFontSizeMultiplier(nsNumber)
        
        updateWebViewTextSize(textSize: multiplier)
    }
    
   func apply(presentationTheme theme: Theme) {
        readingThemesControlsViewController.apply(theme: theme)
        readingThemesControlsViewController.popoverPresentationController?.backgroundColor = theme.colors.popoverBackground
    }
}

//objective-c wrapper for Article presentation.
@objc(WMFReadingThemesControlsPresenter)
class ReadingThemesControlsPresenter: NSObject, ReadingThemesControlsPresenting {
    
    var shouldPassthroughNavBar: Bool {
        return true
    }
    
    var showsSyntaxHighlighting: Bool {
        return false
    }
    
    var readingThemesControlsViewController: ReadingThemesControlsViewController
    var readingThemesControlsToolbarItem: UIBarButtonItem
    var readingThemesControlsPopoverPresenter: UIPopoverPresentationController?
    private let wkWebView: WKWebView
    
    @objc var objcIndexOfCurrentFontSize: Int {
        return indexOfCurrentFontSize
    }
    
    @objc var objcFontSizeMultipliers: [Int] {
        return fontSizeMultipliers
    }
    
    @objc init(readingThemesControlsViewController: ReadingThemesControlsViewController, readingThemesControlsPopoverPresenter: UIPopoverPresentationController, wkWebView: WKWebView, readingThemesControlsToolbarItem: UIBarButtonItem) {
        self.readingThemesControlsViewController = readingThemesControlsViewController
        self.wkWebView = wkWebView
        self.readingThemesControlsToolbarItem = readingThemesControlsToolbarItem
        self.readingThemesControlsPopoverPresenter = readingThemesControlsPopoverPresenter
        super.init()
    }
    
    @objc func objCShowReadingThemesControlsPopup(on viewController: UIViewController, theme: Theme) {
        showReadingThemesControlsPopup(on: viewController, theme: theme)
    }
    
    @objc func objCDismissReadingThemesPopoverIfActive(from viewController: UIViewController) {
        dismissReadingThemesPopoverIfActive(from: viewController)
    }

    @objc func objCApplyPresentationTheme(theme: Theme) {
        apply(presentationTheme: theme)
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
    
    func toggleSyntaxHighlighting(_ controller: ReadingThemesControlsViewController) {
        //do nothing
    }
    
    func updateWebViewTextSize(textSize: Int) {
        wkWebView.wmf_setTextSize(textSize)
    }
}
