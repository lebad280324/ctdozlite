import SwiftUI
import AppKit

/// Use system Liquid Glass for controls, with an opaque accessibility fallback.
struct NativeGlass: ViewModifier {
    var radius: CGFloat = 20
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
    }
}

extension View {
    func nativeGlass(_ radius: CGFloat = 20) -> some View { modifier(NativeGlass(radius: radius)) }
}

/// Plain content background; colour is reserved for bubbles and the selection.
struct WorkspaceBackdrop: View {
    var body: some View {
        Color(nsColor: .textBackgroundColor).ignoresSafeArea().allowsHitTesting(false)
    }
}

extension Color {
    /// Neutral bubble for received messages in light and dark appearance.
    static let bubbleIncoming = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(white: 0.23, alpha: 1) : NSColor(red: 0.914, green: 0.914, blue: 0.922, alpha: 1)
    })
}

/// Keep native window controls while exposing the content beneath the toolbar.
struct NativeWindowChrome: NSViewRepresentable {
    /// Reports the system window corner radius once the window exists.
    var onCornerRadius: (CGFloat) -> Void = { _ in }
    func makeNSView(context: Context) -> NSView { let view = ChromeView(); view.onCornerRadius = onCornerRadius; return view }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class ChromeView: NSView {
        var onCornerRadius: (CGFloat) -> Void = { _ in }
        static let windowRadius: CGFloat = 26

        /// Calls `_setCornerRadius:` with a CGFloat argument; returns whether the window accepted it.
        @discardableResult
        static func applyCornerRadius(_ radius: CGFloat, to window: NSWindow) -> Bool {
            let selector = NSSelectorFromString("_setCornerRadius:")
            typealias Setter = @convention(c) (AnyObject, Selector, CGFloat) -> Void
            var applied = false
            for target in [window as NSObject, window.contentView?.superview as NSObject?].compactMap({ $0 }) where target.responds(to: selector) {
                guard let method = class_getInstanceMethod(type(of: target), selector) else { continue }
                unsafeBitCast(method_getImplementation(method), to: Setter.self)(target, selector, radius)
                applied = true
            }
            if applied { window.contentView?.superview?.needsDisplay = true; window.invalidateShadow() }
            return applied
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            // The regular unified toolbar gives the larger window corner radius of macOS 26.
            window.toolbarStyle = .unified
            // Let AppKit draw a single native edge; no second rounded content mask.
            window.contentView?.layer?.cornerRadius = 0
            window.contentView?.layer?.masksToBounds = false
            // Same private AppKit setter Telegram for macOS uses (`_setCornerRadius:` on the window and
            // its theme frame). Missing selectors are skipped, leaving the system radius untouched.
            let report = onCornerRadius
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                if Self.applyCornerRadius(Self.windowRadius, to: window) { report(Self.windowRadius) }
                else if let value = window.value(forKey: "_cornerRadius") as? NSNumber, value.doubleValue > 4 { report(CGFloat(value.doubleValue)) }
            }
            // Full screen and some resizes rebuild the frame view; restore the radius afterwards.
            for name in [NSWindow.didExitFullScreenNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didBecomeKeyNotification] {
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated { if let window { _ = Self.applyCornerRadius(Self.windowRadius, to: window) } }
                }
            }

        }
    }
}

struct TransparentComposerGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius:20))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: RoundedRectangle(cornerRadius:20))
        } else {
            content.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20))
        }
    }
}

/// A readable material, rather than refracting the transcript through editable text.
struct ReadableComposerSurface: ViewModifier {
 @Environment(\.colorScheme) private var scheme
 func body(content:Content)->some View {
  content.nativeGlass(22)
   .background(Color(nsColor:.textBackgroundColor).opacity(scheme == .dark ? 0.58 : 0.62),in:RoundedRectangle(cornerRadius:22))
   .overlay{RoundedRectangle(cornerRadius:22).strokeBorder(Color.primary.opacity(0.12),lineWidth:0.75)}
 }
}
