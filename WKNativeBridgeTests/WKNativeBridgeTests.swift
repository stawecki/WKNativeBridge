//
//  WKNativeBridgeTests.swift
//  WKNativeBridgeTests
//
//  Created by Mateusz Stawecki on 07/12/2018.
//  Copyright © 2018 Tapjet. All rights reserved.
//

import XCTest
import WebKit
@testable import WKNativeBridge

/* Basic execution tests */
class WKNativeBridgeTests: XCTestCase, WKNavigationDelegate {

    let viewController = UIViewController(nibName: nil, bundle: nil)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let bridge = WKNativeBridge()
    let setUpExpectation = XCTestExpectation(description: "Load WKWebView for testing")

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        setUpExpectation.fulfill()
    }
    
    func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0...length-1).map{ _ in letters.randomElement()! })
    }
    
    override func setUp() {
        //
        let rootView = UIApplication.shared.keyWindow!.rootViewController?.view
        rootView?.addSubview(viewController.view)
        viewController.view.addSubview(webView)
        bridge.attachToWebView(webView: webView)
        webView.navigationDelegate = self
        webView.loadHTMLString("""
        <script>
            let bridge = WKB;
            bridge.register("testJS", (info, cb) => {
                cb({ d: Date.now(), arg: info, from:"JS" })
            })
            let counter = 0
            bridge.register("counterReset", (info, cb) => {
                counter = 0;
                cb({ d: Date.now() })
            })
            bridge.register("counterIncrement", (info, cb) => {
                counter++;
                cb({ d: Date.now(), arg: info, from:"JS", counter:counter })
            })
            bridge.register("nativeCounterDispatch", (info, cb) => {
                counter++;
                for (var i = 0; i < info.parallelCount; i++) {
                    bridge.send('counterReceive',{},(info)=>{

                    })
                }
                cb({ d: Date.now() })
            })

        </script>
        """, baseURL: nil)
        
        wait(for: [setUpExpectation], timeout: 10.0)
    }

    override func tearDown() {
        webView.removeFromSuperview()
        viewController.view.removeFromSuperview()
    }

    func testSingleExecution() {
        let expectation = XCTestExpectation(description: "Single testJS execution Swift->JS with callback")
        bridge.send(handlerName: "testJS", data: ["from":"Swift"]) { (response) in
            // print("\(String(describing: response))")
            XCTAssertEqual((response as! WKNativeBridge.Message)["from"] as! String, "JS")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)
    }

    func testSingleExecutionTimed() {
        self.measure {
            let expectation = XCTestExpectation(description: "Single testJS execution Swift->JS with callback - timed")
            bridge.send(handlerName: "testJS", data: ["from":"Swift"]) { (response) in
                // print("\(String(describing: response))")
                XCTAssertEqual((response as! WKNativeBridge.Message)["from"] as! String, "JS")
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }

    func testParallelSendFromNativeTimed() {
        self.measure {
            let expectation = XCTestExpectation(description: "Parallel send Swift->JS with callback - timed")
            let parallelCount = 100
            
            bridge.send(handlerName: "counterReset", data: ["from":"Swift"]) { (response) in
                for _ in 1...parallelCount {
                    self.bridge.send(handlerName: "counterIncrement", data: ["from":"Swift"]) { (response) in
                         print("\(String(describing: response))")
                        
                        if((response as! WKNativeBridge.Message)["counter"] as! Int == parallelCount) {
                            expectation.fulfill() // JS counter reached dispatched count
                        }
                    }
                    //print(i)
                }
            }
                
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testParallelSendFromJSTimed() {
        self.measure {
            let expectation = XCTestExpectation(description: "Parallel send JS->Swift with callback - timed")
            let parallelCount = 100
            var testCounter = 0;
            
            // the native handler will be called *parallelCount*-times by JS:
            bridge.register(handlerName: "counterReceive", handler: { (info, callback) in
                print("\(String(describing: info))")
                testCounter = testCounter + 1 // increment natively
                
                if(testCounter == parallelCount) {
                    expectation.fulfill() // Swift counter reached dispatched count
                }

                if (callback != nil) { callback!([]) }
            })

            // tell JS to start dipatching calls to Swift to perform the test:
            bridge.send(handlerName: "nativeCounterDispatch", data: ["from":"Swift","parallelCount":parallelCount]) { (response) in
                print("\(String(describing: response))")
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testSingleExecutionLargeData() {
        let data = randomString(length: 1024*1024) // 1MB
        self.measure {
            let expectation = XCTestExpectation(description: "Single testJS execution Swift->JS with callback - large data")
            bridge.send(handlerName: "testJS", data: ["from":"Swift","data":data]) { (response) in
                XCTAssertEqual((response as! WKNativeBridge.Message)["from"] as! String, "JS")
                let arg = (response as! WKNativeBridge.Message)["arg"] as! WKNativeBridge.Message
                XCTAssertEqual(arg["data"] as! String, data) // check echoed data from JS is same as data sent from Swift
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testParallelSendLargeDataFromNativeTimed() {
        let data = randomString(length: 1024*1024) // 1MB
        self.measure {
            let expectation = XCTestExpectation(description: "Parallel send Swift->JS with callback - large data - timed")
            let parallelCount = 10
            
            bridge.send(handlerName: "counterReset", data: ["from":"Swift"]) { (response) in
                for i in 1...parallelCount {
                    let uniqueData = data+String(i) // append iterator number to make the data unique in the context of this test case to ensure send<->callback consistency
                    self.bridge.send(handlerName: "counterIncrement", data: ["from":"Swift","data":uniqueData]) { (response) in
                        let arg = (response as! WKNativeBridge.Message)["arg"] as! WKNativeBridge.Message
                        XCTAssertEqual(arg["data"] as! String, uniqueData) // check echoed data from JS is same as data sent from Swift

                        if((response as! WKNativeBridge.Message)["counter"] as! Int == parallelCount) {
                            expectation.fulfill() // JS counter reached dispatched count
                        }
                    }
                    print(i)
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
}
