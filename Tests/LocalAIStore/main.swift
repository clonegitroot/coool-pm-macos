import Foundation

private struct Failure: Error { let description: String }
private func expectFailure(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw Failure(description: "Operation unexpectedly succeeded")
}

@main struct ModelStoreChecks {
    static func main() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("coool-ai-store-check-" + UUID().uuidString)
        defer { try? fm.removeItem(at: base) }
        let model = LocalAIModel.all[0]
        precondition(LocalAIModel.all.count == 3)
        precondition(LocalAIModel.all.allSatisfy { model in
            model.revision.count == 40 && model.assets.allSatisfy {
                $0.sha256.count == 64 && !$0.name.contains("/") && $0.bytes > 0
            }
        })
        precondition(!LocalAIModelStore.isInstalled(model, base: base))
        let directory = try LocalAIModelStore.modelURL(model, base: base)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker: [String: Any] = ["repository": model.repository, "revision": model.revision,
                                    "assets": model.assets.map { ["name": $0.name, "bytes": $0.bytes, "sha256": $0.sha256] as [String: Any] }]
        try JSONSerialization.data(withJSONObject: marker).write(to: directory.appendingPathComponent(".installed.json"))
        precondition(!LocalAIModelStore.isInstalled(model, base: base))
        // Sparse fixture files have correct sizes but invalid content, so checksum verification must reject them.
        for asset in model.assets {
            let file = directory.appendingPathComponent(asset.name)
            fm.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: UInt64(asset.bytes))
            try handle.close()
        }
        precondition(LocalAIModelStore.isInstalled(model, base: base))
        try expectFailure { try LocalAIModelStore.verifyInstalled(model, base: base) }
        let config = directory.appendingPathComponent("config.json")
        try fm.removeItem(at: config)
        try fm.createSymbolicLink(at: config, withDestinationURL: directory.appendingPathComponent("tokenizer.json"))
        precondition(!LocalAIModelStore.isInstalled(model, base: base))
        try LocalAIModelStore.remove(model, base: base)
        precondition(!fm.fileExists(atPath: directory.path))

        let store = LocalAIModelStore(base: base)
        let task = Task {
            try Task.checkCancellation()
            try await store.download(model: model) { _ in }
        }
        task.cancel()
        do { try await task.value; throw Failure(description: "Cancelled download succeeded") }
        catch is CancellationError {}
        precondition(!LocalAIModelStore.isInstalled(model, base: base))
        print("Verified pinned catalog, partial-install rejection, checksum rejection, symlink rejection, removal and cancellation.")
    }
}
