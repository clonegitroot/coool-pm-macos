import Foundation

struct LocalAIModel: Identifiable, Equatable, Sendable {
    struct Asset: Codable, Equatable, Sendable {
        let name: String
        let bytes: Int64
        let sha256: String
    }

    let id: String
    let displayName: String
    let tier: String
    let detail: String
    let repository: String
    let revision: String
    let minMemoryGB: Int
    let recommendedMemoryGB: Int
    let estimatedMemoryGB: Double
    let contextTokens: Int
    let assets: [Asset]

    var downloadBytes: Int64 { assets.reduce(0) { $0 + $1.bytes } }

    static let all: [Self] = [
        Self(id: "qwen3-1.7b", displayName: "Qwen3 1.7B · 4-bit", tier: "Lightweight",
             detail: "Quick wording and short drafts. Needs more guidance for complex estimates. Long briefs may exceed its context limit.",
             repository: "mlx-community/Qwen3-1.7B-4bit", revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e",
             minMemoryGB: 8, recommendedMemoryGB: 8, estimatedMemoryGB: 2.8, contextTokens: 4096,
             assets: [
                Asset(name: "added_tokens.json", bytes: 707, sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"),
                Asset(name: "config.json", bytes: 937, sha256: "507a6701220524eb8b283425bf0856a9ae4f21f4052e563896ddd668994b1dc7"),
                Asset(name: "merges.txt", bytes: 1671853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
                Asset(name: "model.safetensors", bytes: 968080210, sha256: "0e86d9677e519323849eac1bc272caae88567a481ff188c431f70be543d9995f"),
                Asset(name: "model.safetensors.index.json", bytes: 49731, sha256: "1e3058d4ba4b04e4de35b74467725cbef90ff022198404218e48f21adc9cfa15"),
                Asset(name: "special_tokens_map.json", bytes: 613, sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"),
                Asset(name: "tokenizer.json", bytes: 11422654, sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"),
                Asset(name: "tokenizer_config.json", bytes: 9706, sha256: "253153d0738ceb4c668d2eff957714dd2bea0b56de772a9fdccd96cbf517e6a0"),
                Asset(name: "vocab.json", bytes: 2776833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
             ]),
        Self(id: "qwen3-4b", displayName: "Qwen3 4B · 4-bit", tier: "Balanced",
             detail: "More detailed proposal drafts and scope reviews. Uses more memory and takes longer to respond.",
             repository: "mlx-community/Qwen3-4B-4bit", revision: "4dcb3d101c2a062e5c1d4bb173588c54ea6c4d25",
             minMemoryGB: 16, recommendedMemoryGB: 16, estimatedMemoryGB: 5.0, contextTokens: 4096,
             assets: [
                Asset(name: "added_tokens.json", bytes: 707, sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"),
                Asset(name: "config.json", bytes: 937, sha256: "b5efdcf3b0035a3638e7228dad4d85f5c4a23f156eb7cdb0b44c8366a5d34d9b"),
                Asset(name: "merges.txt", bytes: 1671853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
                Asset(name: "model.safetensors", bytes: 2263022529, sha256: "e240c0bdc0ebb0681bf0da0f98d9719fd6ebe269a3633f81542c13e81345651d"),
                Asset(name: "model.safetensors.index.json", bytes: 63924, sha256: "f7825defe5865d179c3b593173d37056be5f202dcb7153985cf74e75ecf1628b"),
                Asset(name: "special_tokens_map.json", bytes: 613, sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"),
                Asset(name: "tokenizer.json", bytes: 11422654, sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"),
                Asset(name: "tokenizer_config.json", bytes: 9706, sha256: "253153d0738ceb4c668d2eff957714dd2bea0b56de772a9fdccd96cbf517e6a0"),
                Asset(name: "vocab.json", bytes: 2776833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
             ]),
        Self(id: "qwen3-8b", displayName: "Qwen3 8B · 4-bit", tier: "Higher quality",
             detail: "For more demanding scope reviews. Highest memory use and slower responses; needs room alongside your other apps.",
             repository: "mlx-community/Qwen3-8B-4bit", revision: "545dc4251c05440727734bcd94334791f6ab0192",
             minMemoryGB: 24, recommendedMemoryGB: 24, estimatedMemoryGB: 8.0, contextTokens: 4096,
             assets: [
                Asset(name: "added_tokens.json", bytes: 707, sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"),
                Asset(name: "config.json", bytes: 939, sha256: "e5485285fd7e289e76e9cffa112f6dc2e3426519082f7db9b69041589f81a218"),
                Asset(name: "merges.txt", bytes: 1671853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
                Asset(name: "model.safetensors", bytes: 4607835174, sha256: "f2d29621aab300336ad645567ff38c42aac755513006ef4e8a579cf7ef5256d8"),
                Asset(name: "model.safetensors.index.json", bytes: 64065, sha256: "3fb25463b4078b1fc27159daa605190029c2e965f533bf0b1b594f96cbfceb8a"),
                Asset(name: "special_tokens_map.json", bytes: 613, sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"),
                Asset(name: "tokenizer.json", bytes: 11422654, sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"),
                Asset(name: "tokenizer_config.json", bytes: 9706, sha256: "253153d0738ceb4c668d2eff957714dd2bea0b56de772a9fdccd96cbf517e6a0"),
                Asset(name: "vocab.json", bytes: 2776833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
             ]),
    ]
}
