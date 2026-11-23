import Foundation
final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Error>?
    private var progressed = false
    func record(_ fraction: Double) { lock.withLock { if fraction > 0.01 && fraction < 0.2 { progressed = true } } }
    var sawLiveProgress: Bool { lock.withLock { progressed } }
    func set(_ value: Task<Void, Error>) { lock.withLock { task = value } }
    func cancel() { lock.withLock { task?.cancel() } }
}
@main struct CancelFixture {
    static func main() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("coool-ai-progress-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = LocalAIModelStore(base: base)
        let box = CancelBox()
        let task = Task {
            try await store.download(model: LocalAIModel.all[0]) { progress in
                box.record(progress)
                if progress > 0.01 && progress < 0.2 { box.cancel() }
            }
        }
        box.set(task)
        do { try await task.value; fatalError("Interrupted download unexpectedly succeeded") }
        catch { if !task.isCancelled { throw error } }
        let remains = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        precondition(!remains.contains { $0.lastPathComponent.hasPrefix(".download-") })
        precondition(box.sawLiveProgress, "Progress must update during the weights transfer, not only after it finishes")
        precondition(!LocalAIModelStore.isInstalled(LocalAIModel.all[0], base: base))
        print("Verified live progress during weights transfer, cancellation and partial-file cleanup.")
    }
}
