import Foundation

/// Presentation rules only: archive metadata and media URLs are never captions.
public enum MediaPresentation {
    /// Extensions that make a shared link a file card rather than a web preview.
    public static let fileExtensions: Set<String> = ["pdf","doc","docx","xls","xlsx","ppt","pptx","txt","rtf","csv","zip","rar","7z","tar","gz",
        "mp3","m4a","wav","mp4","mov","avi","mkv","psd","ai","sketch","fig","key","pages","numbers","apk","ipa","exe","dmg","pkg","json","xml","sql","md"]

    /// Some archives and older clients store a file as a link; recover the file name when it has one.
    public static func fileName(_ message: MessageSnapshot) -> String? {
        if let name = message.fileName, !name.isEmpty { return withoutSizeSuffix(name) }
        for candidate in [message.linkTitle, message.text].compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            let ext = (candidate as NSString).pathExtension.lowercased()
            if !candidate.contains("\n"), candidate.count <= 255, fileExtensions.contains(ext) { return candidate }
        }
        return nil
    }

    /// Sent files are named "report.docx (40.0 KB)"; the card shows the size separately.
    static func withoutSizeSuffix(_ name: String) -> String {
        guard name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) else { return name }
        let inner = name[open.upperBound..<name.index(before: name.endIndex)]
        let units = ["B", "KB", "MB", "GB"]
        let parts = inner.split(separator: " ")
        guard parts.count == 2, Double(parts[0].replacingOccurrences(of: ",", with: ".")) != nil, units.contains(String(parts[1])) else { return name }
        return String(name[..<open.lowerBound])
    }

    public static func fileURL(_ message: MessageSnapshot) -> String? {
        if let file = message.fileURL { return file }
        guard message.imageURL == nil, let link = message.linkURL, let url = safeWebURL(link) else { return nil }
        let host = url.host?.lowercased() ?? ""
        let pathExt = url.pathExtension.lowercased()
        return fileName(message) != nil || host.hasSuffix("dlfl.vn") || fileExtensions.contains(pathExt) ? link : nil
    }

    /// Zalo's placeholder text for a shared file, e.g. "[Tập tin] report.docx".
    static let filePlaceholder = "[Tập tin]"

    public static func caption(_ message: MessageSnapshot) -> String {
        let text=message.text.trimmingCharacters(in:.whitespacesAndNewlines)
        // The file card already shows the name; "[Tập tin] <name>" is not a caption.
        // "[Tập tin] <name>" is generated for every file (by Zalo or by this app when sending); the
        // card already shows the name, so it is never a caption, whatever the name's spelling.
        if fileURL(message) != nil, text.hasPrefix(filePlaceholder) { return "" }
        if message.fileURL == nil, fileURL(message) != nil, text == fileName(message) || text == message.linkURL { return "" }
        guard message.imageURL != nil || message.fileURL != nil else { return message.text }
        // "[Hình ảnh] Ảnh màn hình ….png" is the uploaded file's name, not something the sender wrote.
        if message.imageURL != nil, message.fileURL == nil, text.hasPrefix("[Hình ảnh]") || text.hasPrefix("[Ảnh]") {
            let rest = text.drop { $0 != "]" }.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "bmp", "tif", "tiff"]
            if rest.isEmpty || (!rest.contains("\n") && imageExtensions.contains((rest as NSString).pathExtension.lowercased())) { return "" }
        }
        if ["[Hình ảnh]","[Ảnh]","[Photo]","[Image]","[Nhãn dán]"].contains(text) { return "" }
        if text == message.imageURL || text == message.fileURL || text == message.linkURL { return "" }
        return message.text
    }
    public static func isBareImage(_ message: MessageSnapshot) -> Bool {
        message.imageURL != nil && message.fileURL == nil && caption(message).isEmpty && (message.replyToText ?? "").isEmpty
    }
    public static func showsLinkPreview(_ message: MessageSnapshot) -> Bool {
        message.imageURL == nil && fileURL(message) == nil && safeWebURL(message.linkURL) != nil
    }
}
