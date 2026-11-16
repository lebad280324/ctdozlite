import AppKit
import Foundation
import NativeBridge

/// Development-only visual QA exports synthetic content, never a signed-in account.
@MainActor
func exportDemoSnapshotIfRequested(_ store: AppStore) async {
    let args = ProcessInfo.processInfo.arguments
    if store.demo, args.contains("--qa-close-window") {
        // Background-mode QA: close the window the way the red button does, then stay alive.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.performClose(nil)
        return
    }
    guard store.demo, let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else { return }
    for _ in 0..<30 {
        if !store.threads.isEmpty && !store.selectedMessages.isEmpty { break }
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
    if let group = store.threads.first(where: { $0.isGroup }) { store.selectThread(group.id) }
    // Optional states for visual QA: details panel, contacts section and dark appearance.
    if args.contains("--snapshot-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
    if args.contains("--snapshot-details") { store.showingInspector = true }
    if args.contains("--snapshot-contacts") { store.showContacts() }
    if args.contains("--snapshot-call") {
        store.features.incomingCall = .object(["caller_name": .string("Người gọi minh họa"), "caller_id": .string("demo-person"), "is_video": .bool(true)])
    }
    if args.contains("--snapshot-viewer") {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("zalolite-viewer-sample.png")
        let size = NSSize(width: 900, height: 600)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemIndigo, .systemPink])?.draw(in: rect, angle: 35); return true
        }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: file)
            NotificationCenter.default.post(name: .openImageViewer, object: file)
        }
    }
    if args.contains("--snapshot-menu") {
        // The conversation view is rebuilt after selection; post once it is listening.
        try? await Task.sleep(nanoseconds: 800_000_000)
        NotificationCenter.default.post(name: .snapshotOpenMenu, object: nil)
    }
    if let index = args.firstIndex(of: "--snapshot-search"), args.indices.contains(index + 1) {
        NotificationCenter.default.post(name: .snapshotOpenSearch, object: args[index + 1])
    }
    if args.contains("--snapshot-emoji") { NotificationCenter.default.post(name: .snapshotOpenEmoji, object: nil) }
    // A QA background must not outlive the snapshot: demo shares the real app's preferences.
    let savedBackground = UserDefaults.standard.object(forKey: "nativeChatBackground")
    if let index = args.firstIndex(of: "--snapshot-background"), args.indices.contains(index + 1) {
        UserDefaults.standard.set(args[index + 1], forKey: "nativeChatBackground")
    }
    defer { UserDefaults.standard.set(savedBackground, forKey: "nativeChatBackground") }
    if args.contains("--snapshot-draft") {
        try? await Task.sleep(nanoseconds:300_000_000)
        let directory=store.dataDirectory
        let files=await Task.detached{()->[URL] in
            let report=directory.appendingPathComponent("Tài liệu minh họa.txt")
            try? Data("Bản xem trước đính kèm — dữ liệu mẫu.".utf8).write(to:report)
            let photo=directory.appendingPathComponent("sample-image.png")
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:72,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:384,bitsPerPixel:32)
            if let bitmap,let pixels=bitmap.bitmapData {for y in 0..<72 {for x in 0..<96 {let n=(y*96+x)*4;pixels[n]=UInt8(80+x);pixels[n+1]=UInt8(140+y);pixels[n+2]=220;pixels[n+3]=255}};if let png=bitmap.representation(using:.png,properties:[:]) {try? png.write(to:photo)}}
            return [photo,report]
        }.value
        store.addAttachments(files);store.quote=store.selectedMessages.first
        store.draft="Nội dung đang soạn rõ ràng, không lẫn tin nhắn phía sau."
    }
    let settingsPage = args.firstIndex(of: "--snapshot-settings").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    if let settingsPage {
        store.requestedSettingsPage = settingsPage
        // The app menu's ⌘, item is the supported way to open the SwiftUI Settings scene.
        if let item = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }),
           let menu = item.menu, let index = menu.items.firstIndex(of: item) {
            menu.performActionForItem(at: index)
        }
    }
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    // Demo history refreshes after selection; a sample file is added once it has settled.
    if args.contains("--snapshot-file"), let threadID = store.selectedThreadID,
       let sample = try? JSONDecoder().decode(MessageSnapshot.self, from: Data("""
       {"id":"demo-file","text":"[Tập tin] Bao_cao_tong_ket.docx","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"is_outgoing":true,"msg_type":"chat.link","link_url":"https://example.invalid/Bao_cao_tong_ket.docx","link_title":"Bao_cao_tong_ket.docx"}
       """.utf8)) {
        store.messages[threadID, default: []].append(sample)
        store.transcript.replace(store.messages[threadID] ?? [])
    }
    if args.contains("--snapshot-link"), let threadID = store.selectedThreadID,
       let sample = try? JSONDecoder().decode(MessageSnapshot.self, from: Data("""
       {"id":"demo-link","text":"https://example.com/helpdesk/new","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"is_outgoing":true,"msg_type":"chat.text","link_url":"https://example.com/helpdesk/new","link_title":"Tạo yêu cầu hỗ trợ"}
       """.utf8)) {
        store.messages[threadID, default: []].append(sample)
        store.transcript.replace(store.messages[threadID] ?? [])
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
    if args.contains("--snapshot-notices"), let threadID = store.selectedThreadID {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let rows = """
        [{"id":"demo-notice-pin","sender_name":"Hướng dẫn","text":"Hướng dẫn ghim 1 tin nhắn link Chào Anh/Chị, Phòng Quản trị Hệ thống...","timestamp":\(now - 3000),"is_outgoing":false,"msg_type":"chat.system"},
         {"id":"demo-notice-leave","sender_name":"Tôi","text":"Trần Thị Phương đã rời khỏi nhóm","timestamp":\(now - 2000),"is_outgoing":true,"msg_type":"chat.system"},
         {"id":"demo-reacted","sender_name":"Tôi","text":"Máy in tầng 5 hỏng nguồn rồi ạ","timestamp":\(now - 1000),"is_outgoing":true,"msg_type":"chat.text","reactions":["👍","❤️"],"reaction_details":[{"emoji":"👍","count":2,"reactors":["demo-guide","\(store.session.uin)"]},{"emoji":"❤️","count":1,"reactors":["demo-guide"]}]}]
        """
        if let samples = try? JSONDecoder().decode([MessageSnapshot].self, from: Data(rows.utf8)) {
            store.messages[threadID, default: []].append(contentsOf: samples)
            store.transcript.replace(store.messages[threadID] ?? [])
        }
        // The demo core has no server pins; inject after its empty refresh has returned.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if let pins = try? JSONDecoder().decode(JSONValue.self, from: Data("""
            [{"topic_id":"1","message_id":"","text":"https://docs.google.com/spreadsheets/d/demo","sender_name":"Hướng dẫn"},
             {"topic_id":"2","message_id":"","text":"Lịch trực kỹ thuật tháng 11","sender_name":"Hướng dẫn"}]
            """.utf8)) {
            store.features.pinnedTopics[threadID] = pins.featureRows
        }
        if args.contains("--snapshot-thread-menu") { NotificationCenter.default.post(name: .snapshotOpenThreadMenu, object: nil) }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        // Any late empty demo refresh is overwritten again before capture.
        if let pins = store.features.pinnedTopics[threadID], pins.isEmpty == false {} else if let pins = try? JSONDecoder().decode(JSONValue.self, from: Data("""
            [{"topic_id":"1","message_id":"","text":"https://docs.google.com/spreadsheets/d/demo","sender_name":"Hướng dẫn"},
             {"topic_id":"2","message_id":"","text":"Lịch trực kỹ thuật tháng 11","sender_name":"Hướng dẫn"}]
            """.utf8)) { store.features.pinnedTopics[threadID] = pins.featureRows }
        if args.contains("--snapshot-pins-open") { NotificationCenter.default.post(name: .showPinnedList, object: threadID) }
        try? await Task.sleep(nanoseconds: 700_000_000)
    }
    if args.contains("--snapshot-media"), let threadID = store.selectedThreadID {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let rows = """
        [{"id":"demo-voice","sender_name":"Hướng dẫn","text":"[Tập tin] 57a0.aac","timestamp":\(now - 5000),"is_outgoing":false,"msg_type":"share.file","file_url":"https://voice-aac-dl.example.invalid/57a0.aac","file_name":"57a0.aac"},
         {"id":"demo-video","sender_name":"Hướng dẫn","text":"[Tập tin] 2aObo","timestamp":\(now - 4000),"is_outgoing":false,"msg_type":"share.file","file_url":"https://video-stal-6.example.invalid/gr/2aObo","file_name":"2aObo"},
         {"id":"demo-maps","sender_name":"Hướng dẫn","text":"https://maps.app.goo.gl/demo","timestamp":\(now - 3000),"is_outgoing":false,"msg_type":"chat.text"},
         {"id":"demo-preview","sender_name":"Hướng dẫn","text":"Đầu nối nhanh thủy lực","timestamp":\(now - 2500),"is_outgoing":false,"msg_type":"chat.text","link_url":"https://shop.example.invalid/dau-noi","link_title":"https://shop.example.invalid/dau-noi","link_desc":"Đầu nối nhanh thủy lực","link_thumb":"https://example.invalid/thumb.jpg"},
         {"id":"demo-call-out","sender_name":"Tôi","text":"📞 Cuộc gọi đi (75s)","timestamp":\(now - 2000),"is_outgoing":true,"msg_type":"chat.text"},
         {"id":"demo-call-miss","sender_name":"Hướng dẫn","text":"📞 Cuộc gọi nhỡ","timestamp":\(now - 1000),"is_outgoing":false,"msg_type":"chat.text"}]
        """
        if let samples = try? JSONDecoder().decode([MessageSnapshot].self, from: Data(rows.utf8)) {
            store.messages[threadID, default: []].append(contentsOf: samples)
            store.transcript.replace(store.messages[threadID] ?? [])
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
    if args.contains("--snapshot-location"), let threadID = store.selectedThreadID,
       let sample = try? JSONDecoder().decode(MessageSnapshot.self, from: Data("""
       {"id":"demo-location","sender_name":"Hướng dẫn","text":"235 Lĩnh Nam, Hoàng Mai, Hà Nội","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"is_outgoing":false,"msg_type":"chat.location","link_url":"https://maps.google.com/maps?q=20.980000,105.875000&z=15","link_title":"235 Lĩnh Nam, Hoàng Mai, Hà Nội"}
       """.utf8)) {
        store.messages[threadID, default: []].append(sample)
        store.transcript.replace(store.messages[threadID] ?? [])
        try? await Task.sleep(nanoseconds: 2_500_000_000)
    }
    if args.contains("--snapshot-file") { try? await Task.sleep(nanoseconds: 800_000_000) }
    if args.contains("--snapshot-resize"), let threadID = store.selectedThreadID,
       let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.isVisible }) {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let rows = (0..<6).map { i in
            "{\"id\":\"demo-out-\(i)\",\"sender_name\":\"Tôi\",\"text\":\"Tin gửi số \(i) để kiểm tra co giãn\",\"timestamp\":\(now + i * 1000),\"is_outgoing\":true,\"msg_type\":\"chat.text\"}"
        }.joined(separator: ",")
        if let samples = try? JSONDecoder().decode([MessageSnapshot].self, from: Data("[\(rows)]".utf8)) {
            store.messages[threadID, default: []].append(contentsOf: samples)
            store.transcript.replace(store.messages[threadID] ?? [])
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        // Live resize: step the width down and back up, as a pointer drag on the edge does.
        let start = window.frame
        window.contentView?.viewWillStartLiveResize()
        let shrink: [CGFloat] = Array(stride(from: start.width, through: start.width - 360, by: -40))
        let grow: [CGFloat] = Array(stride(from: start.width - 360, through: start.width + 160, by: 40))
        for width in shrink + grow {
            window.setFrame(NSRect(x: start.minX, y: start.minY, width: width, height: start.height), display: true)
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        if args.contains("--snapshot-resize-end") { window.contentView?.viewDidEndLiveResize() }
        try? await Task.sleep(nanoseconds: 300_000_000)
        // Render the layer tree, which keeps stale layer contents a view redraw would hide.
        if let view = window.contentView?.superview, let layer = view.layer {
            let scale = window.backingScaleFactor
            let size = view.bounds.size
            if let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.scaleBy(x: scale, y: scale)
                layer.render(in: ctx)
                if let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: args[index + 1]))
                }
            }
        }
        return
    }
    let target = settingsPage == nil
        ? NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.isVisible })
        : NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue != "main" && $0.title != "Zalolite" && $0.frame.width > 500 })
    // The frame view includes the toolbar, which carries half of the workspace controls.
    guard let content = target?.contentView,
          let bitmap = (content.superview ?? content).bitmapImageRepForCachingDisplay(in: (content.superview ?? content).bounds) else { return }
    let view = content.superview ?? content
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
    let path = args[index + 1]
    _ = await Task.detached { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }.value
}

extension Notification.Name {
    /// Development-only: asks the open conversation to show its emoji picker for visual QA.
    static let snapshotOpenMenu = Notification.Name("vn.ctdo.native.snapshotOpenMenu")
    static let snapshotOpenSearch = Notification.Name("vn.ctdo.native.snapshotOpenSearch")
    static let snapshotOpenEmoji = Notification.Name("vn.ctdo.native.snapshotOpenEmoji")
    static let snapshotOpenThreadMenu = Notification.Name("vn.ctdo.native.snapshotOpenThreadMenu")
}
