import CryptoKit
import Foundation

/// Only pinned, data-only assets in LocalAIModel.all are downloaded. Project data never enters a request.
actor LocalAIModelStore {
    private let base: URL
    private var downloading = false

    init(base: URL? = nil) {
        self.base = base ?? Self.defaultBase
    }

    private static var defaultBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coool PM/AIModels", isDirectory: true)
    }

    static func rootURL() throws -> URL { defaultBase }
    static func modelURL(_ model: LocalAIModel) throws -> URL { try modelURL(model, base: defaultBase) }

    static func modelURL(_ model: LocalAIModel, base: URL) throws -> URL {
        guard LocalAIModel.all.contains(model) else { throw StoreError.invalidCatalog }
        return base.appendingPathComponent(model.id, isDirectory: true)
    }

    private struct Installation: Codable, Equatable {
        let repository: String
        let revision: String
        let assets: [LocalAIModel.Asset]
        init(_ model: LocalAIModel) {
            repository = model.repository
            revision = model.revision
            assets = model.assets
        }
    }

    static func isInstalled(_ model: LocalAIModel) -> Bool {
        isInstalled(model, base: defaultBase)
    }
    static func isInstalled(_ model: LocalAIModel, base: URL) -> Bool {
        (try? checkInstallation(model, base: base, hashes: false)) != nil
    }

    static func verifyInstalled(_ model: LocalAIModel) throws {
        try verifyInstalled(model, base: defaultBase)
    }
    static func verifyInstalled(_ model: LocalAIModel, base: URL) throws {
        try checkInstallation(model, base: base, hashes: true)
    }

    private static func checkInstallation(_ model: LocalAIModel, base: URL, hashes: Bool) throws {
        let folder = try modelURL(model, base: base)
        guard try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isSymbolicLink != true else {
            throw StoreError.invalidInstallation
        }
        let marker = folder.appendingPathComponent(".installed.json")
        let actual = try JSONDecoder().decode(Installation.self, from: Data(contentsOf: marker))
        guard actual == Installation(model) else { throw StoreError.invalidInstallation }
        for asset in model.assets {
            try Task.checkCancellation()
            let file = folder.appendingPathComponent(asset.name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize.map(Int64.init) == asset.bytes else { throw StoreError.invalidInstallation }
            if hashes, try sha256(of: file) != asset.sha256 { throw StoreError.checksum }
        }
    }

    private static func sha256(of file: URL) throws -> String {
        let stream = try FileHandle(forReadingFrom: file)
        defer { try? stream.close() }
        var hasher = SHA256()
        while let data = try stream.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func download(model: LocalAIModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        try Task.checkCancellation()
        guard !downloading else { throw StoreError.busy }
        downloading = true
        defer { downloading = false }
        let destination = try Self.modelURL(model, base: base)
        if Self.isInstalled(model, base: base) {
            try Self.verifyInstalled(model, base: base)
            progress(1)
            return
        }
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = try DownloadLock(folder: base, model: model)
        defer { withExtendedLifetime(lock) {} }
        let abandonedPrefix = ".download-" + model.id + "-"
        for old in try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            where old.lastPathComponent.hasPrefix(abandonedPrefix) {
            try fm.removeItem(at: old)
        }
        let resource = try base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let largest = model.assets.map(\.bytes).max() ?? 0
        if let free = resource.volumeAvailableCapacityForImportantUsage,
           free < model.downloadBytes + largest + 536_870_912 { throw StoreError.diskSpace }

        let stage = base.appendingPathComponent(abandonedPrefix + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 7200
        var completed: Int64 = 0
        for asset in model.assets {
            try Task.checkCancellation()
            guard !asset.name.contains("/"), !asset.name.hasPrefix("."),
                  ["json", "safetensors", "txt"].contains(URL(fileURLWithPath: asset.name).pathExtension),
                  let url = URL(string: "https://huggingface.co/\(model.repository)/resolve/\(model.revision)/\(asset.name)") else {
                throw StoreError.invalidCatalog
            }
            let observer = DownloadProgress(completed: completed, total: model.downloadBytes, report: progress)
            let temporary = stage.appendingPathComponent(".partial-" + asset.name)
            defer { try? fm.removeItem(at: temporary) }
            let response = try await observer.download(url, configuration: configuration, destination: temporary)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw StoreError.network }
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
            guard size == asset.bytes, try Self.sha256(of: temporary) == asset.sha256 else { throw StoreError.checksum }
            try fm.moveItem(at: temporary, to: stage.appendingPathComponent(asset.name))
            completed += asset.bytes
            progress(Double(completed) / Double(model.downloadBytes))
        }
        try Task.checkCancellation()
        let marker = try JSONEncoder().encode(Installation(model))
        try marker.write(to: stage.appendingPathComponent(".installed.json"), options: .atomic)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: stage)
        } else {
            try fm.moveItem(at: stage, to: destination)
        }
        progress(1)
    }

    static func remove(_ model: LocalAIModel) throws { try remove(model, base: defaultBase) }
    static func remove(_ model: LocalAIModel, base: URL) throws {
        let directory = try modelURL(model, base: base)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let lock = try DownloadLock(folder: base, model: model)
        defer { withExtendedLifetime(lock) {} }
        try FileManager.default.removeItem(at: directory)
    }

    enum StoreError: LocalizedError {
        case invalidCatalog, invalidInstallation, checksum, busy, diskSpace, network
        var errorDescription: String? {
            let message = switch self {
            case .invalidCatalog: "This model is not in the verified download catalog."
            case .invalidInstallation: "The downloaded model is incomplete. Remove it and download it again."
            case .checksum: "The model failed its integrity check. Download it again."
            case .busy: "A model download is already running. Cancel it or wait for it to finish."
            case .diskSpace: "There is not enough free disk space to download and verify this model."
            case .network: "The model server could not provide this file. Try the download again."
            }
            return AppLanguage.currentText(message)
        }
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let completed: Int64
    let total: Int64
    let report: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastReport = Date.distantPast
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var destination: URL?
    private var transferError: Error?
    private var cancelled = false
    init(completed: Int64, total: Int64, report: @escaping @Sendable (Double) -> Void) {
        self.completed = completed
        self.total = total
        self.report = report
    }
    // Use the session delegate with an explicit task. The async download API can
    // consume download callbacks itself, leaving its per-task delegate at 0%.
    func download(_ url: URL, configuration: URLSessionConfiguration, destination: URL) async throws -> URLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    self.destination = destination
                    let queue = OperationQueue()
                    queue.maxConcurrentOperationCount = 1
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                    self.session = session
                    let task = session.downloadTask(with: url)
                    self.task = task
                    task.resume()
                }
            }
        } onCancel: {
            self.lock.withLock { self.cancelled = true; self.task?.cancel() }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let destination else { throw CancellationError() }
            // URLSession removes its temporary file when this callback returns.
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { transferError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = lock.withLock {
            let value = self.continuation
            self.continuation = nil
            self.task = nil
            self.session = nil
            return value
        }
        session.finishTasksAndInvalidate()
        if let error = transferError ?? error { continuation?.resume(throwing: error) }
        else if let response = task.response { continuation?.resume(returning: response) }
        else { continuation?.resume(throwing: LocalAIModelStore.StoreError.network) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let shouldReport = lock.withLock {
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= 0.1 else { return false }
            lastReport = now
            return true
        }
        if shouldReport { report(min(0.999, Double(completed + totalBytesWritten) / Double(total))) }
    }
}

private final class DownloadLock {
    private let fd: Int32
    init(folder: URL, model: LocalAIModel) throws {
        fd = Darwin.open(folder.appendingPathComponent("." + model.id + ".lock").path,
                         O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw LocalAIModelStore.StoreError.busy
        }
    }
    deinit { close(fd) }
}
