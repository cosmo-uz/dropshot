// Prints Dropshot's on-screen windows (bounds, level) every 50 ms for N seconds.
// Works without Screen Recording permission and while the session is locked.
//   swift scripts/window-probe.swift [seconds]
import AppKit
import CoreGraphics

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 8 : 8
let start = Date()
var last = ""
while Date().timeIntervalSince(start) < seconds {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let ours = info.filter { ($0[kCGWindowOwnerName as String] as? String) == "Dropshot" }
    let description = ours.compactMap { window -> String? in
        guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let layer = window[kCGWindowLayer as String] as? Int else { return nil }
        if layer == 25, (bounds["Height"] ?? 0) < 40 { return nil } // the status item
        return "layer \(layer) x:\(Int(bounds["X"] ?? 0)) y:\(Int(bounds["Y"] ?? 0)) w:\(Int(bounds["Width"] ?? 0)) h:\(Int(bounds["Height"] ?? 0))"
    }.joined(separator: " | ")
    let state = description.isEmpty ? "no panel on screen" : description
    if state != last {
        print(String(format: "t=%5.2fs  %@", Date().timeIntervalSince(start), state))
        last = state
    }
    usleep(50_000)
}
