//
//  ViewController.swift
//  WKNativeBridge
//
//  Created by Mateusz Stawecki on 07/12/2018.
//  Copyright © 2018 Tapjet. All rights reserved.
//

import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate {

    let bridge = WKNativeBridge()
    var counter = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        bridge.verbose = true // if switched on, all communication will be logged to the console
        
        // register a native code block:
        bridge.register(handlerName: "testSwift") { (info, callback) in
            if (callback != nil) {
                self.counter = self.counter + 1
                callback!([ "counter": self.counter, "from":"Swift" ])
            }
        }
        
        // Add WKWebView and attach bridge
        let webView = WKWebView(frame: self.view.bounds)
        webView.navigationDelegate = self
        bridge.attachToWebView(webView: webView)
        self.view.addSubview(webView)
        webView.loadHTMLString("""
        <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
            </head>
            <body>
                <script>
                    let bridge = WKB;
                    // register a js code block:
                    bridge.register("testJS", (info, cb) => {
                        document.getElementById('test').innerHTML = JSON.stringify(info)
                        cb({ d: Date.now() })
                    })
                </script>
                <!-- Call Swift handler from a browser button: -->
                <input type="button" value="Call Swift Handler" onclick="WKB.send('testSwift',{},(info)=>{ document.getElementById('test').innerHTML = JSON.stringify(info) })">
                <div id="test"></div>
            </body>
        </html>
        """, baseURL: nil)
        
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // test invoking the bridge on load:
        bridge.send(handlerName: "testJS", data: ["hello":"From Swift"]) { (info) in
            print("received from js: \(String(describing: info))")
        }
    }


}

