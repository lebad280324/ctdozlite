import AppKit
import ObjectiveC

/// Rate-limits redundant `NSCursor.set()` calls.
///
/// Whenever views move under a resting pointer (scrolling, resizing) AppKit re-evaluates the cursor on
/// every display cycle and sets it again even when it has not changed. With an Accessibility pointer
/// size or colour each `set()` re-renders and re-registers the pointer image, which was measured at
/// 5-8 ms per frame on a 120 Hz display (see `re-notes/56_native_macos_120hz.md`). No public API
/// suppresses the redundant call, so the same cursor is passed through at most once per second.
/// A different cursor is always applied immediately, and any stale state corrects itself within a second.
@MainActor enum CursorThrift {
    private static var installed = false
    fileprivate static weak var last: NSCursor?
    fileprivate static var lastTime: CFTimeInterval = 0
    static let interval: CFTimeInterval = 1

    static func install() {
        guard !installed,
              let original = class_getInstanceMethod(NSCursor.self, #selector(NSCursor.set)),
              let replacement = class_getInstanceMethod(NSCursor.self, #selector(NSCursor.ctdoThriftySet)) else { return }
        installed = true
        method_exchangeImplementations(original, replacement)
    }

    /// True when this cursor was applied so recently that applying it again cannot change anything.
    static func isRedundant(_ cursor: NSCursor, now: CFTimeInterval) -> Bool {
        last === cursor && now - lastTime < interval
    }
}

extension NSCursor {
    @objc dynamic func ctdoThriftySet() {
        // Preserve AppKit's behavior for unexpected off-main callers rather than asserting actor isolation.
        guard Thread.isMainThread else { self.ctdoThriftySet(); return }
        MainActor.assumeIsolated {
            let now = CACurrentMediaTime()
            if NSCursor.current === self, CursorThrift.isRedundant(self, now: now) { return }
            CursorThrift.last = self; CursorThrift.lastTime = now
            // The implementations are exchanged, so this calls AppKit's original `set`.
            self.ctdoThriftySet()
        }
    }
}
