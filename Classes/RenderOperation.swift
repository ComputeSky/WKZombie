//
//  RenderOperation.swift
//  HeadlessDemo
//
//  Created by Mathias Köhnke on 17/12/15.
//  Copyright © 2015 Mathias Köhnke. All rights reserved.
//

import Foundation
import WebKit

internal class RenderOperation : NSOperation {
    
    typealias RequestBlock = () -> Void

    var loadMediaContent : Bool = true
    var requestBlock : RequestBlock?
    var postAction: PostAction?
    
    internal private(set) var result : NSData?
    internal private(set) var response : NSURLResponse?
    internal private(set) var error : NSError?
    
    private var _executing: Bool = false
    override var executing: Bool {
        get {
            return _executing
        }
        set {
            if _executing != newValue {
                willChangeValueForKey("isExecuting")
                _executing = newValue
                didChangeValueForKey("isExecuting")
            }
        }
    }
    
    private var _finished: Bool = false;
    override var finished: Bool {
        get {
            return _finished
        }
        set {
            if _finished != newValue {
                willChangeValueForKey("isFinished")
                _finished = newValue
                didChangeValueForKey("isFinished")
            }
        }
    }
    
    override func main() {
        if self.cancelled {
            return
        } else {
            HLLog("Starting Rendering - \(name)")
            executing = true
            requestBlock?()
        }
    }
    
    func completeRendering(webView: WKWebView?, result: NSData? = nil, error: NSError? = nil) {
        self.result = result ?? self.result
        self.error = error ?? self.error
    
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandlerForName("doneLoading")
        
        executing = false
        finished = true
        
        if(finished) {
            NSLog("completed")
        } else {
            NSLog("Not completed")
        }
    }
}


extension RenderOperation : WKScriptMessageHandler {
    
    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        //None of the content loaded after this point is necessary (images, videos, etc.)
        if let webView = message.webView {
            if message.name == "doneLoading" && loadMediaContent == false {
                if let url = webView.URL where response == nil {
                    response = NSHTTPURLResponse(URL: url, statusCode: 200, HTTPVersion: nil, headerFields: nil)
                }
                webView.stopLoading()
                self.webView(webView, didFinishNavigation: nil)
            }
        }
    }
}

extension RenderOperation : WKNavigationDelegate {
    
    func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse, decisionHandler: (WKNavigationResponsePolicy) -> Void) {
        response = navigationResponse.response
        decisionHandler(.Allow)
    }
    
    func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError error: NSError) {
        if let response = response as? NSHTTPURLResponse, _ = completionBlock {
            let successRange = 200..<300
            if !successRange.contains(response.statusCode) {
                self.error = error
                self.completeRendering(webView)
            }
        }
    }
    
    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        if let postAction = postAction {
            handlePostAction(postAction, webView: webView)
        } else {
            finishedLoading(webView)
        }
    }
    
}


extension RenderOperation {
        
    func finishedLoading(webView: WKWebView) {
        webView.evaluateJavaScript("document.documentElement.outerHTML;") { [weak self] result, error in
            //HLLog("\(result)")
            self?.result = result?.dataUsingEncoding(NSUTF8StringEncoding)
            self?.completeRendering(webView)
        }
    }
    
    func validate(condition: String, webView: WKWebView) {
        webView.evaluateJavaScript(condition) { [weak self] result, error in
            if let result = result as? Bool where result == true {
                self?.finishedLoading(webView)
            } else {
                delay(0.5, completion: {
                    self?.validate(condition, webView: webView)
                })
            }
        }
    }
    
    func waitAndFinish(time: NSTimeInterval, webView: WKWebView) {
        delay(time) {
            self.finishedLoading(webView)
        }
    }
    
    func handlePostAction(postAction: PostAction, webView: WKWebView) {
        switch postAction.type {
        case .Validate: validate(postAction.value as! String, webView: webView)
        case .Wait: waitAndFinish(postAction.value as! NSTimeInterval, webView: webView)
        }
        self.postAction = nil
    }
    
}

// MARK: Helper

private func delay(time: NSTimeInterval, completion: () -> Void) {
    let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(time * Double(NSEC_PER_SEC)))
    dispatch_after(delayTime, dispatch_get_main_queue()) {
        completion()
    }
}