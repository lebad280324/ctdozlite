import SwiftUI

/// Width constraints shared by the workspace columns.
enum ConversationRegions {
    static func sidebarWidth(preferred:CGFloat,available:CGFloat)->CGFloat {
        min(preferred,max(220,available-360-24))
    }
}

/// The history fills the column; only its scroll endpoints reserve space for floating controls.
struct ConversationViewport<History: View, Header: View, Composer: View>: View {
    @ViewBuilder let history: (CGFloat, CGFloat) -> History
    @ViewBuilder let header: () -> Header
    @ViewBuilder let composer: () -> Composer
    @State private var topInset: CGFloat = 76
    @State private var bottomInset: CGFloat = 64

    var body: some View {
        history(topInset, bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                header().fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { topInset = $0 }
            }
            .overlay(alignment: .bottom) {
                composer().fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { bottomInset = $0 }
            }
            .clipped()
    }
}

/// Resize placement changes without feeding every window-size update back into the workspace body.
struct WorkspaceColumnsLayout:Layout {
    let sidebarWidth:CGFloat

    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout Void)->CGSize {
        CGSize(width:proposal.width ?? 1180,height:proposal.height ?? 760)
    }

    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout Void) {
        guard subviews.count == 3 else{return}
        let divider = subviews[1].sizeThatFits(ProposedViewSize(width:nil,height:bounds.height)).width
        let side = min(max(0,bounds.width-divider),ConversationRegions.sidebarWidth(preferred:sidebarWidth,available:bounds.width)+20)
        let widths = [side,divider,max(0,bounds.width-side-divider)]
        var x = bounds.minX
        for (view,width) in zip(subviews,widths) {
            view.place(at:CGPoint(x:x,y:bounds.minY),anchor:.topLeading,proposal:ProposedViewSize(width:width,height:bounds.height))
            x += width
        }
    }
}
