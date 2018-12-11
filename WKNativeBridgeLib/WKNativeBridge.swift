//
//  WKNativeBridge.swift
//
//  Created by Mateusz Stawecki on 16/11/2018.
//  Copyright © 2018 Glide Creations. All rights reserved.
//
//  Based on: https://github.com/Lision/WKWebViewJavascriptBridge
//  Created by Lision

import Foundation
import UIKit
import WebKit
import MessageUI

public class WKNativeBridge: NSObject, WKScriptMessageHandler {
    
    public typealias Callback = (_ responseData: Any?) -> Void
    public typealias Handler = (_ parameters: [String: Any]?, _ callback: Callback?) -> Void
    public typealias Message = [String: Any]

    var webView: WKWebView?
    var verbose = false
    
    /* iOS callbacks for calls made to WKWebview */
    var responseCallbacks = [String: Callback]()
    /* Message handlers from calls made from WKWebview */
    var messageHandlers = [String: Handler]()
    var uniqueId = 0

    /* Send message to WKWebview JS handler */
    func send(handlerName: String, data: Any?, callback: Callback?) {
        var message = [String: Any]()
        message["handlerName"] = handlerName
        message["call"] = "send"

        if data != nil {
            message["data"] = data
        }
        
        if callback != nil {
            uniqueId += 1
            let callbackID = "\(uniqueId)"
            responseCallbacks[callbackID] = callback
            message["callbackID"] = callbackID
        }
        
        do {
            try dispatch(message: message)
        } catch {
            // hit callback with error.
        }
    }
    
    /* Register handler called from WKWebview JS */
    public func register(handlerName: String, handler: @escaping Handler) {
        messageHandlers[handlerName] = handler
    }

    
    // internal: dipatch Swift->WKWebView
    // send a message directly to WKNativeBridge. That message will be received by JS' receive()
    private func dispatch(message: Message) throws {
        var messageJSON = try serialize(message: message)!
        
        if (verbose) {
            print("WKB:Native->JS:\(messageJSON)")
        }

        messageJSON = messageJSON.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        
        let javascriptCommand = "WKB._receive( JSON.parse( decodeURIComponent( \"\(messageJSON)\" ) ) );"
        if Thread.current.isMainThread {
            webView!.evaluateJavaScript(javascriptCommand, completionHandler: nil);
        } else {
            DispatchQueue.main.async {
                self.webView!.evaluateJavaScript(javascriptCommand, completionHandler: nil);
            }
        }
    }
    
    
    private func serialize(message: Message) throws -> String? {
        var result: String?
        let data = try JSONSerialization.data(withJSONObject: message, options: JSONSerialization.WritingOptions(rawValue: 0))
            result = String(data: data, encoding: .utf8)
        return result
    }
    
    private func deserialize(messageJSON: String) -> Message? {
        guard let data = messageJSON.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? Message
        } catch let error {
            print(error)
        }
        return nil
    }
  
    /* Call before webView loads a request, so the bridge script gets loaded. */
    public func attachToWebView(webView: WKWebView) {
        self.webView = webView;
        let userContentController = webView.configuration.userContentController
        userContentController.add(self, name: "WKB")

        let script = """
            var _bridge = {};
            window.WKB = _bridge;
            _bridge._callbacks = {};
            /* receive message from iOS */
            _bridge._receive = function(message) {
                console.log("_bridge._receive", message);
                if (message && message.call == "receive" && message.callbackID) {
                    if (_bridge._callbacks[ message.callbackID ]) {
                        _bridge._callbacks[ message.callbackID ]( message.data );
                    }
                }
                if (message && message.call == "send" && message.handlerName) {
                    _bridge._handlers[ message.handlerName ]( message.data, function(data){
                    console.log('handler result',data, message);
                        if (message.callbackID) {
                            _bridge.dispatch({ call:"receive", callbackID:message.callbackID, info:data });
                        }
                    })
                }
            }
            _bridge._handlers = {};
            _bridge.register = function( handlerName, handler ) {
                _bridge._handlers[ handlerName ] = handler;
            }
            /* dispatch message back to iOS */
            _bridge.dispatch = function( message ) {
                console.log("_bridge.dispatch", message);
                webkit.messageHandlers.WKB.postMessage(JSON.stringify(message));
            }
            _bridge.seq = 0;
            _bridge.send = function( handlerName, data, callback ) {
                var callbackID;
                if (callback) {
                    _bridge.seq++;
                    callbackID = ""+_bridge.seq;
                    _bridge._callbacks[ callbackID ] = callback;
                }
                _bridge.dispatch({ call:"send", callbackID:callbackID, handlerName:handlerName, info:data });
            }
        """
        
        let userScript: WKUserScript = WKUserScript(source:script
            , injectionTime: WKUserScriptInjectionTime.atDocumentStart, forMainFrameOnly: true)
        userContentController.addUserScript(userScript)
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "WKB" {
            let bodyString: String = String(describing:message.body);
            if (verbose) {
                print("WKB:JS->Native:\(bodyString)")
            }
            let event = self.deserialize(messageJSON: bodyString)
            if (event != nil) {
                let eventCall = event!["call"] as? String
                let eventHandlerName = event!["handlerName"] as? String
                let eventCallbackID = event!["callbackID"] as? String
                let eventInfo = event!["info"] as? [String:Any]
                // TODO: ideally "event" should be codable, but "info" may contain Any.
                // Consider: JSONAny (https://stackoverflow.com/questions/46279992/any-when-decoding-json-with-codable)
                if (eventCall == "send" && eventHandlerName != nil) {
                    let handler = messageHandlers[eventHandlerName!]
                    if (handler != nil) {
                        if (eventCallbackID != nil) {
                            let callback: Callback = { (responseData: Any?) in
                                print("responseData:\(responseData!)")
                                // if event requries callback from JS:
                                do {
                                    var sendData: Any = ""
                                    if (responseData != nil) {
                                        sendData = responseData!
                                    }
                                    // pass native result to JS callback:
                                    try self.dispatch(message: [
                                        "call":"receive",
                                        "callbackID":eventCallbackID!,
                                        "data":sendData
                                        ])
                                } catch let error {
                                    print("cb error:\(error)")
                                }
                            };
                            handler!( eventInfo, callback );
                        } else {
                            handler!( eventInfo, nil );
                        }
                        
                    }
                } else if (eventCall == "receive") {
                    if (eventCallbackID != nil && responseCallbacks[eventCallbackID!] != nil) {
                        let callback = responseCallbacks[eventCallbackID!]!
                        callback(eventInfo)
                    }
                }
            }
        }
    }
}
