import Foundation

/// One downloadable quantization of a catalog model.
struct QuantVariant: Identifiable, Hashable {
    var id: String { tag }
    /// An Ollama tag, or a Hugging Face repo for MLX LM.
    let tag: String
    /// e.g. "Q4_K_M", "Q8_0", "FP16", "Q4_0 QAT", "MXFP4", "4bit"
    let quant: String
    let bytes: Int64
    /// Who produced the quantized weights.
    var quantizedBy = "Ollama"
    /// Other Ollama tags that point at the same weights.
    var aliases: [String] = []
    var isDefault = false

    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var quality: String {
        switch quant {
        case "Q8_0", "8bit": return "Near-lossless"
        case "FP16", "BF16": return "Full precision"
        case "Q4_0 QAT": return "Quantization-aware"
        case "MXFP4": return "Native 4-bit"
        default: return "Balanced"
        }
    }

    func matches(_ tag: String) -> Bool {
        let t = tag.hasSuffix(":latest") ? String(tag.dropLast(7)) : tag
        return self.tag == t || aliases.contains(t)
    }
}

/// A hand-curated list of open-weight models from their original publishers.
/// Every entry is distributed as GGUF weights (tensors only — no executable code), has been
/// downloaded and evaluated by a very large community, and runs fully offline.
/// Tags, sizes and quantization types were verified against the Ollama registry. The MLX versions were
/// checked on Hugging Face: each repo is ungated and holds safetensors with no code files.
struct CatalogModel: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case small = "Small & Fast"
        case everyday = "Everyday Assistants"
        case reasoning = "Reasoning"
        case coding = "Coding"
        case large = "Large"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .small: return "hare.fill"
            case .everyday: return "bubble.left.and.text.bubble.right.fill"
            case .reasoning: return "brain.head.profile"
            case .coding: return "chevron.left.forwardslash.chevron.right"
            case .large: return "mountain.2.fill"
            }
        }
    }

    let displayName: String
    let publisher: String
    let license: String
    let parameters: String
    let maxContext: Int
    /// Rough fp16 KV-cache cost per token, used for memory-fit estimates.
    let kvKBPerToken: Double
    let category: Category
    let summary: String
    var thinking = false
    var featured = false
    /// Normalised substrings used to recognise this model in other frameworks (LM Studio, llama.cpp, MLX).
    let matchKeys: [String]
    /// Where to find the same weights for non-Ollama frameworks.
    var huggingFaceHint: String = ""
    let variants: [QuantVariant]
    /// The same model for MLX LM, converted by mlx-community. Empty when no version passed the check.
    var mlxVariants: [QuantVariant] = []

    func variants(for kind: BackendKind) -> [QuantVariant] { kind == .mlx ? mlxVariants : variants }

    var defaultVariant: QuantVariant { variants.first(where: \.isDefault) ?? variants[0] }
    var ollamaTag: String { defaultVariant.tag }
    var id: String { ollamaTag }
    var downloadBytes: Int64 { defaultVariant.bytes }
    var downloadSize: String { defaultVariant.size }

    func variant(forTag tag: String) -> QuantVariant? { (variants + mlxVariants).first { $0.matches(tag) } }
}

private func q(_ tag: String, _ quant: String, _ bytes: Int64, by: String = "Ollama",
               aliases: [String] = [], isDefault: Bool = false) -> QuantVariant {
    QuantVariant(tag: tag, quant: quant, bytes: bytes, quantizedBy: by, aliases: aliases, isDefault: isDefault)
}

private func m(_ repo: String, _ quant: String, _ bytes: Int64, isDefault: Bool = false) -> QuantVariant {
    QuantVariant(tag: "mlx-community/\(repo)", quant: quant, bytes: bytes, quantizedBy: "mlx-community", isDefault: isDefault)
}

