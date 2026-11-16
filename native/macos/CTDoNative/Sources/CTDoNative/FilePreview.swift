import AppKit
import SwiftUI
import Quartz
import QuickLookThumbnailing
import UniformTypeIdentifiers
import NativeBridge

/// Shows local files in the system Quick Look panel; previews need no extra library.
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var items: [URL] = []

    func show(_ url: URL) {
        items = [url]
        guard let panel = QLPreviewPanel.shared() else { NSWorkspace.shared.open(url); return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { items.count }
    }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { items[index] as NSURL }
    }
}

@MainActor
extension AppStore {
    /// Private cache for previews, inside this account's data folder.
    var previewDirectory: URL { dataDirectory.appendingPathComponent("previews", isDirectory: true) }

    /// A file already on disk for this message: a saved copy first, then the preview cache.
    func localCopy(of message: MessageSnapshot) -> URL? {
        let saved = (UserDefaults.standard.dictionary(forKey: "nativeDownloadedFiles") as? [String: String])?[message.id]
        let preview = previewDirectory.appendingPathComponent(message.id, isDirectory: true)
            .appendingPathComponent(MediaPresentation.fileName(message) ?? "tep")
        for candidate in [MediaSource.local(message), saved.map { URL(fileURLWithPath: $0) }, preview].compactMap({ $0 })
        where FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        return nil
    }

    /// Opens Quick Look, fetching the file into the preview cache through the worker first.
    func previewFile(_ message: MessageSnapshot) {
        if let local = localCopy(of: message) { QuickLookController.shared.show(local); return }
        guard supports("download_media"), let remote = MediaPresentation.fileURL(message) else { return }
        let folder = previewDirectory.appendingPathComponent(message.id, isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { self.error = "Không tạo được thư mục xem trước."; return }
        let name = MediaPresentation.fileName(message) ?? "tep"
        pendingPreviews[folder.appendingPathComponent(name).path] = message.id
        features.notification = "Đang chuẩn bị xem trước…"
        send("download_media", parameters: ["url": .string(remote), "file_name": .string(name), "directory": .string(folder.path)])
    }

    /// Saves to the chosen folder and remembers where, for "Mở trong thư mục".
    func saveFile(_ message: MessageSnapshot) {
        guard supports("download_media"), let remote = MediaPresentation.fileURL(message) else { return }
        let name = MediaPresentation.fileName(message) ?? "tep"
        let start: (URL) -> Void = { [weak self] folder in
            guard let self else { return }
            self.pendingSaves[folder.appendingPathComponent(name).path] = message.id
            self.send("download_media", parameters: ["url": .string(remote), "file_name": .string(name), "directory": .string(folder.path)])
        }
        var isDirectory: ObjCBool = false
        if let saved = UserDefaults.standard.string(forKey: "nativeDownloadDirectory"), !saved.isEmpty,
           FileManager.default.fileExists(atPath: saved, isDirectory: &isDirectory), isDirectory.boolValue {
            start(URL(fileURLWithPath: saved, isDirectory: true)); return
        }
        let panel = NSOpenPanel(); panel.title = "Chọn thư mục lưu tệp"; panel.prompt = "Lưu vào đây"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in start(folder) }
        }
    }

    /// Called for every finished download; opens previews and records saved locations.
    func completeFileDownload(path: String) {
        if pendingPreviews.removeValue(forKey: path) != nil {
            features.notification = ""
            QuickLookController.shared.show(URL(fileURLWithPath: path))
        }
        if let messageID = pendingSaves.removeValue(forKey: path) {
            var saved = UserDefaults.standard.dictionary(forKey: "nativeDownloadedFiles") as? [String: String] ?? [:]
            saved[messageID] = path
            if saved.count > 2_000 { saved = Dictionary(uniqueKeysWithValues: saved.suffix(2_000).map { ($0.key, $0.value) }) }
            UserDefaults.standard.set(saved, forKey: "nativeDownloadedFiles")
            fileDownloadsVersion += 1
        }
    }
}

/// File message card: type icon or thumbnail, name, and preview / reveal / save actions.
struct FileCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.transcriptColumnWidth) private var columnWidth
    private var cardWidth:CGFloat {min(260,max(100,(columnWidth-32)*0.78))}
    let message: MessageSnapshot
    let remote: URL
    @State private var thumbnail: NSImage?
    private var name: String { MediaPresentation.fileName(message) ?? remote.lastPathComponent }
    private var ext: String { (name as NSString).pathExtension.uppercased() }
    private var local: URL? { _ = store.fileDownloadsVersion; return store.localCopy(of: message) }
    private var icon: NSImage {
        NSWorkspace.shared.icon(for: UTType(filenameExtension: (name as NSString).pathExtension) ?? .data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { store.previewFile(message) } label: {
                ZStack {
                    LinearGradient(colors: [Color.primary.opacity(0.05), Color.primary.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    }
                }
                .frame(width:cardWidth,height:cardWidth*132/260).clipped()
                .overlay(alignment: .topLeading) {
                    if !ext.isEmpty {
                        Text(ext).font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule()).padding(8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Xem nhanh (không cần tải về)")
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: name).font(.system(size: 13, weight: .semibold)).lineLimit(2).truncationMode(.middle)
                Text(local == nil ? "Chưa tải về · \(remote.host ?? "")" : "Đã có trên máy").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    action("eye", "Xem trước") { store.previewFile(message) }
                    if let local {
                        action("folder", "Mở thư mục") { NSWorkspace.shared.activateFileViewerSelecting([local]) }
                        action("arrow.up.forward.app", "Mở") { NSWorkspace.shared.open(local) }
                    } else {
                        action("arrow.down.circle", "Tải về") { store.saveFile(message) }
                    }
                }
            }
            .padding(12)
        }
        .frame(width:cardWidth)
        .background(Color.bubbleIncoming, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
        .task(id: local?.path) { await loadThumbnail() }
        .contextMenu {
            Button("Xem trước") { store.previewFile(message) }
            Button("Tải về…") { store.saveFile(message) }
            if let local { Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([local]) } }
            Button("Mở bằng trình duyệt") { NSWorkspace.shared.open(remote) }
            Button("Sao chép liên kết") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(remote.absoluteString, forType: .string) }
        }
    }

    private func action(_ icon: String, _ title: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain)
    }

    /// Thumbnails are generated from a local copy only; remote files keep their type icon.
    private func loadThumbnail() async {
        guard let local else { thumbnail = nil; return }
        let request = QLThumbnailGenerator.Request(fileAt: local, size: CGSize(width: 260, height: 132), scale: 2, representationTypes: .thumbnail)
        thumbnail = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }
}
