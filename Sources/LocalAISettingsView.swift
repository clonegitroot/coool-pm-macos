import SwiftUI

struct LocalAISettingsView: View {
    @ObservedObject private var ai = LocalAIController.shared
    @AppStorage("localAIEnabled") private var enabled = false
    @AppStorage("localAIIdlePolicy") private var idlePolicy = "5"
    @State private var removing: LocalAIModel?
    @State private var downloading: LocalAIModel?
    @Environment(\.locale) private var locale
    private let hardware = AIHardware()

    var body: some View {
        Section {
            Toggle("Enable Local AI", isOn: Binding(get: { enabled }, set: { ai.setEnabled($0); enabled = $0 }))
                .disabled(!hardware.appleSilicon)
            Text("Download a model once, then generate on this Mac. Briefs and project context are processed locally. Suggestions are reviewed before applying.")
                .font(.callout).foregroundStyle(.secondary)
            Text("\(hardware.chip) · \(hardware.memoryGB) GB unified memory").font(.caption)
            if !hardware.appleSilicon { Text("Local AI requires an Apple Silicon Mac.").foregroundStyle(.secondary) }
            Text("Memory and quality guidance is an estimate. Available memory, brief length and other running apps affect performance.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Models") {
            ForEach(LocalAIModel.all) { model in
                modelCard(model)
            }
        }
        Section("Model memory") {
            LabeledContent("Status", value: ai.statusText)
            if let loaded = ai.loadedModelID, let model = LocalAIModel.all.first(where: { $0.id == loaded }) {
                Text(model.displayName).font(.callout)
            }
            if ai.memoryBytes > 0 {
                LabeledContent("Model allocations", value: ByteCountFormatter.string(fromByteCount: Int64(ai.memoryBytes), countStyle: .memory))
                Text("Reported model allocations exclude some process and system memory.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Unload model", selection: $idlePolicy) {
                Text("After every task").tag("task")
                Text("After 2 minutes idle").tag("2")
                Text("After 5 minutes idle").tag("5")
                Text("After 15 minutes idle").tag("15")
                Text("Keep loaded while open").tag("keep")
            }
            HStack {
                Button("Load selected model") { Task { await ai.loadFromSettings() } }
                    .disabled(!enabled || ai.isBusy || !LocalAIModelStore.isInstalled(ai.selectedModel))
                if ai.isBusy {
                    Button("Cancel AI task") { ai.cancel() }.disabled(ai.state == .unloading)
                } else {
                    Button("Unload now") { Task { await ai.unload() } }.disabled(!ai.isReady)
                }
            }
            Text("Idle models are released under memory pressure. Quitting releases the model. Downloaded files remain available.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = ai.errorMessage {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .confirmationDialog("Remove downloaded model?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { model in
            Button("Remove model", role: .destructive) { Task { await ai.remove(model) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("You can download it again later. Project data stays in your encrypted library.") }
        .confirmationDialog("Download local AI model?", isPresented: Binding(get: { downloading != nil }, set: { if !$0 { downloading = nil } }),
                            titleVisibility: .visible, presenting: downloading) { model in
            Button("Download") { ai.download(model) }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("Downloads \(ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file)) from Hugging Face. Only model files are requested. No project data is sent. Model license: Apache 2.0.")
        }
    }

    private func modelCard(_ model: LocalAIModel) -> some View {
        let installed = LocalAIModelStore.isInstalled(model)
        let selected = ai.selectedModel.id == model.id
        let eligible = hardware.appleSilicon && hardware.memoryGB >= model.minMemoryGB
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.displayName).font(.headline)
                Spacer()
                if hardware.recommended.id == model.id { Text("Recommended for your Mac").font(.caption).foregroundStyle(.tint) }
            }
            HStack {
                Text(LocalizedStringKey(model.tier)).font(.callout.weight(.medium))
                Spacer()
                if let url = URL(string: "https://huggingface.co/" + model.repository) {
                    Link("Model and license", destination: url).font(.caption)
                }
            }
            Text(LocalizedStringKey(model.detail)).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file)) download · about \(model.estimatedMemoryGB.formatted(.number.locale(locale))) GB working memory")
                .font(.caption).foregroundStyle(.secondary)
            if !eligible { Text("Choose a smaller model for this Mac’s memory.").font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(selected ? "Selected" : "Select model") { Task { await ai.select(model) } }
                    .disabled(selected || ai.isBusy || !eligible)
                if ai.downloadingModelID == model.id {
                    ProgressView(value: ai.downloadProgress).frame(maxWidth: 140)
                    Text(ai.downloadProgress, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit())
                    Button("Cancel download") { ai.cancelDownload() }
                } else if installed {
                    Text("Downloaded").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove…", role: .destructive) { removing = model }
                        .disabled(ai.isBusy)
                } else {
                    Button("Download model…") { downloading = model }
                        .disabled(!enabled || !eligible || ai.downloadingModelID != nil)
                }
            }
        }.padding(.vertical, 8)
    }
}
