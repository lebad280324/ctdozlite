import Foundation
import Darwin

/// Bounds the output stream even when a child emits an invalid or unterminated frame.
public struct JSONLineDecoder {
    private var buffer = Data()
    private var scannedBytes = 0
    public let maximumFrameBytes: Int
    public init(maximumFrameBytes: Int = 8 * 1_024 * 1_024) { self.maximumFrameBytes = maximumFrameBytes }

    public mutating func append(_ chunk: Data) throws -> [CoreEvent] {
        guard chunk.count <= maximumFrameBytes, buffer.count <= maximumFrameBytes - chunk.count else {
            buffer.removeAll(keepingCapacity: false)
            scannedBytes = 0
            throw BridgeFailure.oversizedFrame
        }
        buffer.append(chunk)
        var events: [CoreEvent] = []
        while let newline = buffer.range(of: Data([0x0A]), in: buffer.index(buffer.startIndex, offsetBy: scannedBytes)..<buffer.endIndex)?.lowerBound {
            let frame = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            scannedBytes = 0
            if !frame.isEmpty { events.append(try JSONDecoder().decode(CoreEvent.self, from: frame)) }
        }
        scannedBytes = buffer.count
        return events
    }
}

public enum BridgeFailure: LocalizedError {
    case missingCore, oversizedFrame, invalidFrame, disconnected, launchFailed
    public var errorDescription: String? {
        switch self {
        case .missingCore: return "Không tìm thấy bộ xử lý. Hãy mở ứng dụng từ bản đóng gói đầy đủ."
        case .oversizedFrame: return "Dữ liệu trả về quá lớn. Hãy tải lại cuộc trò chuyện."
        case .invalidFrame: return "Không đọc được dữ liệu từ bộ xử lý. Hãy khởi động lại ứng dụng."
        case .disconnected: return "Kết nối với bộ xử lý đã dừng. Hãy khởi động lại ứng dụng."
        case .launchFailed: return "Không khởi động được bộ xử lý. Hãy kiểm tra lại bản cài đặt."
        }
    }
}

/// A single serial queue owns the child, its pipes and framing; the UI only sends intents.
public final class CoreProcess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "vn.ctdo.native.core", qos: .userInitiated)
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var diagnostics: FileHandle?
    private var decoder = JSONLineDecoder()
    private var stopping = false
    private var stopCompletion: (@Sendable () -> Void)?
    private let onEvent: @Sendable (CoreEvent) -> Void
    private let onFailure: @Sendable (String) -> Void

    public init(onEvent: @escaping @Sendable (CoreEvent) -> Void,
                onFailure: @escaping @Sendable (String) -> Void) {
        self.onEvent = onEvent; self.onFailure = onFailure
    }

    public func start(coreURL: URL, dataDirectory: URL, demo: Bool) {
        queue.async { [weak self] in
            guard let self, self.process == nil else { return }
            do {
                guard FileManager.default.isExecutableFile(atPath: coreURL.path) else { throw BridgeFailure.missingCore }
                try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let child = Process()
                let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                child.executableURL = coreURL
                child.arguments = ["--data-dir", dataDirectory.path] + (demo ? ["--demo"] : [])
                child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
                child.currentDirectoryURL = dataDirectory
                self.stopping = false
                self.decoder = JSONLineDecoder()
                self.input = stdin.fileHandleForWriting
                self.output = stdout.fileHandleForReading
                self.diagnostics = stderr.fileHandleForReading
                self.output?.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    self?.queue.async { [weak self] in self?.receive(data) }
                }
                // Diagnostic text may contain upstream payloads; drain it without displaying or retaining it.
                self.diagnostics?.readabilityHandler = { handle in _ = handle.availableData }
                child.terminationHandler = { [weak self] _ in
                    self?.queue.async { [weak self] in
                        guard let self else { return }
                        self.closePipes()
                        self.process = nil
                        if !self.stopping { self.onFailure(BridgeFailure.disconnected.localizedDescription) }
                        self.stopCompletion?()
                        self.stopCompletion = nil
                    }
                }
                self.process = child
                try child.run()
            } catch {
                self.process = nil
                self.closePipes()
                self.onFailure((error as? BridgeFailure ?? .launchFailed).localizedDescription)
            }
        }
    }

    public func send(id: String, command: String, parameters: [String: JSONValue] = [:]) {
        queue.async { [weak self] in
            guard let self, let input = self.input, self.process?.isRunning == true else {
                self?.onFailure(BridgeFailure.disconnected.localizedDescription)
                return
            }
            do {
                var body = parameters
                body["id"] = .string(id); body["command"] = .string(command)
                var data = try JSONEncoder().encode(body)
                data.append(0x0A)
                guard data.count <= 256 * 1_024 else {
                    self.onEvent(CoreEvent(id: id, event: "result", command: command, ok: false, data: nil,
                        error: "Nội dung thao tác quá lớn. Hãy rút ngắn nội dung hoặc gửi dưới dạng tệp."))
                    return
                }
                try input.write(contentsOf: data)
            } catch { self.onFailure(BridgeFailure.disconnected.localizedDescription) }
        }
    }

    public func stop(completion: @escaping @Sendable () -> Void = {}) {
        queue.async { [self] in
            guard let child = self.process, child.isRunning else {
                closePipes(); process = nil; completion(); return
            }
            self.stopCompletion = completion
            self.stopping = true
            // Closing stdin is an ownership signal, including while authentication is in progress.
            try? self.input?.close()
            self.input = nil
            self.queue.asyncAfter(deadline: .now() + 1) { [self, child] in
                if child.isRunning { child.terminate() }
                self.closePipes()
            }
            self.queue.asyncAfter(deadline: .now() + 2) { [child] in
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        do { for var event in try decoder.append(data) { try event.prepareForUI(); onEvent(event) } }
        catch {
            onFailure((error as? BridgeFailure ?? .invalidFrame).localizedDescription)
            stopping = true
            process?.terminate()
        }
    }

    private func closePipes() {
        output?.readabilityHandler = nil; diagnostics?.readabilityHandler = nil
        try? input?.close(); try? output?.close(); try? diagnostics?.close()
        input = nil; output = nil; diagnostics = nil
    }
}