enum ModelCatalog {
    static let all: [CatalogModel] = [
        // Small & fast
        .init(displayName: "Gemma 3 1B", publisher: "Google DeepMind", license: "Gemma Terms",
              parameters: "1B", maxContext: 32_768, kvKBPerToken: 26, category: .small,
              summary: "Tiny and very fast. Great for quick questions, rewriting and summaries.",
              matchKeys: ["gemma31b"], huggingFaceHint: "google/gemma-3-1b-it",
              variants: [q("gemma3:1b", "Q4_K_M", 806_067_267, aliases: ["gemma3:1b-it-q4_K_M"], isDefault: true),
                         q("gemma3:1b-it-qat", "Q4_0 QAT", 1_003_539_572, by: "Google"),
                         q("gemma3:1b-it-q8_0", "Q8_0", 1_069_315_395),
                         q("gemma3:1b-it-fp16", "FP16", 2_006_582_595)],
              mlxVariants: [m("gemma-3-1b-it-4bit", "4bit", 732_577_304, isDefault: true),
                            m("gemma-3-1b-it-8bit", "8bit", 1_383_448_829)]),
        .init(displayName: "Llama 3.2 1B", publisher: "Meta", license: "Llama 3.2 Community",
              parameters: "1.2B", maxContext: 131_072, kvKBPerToken: 32, category: .small,
              summary: "Meta's smallest assistant. Long context, light on memory and battery.",
              matchKeys: ["llama321b"], huggingFaceHint: "meta-llama/Llama-3.2-1B-Instruct",
              variants: [q("llama3.2:1b-instruct-q4_K_M", "Q4_K_M", 807_709_300),
                         q("llama3.2:1b", "Q8_0", 1_321_097_844, aliases: ["llama3.2:1b-instruct-q8_0"], isDefault: true),
                         q("llama3.2:1b-instruct-fp16", "FP16", 2_479_610_484)],
              mlxVariants: [m("Llama-3.2-1B-Instruct-4bit", "4bit", 695_283_921, isDefault: true),
                            m("Llama-3.2-1B-Instruct-8bit", "8bit", 1_313_157_436)]),
        .init(displayName: "Qwen3 1.7B", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "1.7B", maxContext: 40_960, kvKBPerToken: 112, category: .small,
              summary: "Small hybrid model that can switch thinking on for harder questions.", thinking: true,
              matchKeys: ["qwen317b"], huggingFaceHint: "Qwen/Qwen3-1.7B",
              variants: [q("qwen3:1.7b", "Q4_K_M", 1_359_292_957, aliases: ["qwen3:1.7b-q4_K_M"], isDefault: true),
                         q("qwen3:1.7b-q8_0", "Q8_0", 2_220_102_173),
                         q("qwen3:1.7b-fp16", "FP16", 4_069_691_933)],
              mlxVariants: [m("Qwen3-1.7B-4bit", "4bit", 968_080_210, isDefault: true),
                            m("Qwen3-1.7B-8bit", "8bit", 1_828_306_541),
                            m("Qwen3-1.7B-bf16", "BF16", 3_441_185_437)]),

        // Everyday
        .init(displayName: "Qwen3 4B Instruct 2507", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "4B", maxContext: 262_144, kvKBPerToken: 144, category: .everyday,
              summary: "Best quality-per-GB for a 16 GB Mac. Fast, direct answers with a huge context window.", featured: true,
              matchKeys: ["qwen34binstruct2507", "qwen34b2507instruct"], huggingFaceHint: "Qwen/Qwen3-4B-Instruct-2507",
              variants: [q("qwen3:4b-instruct-2507-q4_K_M", "Q4_K_M", 2_497_293_316, isDefault: true),
                         q("qwen3:4b-instruct-2507-q8_0", "Q8_0", 4_280_417_796),
                         q("qwen3:4b-instruct-2507-fp16", "FP16", 8_051_297_764)],
              mlxVariants: [m("Qwen3-4B-Instruct-2507-4bit", "4bit", 2_263_022_417, isDefault: true),
                            m("Qwen3-4B-Instruct-2507-8bit", "8bit", 4_274_158_989)]),
        .init(displayName: "Llama 3.2 3B", publisher: "Meta", license: "Llama 3.2 Community",
              parameters: "3.2B", maxContext: 131_072, kvKBPerToken: 112, category: .everyday,
              summary: "Reliable all-rounder for chat, summarising and instruction following.", featured: true,
              matchKeys: ["llama323b"], huggingFaceHint: "meta-llama/Llama-3.2-3B-Instruct",
              variants: [q("llama3.2:3b", "Q4_K_M", 2_019_392_628, aliases: ["llama3.2:3b-instruct-q4_K_M", "llama3.2"], isDefault: true),
                         q("llama3.2:3b-instruct-q8_0", "Q8_0", 3_421_914_228),
                         q("llama3.2:3b-instruct-fp16", "FP16", 6_433_703_028)],
              mlxVariants: [m("Llama-3.2-3B-Instruct-4bit", "4bit", 1_807_496_278, isDefault: true),
                            m("Llama-3.2-3B-Instruct-8bit", "8bit", 3_413_784_042)]),
        .init(displayName: "Phi-4 Mini", publisher: "Microsoft", license: "MIT",
              parameters: "3.8B", maxContext: 131_072, kvKBPerToken: 128, category: .everyday,
              summary: "Strong at math and logic for its size. Permissive MIT license.",
              matchKeys: ["phi4mini"], huggingFaceHint: "microsoft/Phi-4-mini-instruct",
              variants: [q("phi4-mini:3.8b", "Q4_K_M", 2_491_876_363, aliases: ["phi4-mini:3.8b-q4_K_M", "phi4-mini"], isDefault: true),
                         q("phi4-mini:3.8b-q8_0", "Q8_0", 4_084_613_131),
                         q("phi4-mini:3.8b-fp16", "FP16", 7_680_696_331)]),
        .init(displayName: "Granite 4.0 Micro", publisher: "IBM", license: "Apache 2.0",
              parameters: "3.4B", maxContext: 131_072, kvKBPerToken: 128, category: .everyday,
              summary: "Enterprise-focused, safety-tuned model with clean licensing.",
              matchKeys: ["granite4", "granite40micro"], huggingFaceHint: "ibm-granite/granite-4.0-micro",
              variants: [q("granite4:3b", "Q4_K_M", 2_099_520_968, aliases: ["granite4:micro"], isDefault: true)],
              mlxVariants: [m("granite-4.0-micro-8bit", "8bit", 3_615_813_143, isDefault: true)]),
        .init(displayName: "Gemma 3 4B", publisher: "Google DeepMind", license: "Gemma Terms",
              parameters: "4.3B", maxContext: 131_072, kvKBPerToken: 70, category: .everyday,
              summary: "Friendly, well-written answers with good multilingual support.",
              matchKeys: ["gemma34b"], huggingFaceHint: "google/gemma-3-4b-it",
              variants: [q("gemma3:4b", "Q4_K_M", 3_350_272_259, aliases: ["gemma3:4b-it-q4_K_M", "gemma3"], isDefault: true),
                         q("gemma3:4b-it-qat", "Q4_0 QAT", 4_006_302_868, by: "Google"),
                         q("gemma3:4b-it-q8_0", "Q8_0", 4_990_741_347),
                         q("gemma3:4b-it-fp16", "FP16", 8_627_991_747)],
              mlxVariants: [m("gemma-3-4b-it-4bit", "4bit", 3_400_569_562, isDefault: true),
                            m("gemma-3-4b-it-8bit", "8bit", 5_676_143_295)]),
        .init(displayName: "Llama 3.1 8B", publisher: "Meta", license: "Llama 3.1 Community",
              parameters: "8B", maxContext: 131_072, kvKBPerToken: 128, category: .everyday,
              summary: "The most widely deployed open model. Solid general knowledge and writing.",
              matchKeys: ["llama318b", "metallama318b"], huggingFaceHint: "meta-llama/Llama-3.1-8B-Instruct",
              variants: [q("llama3.1:8b", "Q4_K_M", 4_920_752_841, aliases: ["llama3.1:8b-instruct-q4_K_M", "llama3.1"], isDefault: true),
                         q("llama3.1:8b-instruct-q8_0", "Q8_0", 8_540_789_449)],
              mlxVariants: [m("Llama-3.1-8B-Instruct-4bit", "4bit", 4_517_489_037, isDefault: true)]),
        .init(displayName: "Mistral 7B", publisher: "Mistral AI", license: "Apache 2.0",
              parameters: "7.2B", maxContext: 32_768, kvKBPerToken: 128, category: .everyday,
              summary: "Battle-tested European model. Concise and efficient.",
              matchKeys: ["mistral7b"], huggingFaceHint: "mistralai/Mistral-7B-Instruct-v0.3",
              variants: [q("mistral:7b", "Q4_K_M", 4_372_823_897, aliases: ["mistral:7b-instruct-v0.3-q4_K_M", "mistral"], isDefault: true),
                         q("mistral:7b-instruct-v0.3-q8_0", "Q8_0", 7_702_576_985)],
              mlxVariants: [m("Mistral-7B-Instruct-v0.3-4bit", "4bit", 4_077_480_215, isDefault: true),
                            m("Mistral-7B-Instruct-v0.3-8bit", "8bit", 7_701_359_025)]),

        // Reasoning
        .init(displayName: "Qwen3 4B Thinking 2507", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "4B", maxContext: 262_144, kvKBPerToken: 144, category: .reasoning,
              summary: "Thinks step by step before answering. Excellent at math and puzzles for its size.", thinking: true,
              matchKeys: ["qwen34bthinking2507", "qwen34b2507thinking"], huggingFaceHint: "Qwen/Qwen3-4B-Thinking-2507",
              variants: [q("qwen3:4b-thinking-2507-q4_K_M", "Q4_K_M", 2_497_293_444, aliases: ["qwen3:4b"], isDefault: true),
                         q("qwen3:4b-thinking-2507-q8_0", "Q8_0", 4_280_417_924)],
              mlxVariants: [m("Qwen3-4B-Thinking-2507-4bit", "4bit", 2_263_022_417, isDefault: true),
                            m("Qwen3-4B-Thinking-2507-8bit", "8bit", 4_274_158_989)]),
        .init(displayName: "Qwen3 8B", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "8.2B", maxContext: 40_960, kvKBPerToken: 144, category: .reasoning,
              summary: "Hybrid thinking model — toggle reasoning on or off per message.", thinking: true, featured: true,
              matchKeys: ["qwen38b"], huggingFaceHint: "Qwen/Qwen3-8B",
              variants: [q("qwen3:8b", "Q4_K_M", 5_225_387_677, aliases: ["qwen3:8b-q4_K_M", "qwen3"], isDefault: true),
                         q("qwen3:8b-q8_0", "Q8_0", 8_851_089_053)],
              mlxVariants: [m("Qwen3-8B-4bit", "4bit", 4_607_835_174, isDefault: true),
                            m("Qwen3-8B-8bit", "8bit", 8_703_048_996)]),
        .init(displayName: "DeepSeek-R1 8B", publisher: "DeepSeek", license: "MIT",
              parameters: "8B", maxContext: 131_072, kvKBPerToken: 144, category: .reasoning,
              summary: "R1-0528 reasoning distilled into Qwen3 8B. Shows its full chain of thought.", thinking: true,
              matchKeys: ["deepseekr1", "r10528qwen38b"], huggingFaceHint: "deepseek-ai/DeepSeek-R1-0528-Qwen3-8B",
              variants: [q("deepseek-r1:8b", "Q4_K_M", 5_225_375_560, aliases: ["deepseek-r1:8b-0528-qwen3-q4_K_M", "deepseek-r1"], isDefault: true),
                         q("deepseek-r1:8b-0528-qwen3-q8_0", "Q8_0", 8_851_076_936)],
              mlxVariants: [m("DeepSeek-R1-0528-Qwen3-8B-4bit", "4bit", 4_607_835_164, isDefault: true),
                            m("DeepSeek-R1-0528-Qwen3-8B-8bit", "8bit", 8_703_048_996)]),
        .init(displayName: "Phi-4 14B", publisher: "Microsoft", license: "MIT",
              parameters: "14.7B", maxContext: 16_384, kvKBPerToken: 200, category: .reasoning,
              summary: "Excellent reasoning and STEM answers. Needs most of a 16 GB Mac.",
              matchKeys: ["phi414b", "phi4q", "phi4gguf"], huggingFaceHint: "microsoft/phi-4",
              variants: [q("phi4:14b", "Q4_K_M", 9_053_115_905, aliases: ["phi4:14b-q4_K_M", "phi4"], isDefault: true),
                         q("phi4:14b-q8_0", "Q8_0", 15_580_501_505)],
              mlxVariants: [m("phi-4-4bit", "4bit", 8_246_633_911, isDefault: true),
                            m("phi-4-8bit", "8bit", 15_576_180_399)]),

        // Coding
        .init(displayName: "Qwen2.5 Coder 3B", publisher: "Alibaba Qwen", license: "Qwen Research",
              parameters: "3.1B", maxContext: 32_768, kvKBPerToken: 36, category: .coding,
              summary: "Small, quick coding helper for snippets and explanations.",
              matchKeys: ["qwen25coder3b"], huggingFaceHint: "Qwen/Qwen2.5-Coder-3B-Instruct",
              variants: [q("qwen2.5-coder:3b", "Q4_K_M", 1_929_912_139, aliases: ["qwen2.5-coder:3b-instruct-q4_K_M"], isDefault: true),
                         q("qwen2.5-coder:3b-instruct-q8_0", "Q8_0", 3_285_485_387)],
              mlxVariants: [m("Qwen2.5-Coder-3B-Instruct-4bit", "4bit", 1_736_293_090, isDefault: true),
                            m("Qwen2.5-Coder-3B-Instruct-8bit", "8bit", 3_279_142_142)]),
        .init(displayName: "Qwen2.5 Coder 7B", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "7.6B", maxContext: 32_768, kvKBPerToken: 56, category: .coding,
              summary: "One of the most popular local coding models. Writes, explains and fixes code.", featured: true,
              matchKeys: ["qwen25coder7b"], huggingFaceHint: "Qwen/Qwen2.5-Coder-7B-Instruct",
              variants: [q("qwen2.5-coder:7b", "Q4_K_M", 4_683_087_074, aliases: ["qwen2.5-coder:7b-instruct-q4_K_M", "qwen2.5-coder"], isDefault: true),
                         q("qwen2.5-coder:7b-instruct-q8_0", "Q8_0", 8_098_538_722)],
              mlxVariants: [m("Qwen2.5-Coder-7B-Instruct-4bit", "4bit", 4_284_346_255, isDefault: true),
                            m("Qwen2.5-Coder-7B-Instruct-8bit", "8bit", 8_091_987_725)]),

        // Large
        .init(displayName: "Gemma 3 12B", publisher: "Google DeepMind", license: "Gemma Terms",
              parameters: "12B", maxContext: 131_072, kvKBPerToken: 120, category: .large,
              summary: "Higher quality writing and knowledge. Best on 24 GB+ Macs.",
              matchKeys: ["gemma312b"], huggingFaceHint: "google/gemma-3-12b-it",
              variants: [q("gemma3:12b", "Q4_K_M", 8_164_039_587, aliases: ["gemma3:12b-it-q4_K_M"], isDefault: true),
                         q("gemma3:12b-it-qat", "Q4_0 QAT", 8_928_674_580, by: "Google"),
                         q("gemma3:12b-it-q8_0", "Q8_0", 13_373_415_235)],
              mlxVariants: [m("gemma-3-12b-it-4bit", "4bit", 8_028_675_248, isDefault: true),
                            m("gemma-3-12b-it-8bit", "8bit", 14_414_748_818)]),
        .init(displayName: "Qwen3 14B", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "14.8B", maxContext: 40_960, kvKBPerToken: 160, category: .large,
              summary: "Big step up in quality with optional thinking. Best on 24 GB+ Macs.", thinking: true,
              matchKeys: ["qwen314b"], huggingFaceHint: "Qwen/Qwen3-14B",
              variants: [q("qwen3:14b", "Q4_K_M", 9_276_198_077, aliases: ["qwen3:14b-q4_K_M"], isDefault: true),
                         q("qwen3:14b-q8_0", "Q8_0", 15_895_154_877)],
              mlxVariants: [m("Qwen3-14B-4bit", "4bit", 8_307_898_514, isDefault: true),
                            m("Qwen3-14B-8bit", "8bit", 15_691_839_954)]),
        .init(displayName: "gpt-oss 20B", publisher: "OpenAI", license: "Apache 2.0",
              parameters: "21B (MoE)", maxContext: 131_072, kvKBPerToken: 48, category: .large,
              summary: "OpenAI's open-weight reasoning model. Needs a 24 GB+ Mac.", thinking: true,
              matchKeys: ["gptoss20b"], huggingFaceHint: "openai/gpt-oss-20b",
              variants: [q("gpt-oss:20b", "MXFP4", 13_793_441_427, by: "OpenAI", aliases: ["gpt-oss"], isDefault: true)],
              mlxVariants: [m("gpt-oss-20b-MXFP4-Q4", "MXFP4", 11_178_569_159, isDefault: true)]),
    ]

