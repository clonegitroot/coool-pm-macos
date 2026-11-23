import AppKit
import Foundation

struct AIHardware {
    let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    var appleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
    var chip: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0 else { return "Mac" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &value, &size, nil, 0) == 0 else { return "Apple Silicon" }
        return String(cString: value)
    }
    var recommended: LocalAIModel {
        LocalAIModel.all.last { memoryGB >= $0.recommendedMemoryGB } ?? LocalAIModel.all[0]
    }
}

@MainActor
final class LocalAIController: ObservableObject {
    static let shared = LocalAIController()
    enum State: Equatable { case unloaded, loading, ready, generating, unloading, failed }
    @Published private(set) var state = State.unloaded
    @Published private(set) var loadedModelID: String?
    @Published private(set) var memoryBytes: UInt64 = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var downloadProgress = 0.0
    @Published private(set) var catalogRevision = 0

    private var loadOperationID: UUID?
    private var generationOperationID: UUID?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var pending: CheckedContinuation<String, Error>?
    private var requestID: String?
    private var requestText = ""
    private var timeout: Task<Void, Never>?
    private var scheduledPolicy: String?
    private var idleTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private let store = LocalAIModelStore()
    private var pressure: DispatchSourceMemoryPressure?
    private var stopWaiters = [CheckedContinuation<Void, Never>]()
    private var failureAfterStop: String?
    private var observers = [NSObjectProtocol]()

    var enabled: Bool { UserDefaults.standard.bool(forKey: "localAIEnabled") }
    var isBusy: Bool { state == .loading || state == .generating || state == .unloading }
    var isReady: Bool { state == .ready }
    var selectedModel: LocalAIModel {
        LocalAIModel.all.first { $0.id == UserDefaults.standard.string(forKey: "localAIModelID") } ?? AIHardware().recommended
    }
    var statusText: String {
        let key: String
        switch state {
        case .unloaded: key = "Model unloaded"
        case .loading: key = "Preparing local AI…"
        case .ready: key = "Ready"
        case .generating: key = "Generating…"
        case .unloading: key = "Releasing model memory…"
        case .failed: key = "Local AI needs attention"
        }
        return AppLanguage.currentText(key)
    }
    var idlePolicy: String { UserDefaults.standard.string(forKey: "localAIIdlePolicy") ?? "5" }

