import SwiftUI
import AppKit

/// Height a popover's content may use without running past the window edge.
private struct PopoverMaxHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 600 }

extension EnvironmentValues {
    var popoverMaxHeight: CGFloat {
        get { self[PopoverMaxHeightKey.self] }
        set { self[PopoverMaxHeightKey.self] = newValue }
    }
}

/// Window-space room around an anchor, used to keep popovers inside the app window.
/// AppKit places popovers against the screen, so a tall card beside a row near the
/// window's bottom edge would otherwise hang below the window.
enum PopoverRoom {
    static let margin: CGFloat = 14
    /// Opens towards the larger side; returns that edge and the content height that fits there.
    static func vertical(anchor: CGRect, windowHeight: CGFloat) -> (edge: Edge, maxHeight: CGFloat) {
        let above = anchor.minY - margin * 2
        let below = windowHeight - anchor.maxY - margin * 2
        return above > below ? (.top, max(200, above)) : (.bottom, max(200, below))
    }
    static var windowHeight: CGFloat {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.contentView?.bounds.height ?? 800
    }
}

private struct WindowBoundedPopover<Popover: View>: ViewModifier {
    @Binding var isPresented: Bool
    let popover: () -> Popover
    /// Updated without re-rendering, so rows that never open a popover cost nothing while scrolling.
    @State private var anchor = FrameBox()

    func body(content: Content) -> some View {
        let room = PopoverRoom.vertical(anchor: anchor.value, windowHeight: PopoverRoom.windowHeight)
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { [anchor] in anchor.value = $0 }
            .popover(isPresented: $isPresented, arrowEdge: room.edge) {
                popover().environment(\.popoverMaxHeight, room.maxHeight)
            }
    }
}

extension View {
    /// A popover that opens above or below its anchor, whichever has more room, and sizes
    /// its content (through `popoverMaxHeight`) so it never leaves the window.
    func windowBoundedPopover<Popover: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Popover) -> some View {
        modifier(WindowBoundedPopover(isPresented: isPresented, popover: content))
    }
}