    static func entry(forOllamaTag tag: String) -> CatalogModel? {
        all.first { $0.variant(forTag: tag) != nil }
    }

    static func variant(forTag tag: String) -> QuantVariant? {
        entry(forOllamaTag: tag)?.variant(forTag: tag)
    }

    /// Fuzzy match used for frameworks that expose free-form model IDs.
    static func entry(matchingID id: String) -> CatalogModel? {
        if let exact = entry(forOllamaTag: id) { return exact }
        let n = normalise(id)
        // Prefer the most specific (longest) key that matches.
        var best: (CatalogModel, Int)?
        for model in all {
            for key in model.matchKeys {
                let k = normalise(key)
                if n.contains(k), k.count > (best?.1 ?? 0) { best = (model, k.count) }
            }
        }
        return best?.0
    }

    static func normalise(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Pulls a quantization label and the quantizer's name out of free-form model IDs
/// such as `lmstudio-community/Qwen3-8B-GGUF/Qwen3-8B-Q4_K_M.gguf` or `mlx-community/Qwen3-4B-4bit`.
enum QuantParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![a-z0-9])(iq\d_[a-z]+|q\d_k_[sml]|q\d_k|q\d_\d|mxfp4|bf16|fp16|f16|f32|\d{1,2}-?bit|qat)(?![a-z0-9])"#)