    init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.state == .ready { await self.unload() }
                else if source.data.contains(.critical), self.isBusy {
                    self.failureAfterStop = AppLanguage.currentText("Local AI stopped because available memory is low. Your brief is retained. Try the Lightweight model.")
                    self.cancel()
                }
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .cooolLibraryDidRestore, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        })
        source.resume()
        pressure = source
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.enabled { self.cancel(); self.cancelDownload() }
                else if let loaded = self.loadedModelID, loaded != self.selectedModel.id { self.cancel() }
                else if self.state == .ready && self.scheduledPolicy != self.idlePolicy { self.scheduleIdleUnload() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.process?.terminate() }
        })
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "localAIEnabled")
        if !enabled { cancel(); cancelDownload() }
        objectWillChange.send()
    }

    func select(_ model: LocalAIModel) async {
        guard !isBusy else { return }
        await unload()
        UserDefaults.standard.set(model.id, forKey: "localAIModelID")
        errorMessage = nil
        objectWillChange.send()
    }

    func download(_ model: LocalAIModel) {
        guard downloadingModelID == nil else { return }
        downloadingModelID = model.id
        downloadProgress = 0
        errorMessage = nil
        downloadTask = Task { [self] in
            defer { downloadingModelID = nil; downloadTask = nil; catalogRevision += 1 }
            do {
                try await store.download(model: model) { [weak self] fraction in
                    Task { @MainActor in self?.downloadProgress = fraction }
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func remove(_ model: LocalAIModel) async {
        guard !isBusy, downloadingModelID != model.id else { return }
        if loadedModelID == model.id { await unload() }
        do { try LocalAIModelStore.remove(model); catalogRevision += 1 }
        catch { errorMessage = error.localizedDescription }
    }

    func loadFromSettings() async {
        do { try await loadSelected() }
        catch is CancellationError {}
        catch { errorMessage = error.localizedDescription }
    }

    func loadSelected() async throws {
        guard enabled else { throw LibraryError(description: "Enable Local AI in Settings before using the assistant.") }
        let hardware = AIHardware()
        let model = selectedModel
        guard hardware.appleSilicon else { throw LibraryError(description: "Local AI requires an Apple Silicon Mac.") }
        guard hardware.memoryGB >= model.minMemoryGB else { throw LibraryError(description: "Choose a smaller model for this Mac’s memory.") }
        guard LocalAIModelStore.isInstalled(model) else {
            throw LibraryError(description: "Download the selected model in Settings → Local AI first.")
        }
        if state == .ready && loadedModelID == model.id { idleTask?.cancel(); scheduleIdleUnload(); return }
        guard !isBusy else { throw LibraryError(description: "Wait for the current AI task to finish.") }
        await unload()
        let operation = UUID()
        loadOperationID = operation
        defer { if loadOperationID == operation { loadOperationID = nil } }
        state = .loading
        errorMessage = nil
        do {
            try await Task.detached(priority: .utility) { try LocalAIModelStore.verifyInstalled(model) }.value
            try Task.checkCancellation()
            guard loadOperationID == operation, state == .loading, enabled else { throw CancellationError() }
            try launchHelper()
            _ = try await request(["command": "load", "modelPath": try LocalAIModelStore.modelURL(model).path])
            loadedModelID = model.id
            state = .ready
            scheduleIdleUnload()
        } catch {
            if loadOperationID == operation {
                if !(error is CancellationError) { failureAfterStop = error.localizedDescription }
                await unload()
            }
            throw error
        }
    }

    func generate(prompt: String, maxTokens: Int = 1600) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await loadSelected()
            idleTask?.cancel()
            guard state == .ready, enabled else { throw CancellationError() }
            let operation = UUID()
            generationOperationID = operation
            defer { if generationOperationID == operation { generationOperationID = nil } }
            state = .generating
            do {
                let answer = try await request(["command": "generate", "prompt": prompt, "maxTokens": min(2400, max(64, maxTokens)),
                                                "contextTokens": selectedModel.contextTokens])
                guard generationOperationID == operation else { throw CancellationError() }
                state = .ready
                if idlePolicy == "task" { await unload() } else { scheduleIdleUnload() }
                return answer
            } catch {
                if generationOperationID == operation {
                    if !(error is CancellationError) { failureAfterStop = error.localizedDescription }
                    await unload()
                }
                throw error
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func cancel() {
        loadOperationID = nil
        generationOperationID = nil
        idleTask?.cancel()
        finishRequest(.failure(CancellationError()))
        if process != nil {
            beginStop()
        } else {
            state = .unloaded
        }
    }

    func unload() async {
        idleTask?.cancel()
        finishRequest(.failure(CancellationError()))
        guard process != nil else {
            memoryBytes = 0
            loadedModelID = nil
            if let message = failureAfterStop { state = .failed; errorMessage = message; failureAfterStop = nil }
            else { state = .unloaded }
            return
        }
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
            beginStop()
        }
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        scheduledPolicy = idlePolicy
        guard state == .ready, idlePolicy != "keep" else { return }
        let seconds = idlePolicy == "task" ? 300 : (Double(idlePolicy) ?? 5) * 60
        idleTask = Task {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            if state == .ready { await unload() }
        }
    }

    private func launchHelper() throws {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "CooolPM-AI") else {
            throw LibraryError(description: "The Local AI helper is missing. Rebuild or reinstall Coool PM.")
        }
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = url
        child.currentDirectoryURL = url.deletingLastPathComponent()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self, weak child] _ in
            Task { @MainActor in
                guard let self, self.process === child else { return }
                self.helperExited()
            }
        }
        output = stdout.fileHandleForReading
        let descriptor = stdout.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        output?.readabilityHandler = { [weak self, weak child] handle in
            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = Darwin.read(handle.fileDescriptor, &bytes, 65_536)
            guard count >= 0 else { return }
            let data = Data(bytes.prefix(count))
            Task { @MainActor in if let self, self.process === child { self.received(data) } }
        }
        process = child
        input = stdin.fileHandleForWriting
        do { try child.run() }
        catch {
            output?.readabilityHandler = nil
            process = nil; input = nil; output = nil
            throw error
        }
    }

    private func request(_ payload: [String: Any]) async throws -> String {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            guard pending == nil, let input else { continuation.resume(throwing: CancellationError()); return }
            let id = UUID().uuidString
            requestID = id
            pending = continuation
            requestText = ""
            timeout = Task {
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
                failureAfterStop = AppLanguage.currentText("Local AI timed out. Try a shorter brief or a smaller model.")
                cancel()
            }
            do {
                var message = payload
                message["id"] = id
                try input.write(contentsOf: JSONSerialization.data(withJSONObject: message) + Data([10]))
            } catch {
                finishRequest(.failure(error))
            }
        }
    }

    private func received(_ data: Data) {
        guard process != nil else { return }
        guard !data.isEmpty else { output?.readabilityHandler = nil; return }
        buffer.append(data)
        guard buffer.count <= 1_048_576 else {
            failureAfterStop = AppLanguage.currentText("The AI response exceeded the supported size.")
            cancel()
            return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let reply = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  reply["id"] as? String == requestID, let kind = reply["type"] as? String else { continue }
            if let bytes = reply["memoryBytes"] as? UInt64 { memoryBytes = bytes }
            switch kind {
            case "token":
                if let text = reply["text"] as? String {
                    requestText += text
                    if requestText.utf8.count > 262_144 { cancel(); return }
                }
            case "loaded": finishRequest(.success(""))
            case "done":
                if let text = reply["text"] as? String { requestText = text }
                finishRequest(.success(requestText))
            case "error":
                let message = reply["message"] as? String ?? "Local AI could not complete this request."
                finishRequest(.failure(LibraryError(description: message)))
            default: break
            }
        }
    }

    private func finishRequest(_ result: Result<String, Error>) {
        timeout?.cancel()
        timeout = nil
        requestID = nil
        let continuation = pending
        pending = nil
        requestText = ""
        continuation?.resume(with: result)
    }

    private func beginStop() {
        guard let process else { return }
        state = .unloading
        output?.readabilityHandler = nil
        try? input?.close()
        input = nil
        if process.isRunning { process.terminate() }
        let pid = process.processIdentifier
        Task {
            try? await Task.sleep(for: .seconds(2))
            if self.process === process && process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func helperExited() {
        let expected = state == .unloading
        finishRequest(.failure(CancellationError()))
        output?.readabilityHandler = nil
        try? output?.close()
        output = nil; input = nil; process = nil
        buffer = Data()
        loadedModelID = nil
        memoryBytes = 0
        if let message = failureAfterStop {
            state = .failed; errorMessage = message; failureAfterStop = nil
        } else if expected { state = .unloaded }
        else { state = .failed; errorMessage = AppLanguage.currentText("The Local AI helper stopped. Try loading the model again.") }
        let waiters = stopWaiters
        stopWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}
