import AppKit

// AppKit lifecycle (instead of the SwiftUI `App` protocol) because this is an agent app:
// we need precise control over a status item, a non-activating panel and on-demand windows.
let app = NSApplication.shared
#if DEBUG
PreviewRenderer.runIfRequested()
#endif
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
