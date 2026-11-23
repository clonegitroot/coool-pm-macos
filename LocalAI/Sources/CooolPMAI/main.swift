import Foundation
import MLX
import MLXLLM
import MLXLMCommon

private struct Request: Decodable {
    let id: String
    let command: String
    let modelPath: String?
    let prompt: String?
    let maxTokens: Int?
    let contextTokens: Int?
}

private let instructions = "You are a careful creative production assistant. Follow the requested JSON schema exactly. Output only one valid JSON object, with all required keys. Never add a preamble, markdown or code fences."

private func reply(_ value: [String: Any]) {
    guard let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(bytes + Data([10]))
}

@main
private struct InferenceHelper {
    static func main() async {
        // Disable native crash dumps for this process because model inputs may contain private records.
        var coreLimit = rlimit(rlim_cur: 0, rlim_max: 0)
        _ = setrlimit(RLIMIT_CORE, &coreLimit)
        GPU.set(cacheLimit: 64 * 1024 * 1024)
        var model: ModelContainer?
        while let line = readLine() {
            guard line.utf8.count <= 512 * 1024,
                  let request = try? JSONDecoder().decode(Request.self, from: Data(line.utf8)) else {
                reply(["id": "", "type": "error", "message": "Invalid local AI request."])
                continue
            }
            do {
                switch request.command {
                case "load":
                    guard model == nil, let path = request.modelPath else { throw HelperError.invalidRequest }
                    let url = URL(fileURLWithPath: path, isDirectory: true)
                    for name in ["config.json", "tokenizer.json", "tokenizer_config.json"] {
                        guard FileManager.default.isReadableFile(atPath: url.appendingPathComponent(name).path) else {
                            throw HelperError.missingModel
                        }
                    }
                    // The directory API parses safetensors/configuration and never runs repository code.
                    model = try await loadModelContainer(directory: url)
                    reply(["id": request.id, "type": "loaded", "memoryBytes": GPU.activeMemory + GPU.cacheMemory])
                case "generate":
                    guard let model, let prompt = request.prompt, !prompt.isEmpty else { throw HelperError.missingModel }
                    let maxTokens = min(max(request.maxTokens ?? 1400, 16), 4096)
                    let contextTokens = min(max(request.contextTokens ?? 4096, 1024), 8192)
                    let count = try await model.perform { @Sendable context in
                        let input = try await context.processor.prepare(input: UserInput(
                            chat: [.system(instructions), .user(prompt)], additionalContext: ["enable_thinking": false]))
                        return input.text.tokens.size
                    }
                    guard count + maxTokens <= contextTokens else { throw HelperError.contextTooLong }
                    // Start a new session for every action so one project's context never leaks into another.
                    let session = ChatSession(model, instructions: instructions,
                        generateParameters: GenerateParameters(
                        maxTokens: maxTokens, maxKVSize: contextTokens, temperature: 0.7,
                        topP: 0.8), additionalContext: ["enable_thinking": false])
                    for try await token in session.streamResponse(to: prompt) {
                        reply(["id": request.id, "type": "token", "text": token])
                    }
                    session.clear()
                    GPU.clearCache()
                    reply(["id": request.id, "type": "done", "memoryBytes": GPU.activeMemory + GPU.cacheMemory])
                case "unload":
                    model = nil
                    GPU.clearCache()
                    reply(["id": request.id, "type": "unloaded", "memoryBytes": 0])
                    return
                default: throw HelperError.invalidRequest
                }
            } catch let error as HelperError {
                reply(["id": request.id, "type": "error", "message": error.message])
            } catch {
                // Runtime diagnostics must never echo the prompt, configuration contents or source document paths.
                reply(["id": request.id, "type": "error", "message": "Local model processing failed. Check the download or choose a smaller model."])
            }
        }
    }
}

private enum HelperError: Error {
    case invalidRequest, missingModel, contextTooLong
    var message: String {
        switch self {
        case .invalidRequest: "Invalid local AI request."
        case .missingModel: "The model is unavailable or its download is incomplete."
        case .contextTooLong: "The brief and selected project context exceed this model’s context limit. Shorten the brief or remove a reference project."
        }
    }
}