    static func quant(in id: String) -> String? {
        let range = NSRange(id.startIndex..., in: id)
        guard let match = pattern.matches(in: id, range: range).last,
              let r = Range(match.range(at: 1), in: id) else { return nil }
        return normalise(String(id[r]))
    }

    static func normalise(_ q: String) -> String {
        let upper = q.uppercased()
        if upper == "F16" { return "FP16" }
        if upper.hasSuffix("BIT") { return upper.replacingOccurrences(of: "-", with: "").lowercased() }
        return upper
    }

    /// For `owner/repo…` style IDs the owner is who published the quantized weights.
    static func provider(in id: String) -> String? {
        var path = id
        if path.hasPrefix("hf.co/") { path.removeFirst(6) }
        if path.hasPrefix("huggingface.co/") { path.removeFirst(15) }
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return String(parts[0])
    }
}

/// Estimates whether a model + context window fits in the GPU working set of this Mac.
enum MemoryFit {
    enum Verdict {
        case great, tight, tooLarge
        var level: HealthLevel {
            switch self {
            case .great: return .good
            case .tight: return .warning
            case .tooLarge: return .critical
            }
        }
        var label: String {
            switch self {
            case .great: return "Runs great"
            case .tight: return "Tight fit"
            case .tooLarge: return "Too large"
            }
        }
    }

    static func estimateBytes(weights: Int64, kvKBPerToken: Double, context: Int) -> Int64 {
        let kv = kvKBPerToken * 1024 * Double(context)
        return Int64(Double(weights) * 1.05 + kv + 400 * 1_048_576)
    }

    static func verdict(requiredBytes: Int64, budget: Int64) -> Verdict {
        let r = Double(requiredBytes), b = Double(budget)
        if r <= b * 0.70 { return .great }
        if r <= b { return .tight }
        return .tooLarge
    }
}
