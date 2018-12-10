# WKNativeBridge
Two-way bridge for sending messages between Swift and JavaScript in WKWebView.

## Features
- Single-file implementation (Swift 4.2)
- No static JS dependencies (injected at runtime via WKUserContentController)
- Simple message flow (no additonal queues, relying on webkit.messageHandlers directly)
- XCTest suite for performance, durability and parallel testing
- iOS9+

## Example

Initiate bridge in Swift:
```swift
let bridge = WKNativeBridge()
```

Attach to WKWebView instance before loading your page:
```swift
bridge.attachToWebView(webView: webView)
```

### Call Swift (Native) code from JavaScript (WKWebView)

Define native handlers:
```swift
// register a native code block:
bridge.register(handlerName: "testSwift") { (info, callback) in
    print("received from js: \(String(describing: info))")
    if (callback != nil) {
        self.counter = self.counter + 1
        callback!([ "counter": self.counter, "from":"Swift" ]) // reply to JS send request
    }
}
```

In your page, call Swift handler from JavaScript:
```js
if (typeof WKB !== 'undefined') {
    let bridge = WKB;
    bridge.send('testSwift', { timestamp: Date.now() }, (info)=>{ 
        console.log(info); // log reply from Swift
    })
} else {
    console.log("WKNativeBridge is not available. Implement fallback if necessary.")
}
```

### Call JavaScript (WKWebView) code from Swift (Native)

Define JavaScript handlers:
```html
<script>
    let bridge = WKB;
    // register a js code block:
    bridge.register("testJS", (info, cb) => {
        console.log(info); // log payload sent from Swift
        cb({ d: Date.now() }) // reply to Swift's send request
    })
</script>

```

In Swift, Call JavaScript handler and receive reply:
```swift
bridge.send(handlerName: "testJS", data: ["hello":"From Swift"]) { (info) in
    print("received from js: \(String(describing: info))")
}
```

## Other
This is a work in progress. The goal is to create a minimalistic solution aimed at modern iOS and Swift without UIWebView and Obj-C baggage.

WKNativeBridge is based on: https://github.com/Lision/WKWebViewJavascriptBridge

For a more cross-platform solution see: https://github.com/marcuswestin/WebViewJavascriptBridge

## License
MIT

