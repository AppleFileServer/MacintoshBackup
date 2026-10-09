import AppKit
import SwiftUI

/// Hands over the NSWindow a SwiftUI view is in, once it's in one.
struct WindowFinder: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Finder(found: found) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Finder: NSView {
        let found: (NSWindow) -> Void
        init(found: @escaping (NSWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}
