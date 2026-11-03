import Foundation

/// A hand-curated list of open-weight models from their original publishers.
/// Every entry is distributed as GGUF weights (tensors only — no executable code), has been
/// downloaded and evaluated by a very large community, and runs fully offline.
struct CatalogModel: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case recommended = "Recommended"
        case small = "Small & Fast"
        case everyday = "Everyday Assistants"
        case reasoning = "Reasoning"
        case coding = "Coding"
        case large = "Large"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .recommended: return "star.fill"
            case .small: return "hare.fill"
            case .everyday: return "bubble.left.and.text.bubble.right.fill"
            case .reasoning: return "brain.head.profile"
            case .coding: return "chevron.left.forwardslash.chevron.right"
            case .large: return "mountain.2.fill"
            }
        }
    }

    var id: String { ollamaTag }
    let ollamaTag: String
    let displayName: String
    let publisher: String
    let license: String
    let parameters: String
    let downloadBytes: Int64
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

    var downloadSize: String { ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file) }
}

enum ModelCatalog {
    static let all: [CatalogModel] = [
        // Small & fast
        .init(ollamaTag: "gemma3:1b", displayName: "Gemma 3 1B", publisher: "Google DeepMind", license: "Gemma Terms",
              parameters: "1B", downloadBytes: 806_067_267, maxContext: 32_768, kvKBPerToken: 26, category: .small,
              summary: "Tiny and very fast. Great for quick questions, rewriting and summaries.",
              matchKeys: ["gemma31b", "gemma3:1b"], huggingFaceHint: "google/gemma-3-1b-it"),
        .init(ollamaTag: "llama3.2:1b", displayName: "Llama 3.2 1B", publisher: "Meta", license: "Llama 3.2 Community",
              parameters: "1.2B", downloadBytes: 1_321_097_844, maxContext: 131_072, kvKBPerToken: 32, category: .small,
              summary: "Meta's smallest assistant. Long context, light on memory and battery.",
              matchKeys: ["llama321b"], huggingFaceHint: "meta-llama/Llama-3.2-1B-Instruct"),
        .init(ollamaTag: "qwen3:1.7b", displayName: "Qwen3 1.7B", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "1.7B", downloadBytes: 1_359_292_957, maxContext: 40_960, kvKBPerToken: 112, category: .small,
              summary: "Small hybrid model that can switch thinking on for harder questions.", thinking: true,
              matchKeys: ["qwen317b"], huggingFaceHint: "Qwen/Qwen3-1.7B"),

        // Everyday
        .init(ollamaTag: "qwen3:4b-instruct-2507-q4_K_M", displayName: "Qwen3 4B Instruct 2507", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "4B", downloadBytes: 2_497_293_316, maxContext: 262_144, kvKBPerToken: 144, category: .everyday,
              summary: "Best quality-per-GB for a 16 GB Mac. Fast, direct answers with a huge context window.", featured: true,
              matchKeys: ["qwen34binstruct2507", "qwen34b2507instruct"], huggingFaceHint: "Qwen/Qwen3-4B-Instruct-2507"),
        .init(ollamaTag: "llama3.2:3b", displayName: "Llama 3.2 3B", publisher: "Meta", license: "Llama 3.2 Community",
              parameters: "3.2B", downloadBytes: 2_019_392_628, maxContext: 131_072, kvKBPerToken: 112, category: .everyday,
              summary: "Reliable all-rounder for chat, summarising and instruction following.", featured: true,
              matchKeys: ["llama323b"], huggingFaceHint: "meta-llama/Llama-3.2-3B-Instruct"),
        .init(ollamaTag: "phi4-mini:3.8b", displayName: "Phi-4 Mini", publisher: "Microsoft", license: "MIT",
              parameters: "3.8B", downloadBytes: 2_491_876_363, maxContext: 131_072, kvKBPerToken: 128, category: .everyday,
              summary: "Strong at math and logic for its size. Permissive MIT license.",
              matchKeys: ["phi4mini"], huggingFaceHint: "microsoft/Phi-4-mini-instruct"),
        .init(ollamaTag: "granite4:3b", displayName: "Granite 4.0 Micro", publisher: "IBM", license: "Apache 2.0",
              parameters: "3B", downloadBytes: 2_099_520_968, maxContext: 131_072, kvKBPerToken: 128, category: .everyday,
              summary: "Enterprise-focused, safety-tuned model with clean licensing.",
              matchKeys: ["granite4", "granite40micro"], huggingFaceHint: "ibm-granite/granite-4.0-micro"),
        .init(ollamaTag: "gemma3:4b", displayName: "Gemma 3 4B", publisher: "Google DeepMind", license: "Gemma Terms",
              parameters: "4.3B", downloadBytes: 3_350_272_259, maxContext: 131_072, kvKBPerToken: 70, category: .everyday,
              summary: "Friendly, well-written answers with good multilingual support.",
              matchKeys: ["gemma34b"], huggingFaceHint: "google/gemma-3-4b-it"),
        .init(ollamaTag: "llama3.1:8b", displayName: "Llama 3.1 8B", publisher: "Meta", license: "Llama 3.1 Community",
              parameters: "8B", downloadBytes: 4_920_752_841, maxContext: 131_072, kvKBPerToken: 128, category: .everyday,
              summary: "The most widely deployed open model. Solid general knowledge and writing.",
              matchKeys: ["llama318b", "metallama318b"], huggingFaceHint: "meta-llama/Llama-3.1-8B-Instruct"),
        .init(ollamaTag: "mistral:7b", displayName: "Mistral 7B", publisher: "Mistral AI", license: "Apache 2.0",
              parameters: "7.2B", downloadBytes: 4_372_823_897, maxContext: 32_768, kvKBPerToken: 128, category: .everyday,
              summary: "Battle-tested European model. Concise and efficient.",
              matchKeys: ["mistral7b"], huggingFaceHint: "mistralai/Mistral-7B-Instruct-v0.3"),

        // Reasoning
        .init(ollamaTag: "qwen3:4b-thinking-2507-q4_K_M", displayName: "Qwen3 4B Thinking 2507", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "4B", downloadBytes: 2_497_293_444, maxContext: 262_144, kvKBPerToken: 144, category: .reasoning,
              summary: "Thinks step by step before answering. Excellent at math and puzzles for its size.", thinking: true,
              matchKeys: ["qwen34bthinking2507", "qwen34b2507thinking"], huggingFaceHint: "Qwen/Qwen3-4B-Thinking-2507"),
        .init(ollamaTag: "qwen3:8b", displayName: "Qwen3 8B", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "8.2B", downloadBytes: 5_225_387_677, maxContext: 40_960, kvKBPerToken: 144, category: .reasoning,
              summary: "Hybrid thinking model — toggle reasoning on or off per message.", thinking: true, featured: true,
              matchKeys: ["qwen38b"], huggingFaceHint: "Qwen/Qwen3-8B"),
        .init(ollamaTag: "deepseek-r1:8b", displayName: "DeepSeek-R1 8B", publisher: "DeepSeek", license: "MIT",
              parameters: "8B", downloadBytes: 5_225_375_560, maxContext: 131_072, kvKBPerToken: 144, category: .reasoning,
              summary: "R1-0528 reasoning distilled into Qwen3 8B. Shows its full chain of thought.", thinking: true,
              matchKeys: ["deepseekr1", "r10528qwen38b"], huggingFaceHint: "deepseek-ai/DeepSeek-R1-0528-Qwen3-8B"),
        .init(ollamaTag: "phi4:14b", displayName: "Phi-4 14B", publisher: "Microsoft", license: "MIT",
              parameters: "14.7B", downloadBytes: 9_053_115_905, maxContext: 16_384, kvKBPerToken: 200, category: .reasoning,
              summary: "Excellent reasoning and STEM answers. Needs most of a 16 GB Mac.",
              matchKeys: ["phi414b", "phi4q", "phi4gguf"], huggingFaceHint: "microsoft/phi-4"),

        // Coding
        .init(ollamaTag: "qwen2.5-coder:3b", displayName: "Qwen2.5 Coder 3B", publisher: "Alibaba Qwen", license: "Qwen Research",
              parameters: "3.1B", downloadBytes: 1_929_912_139, maxContext: 32_768, kvKBPerToken: 36, category: .coding,
              summary: "Small, quick coding helper for snippets and explanations.",
              matchKeys: ["qwen25coder3b"], huggingFaceHint: "Qwen/Qwen2.5-Coder-3B-Instruct"),
        .init(ollamaTag: "qwen2.5-coder:7b", displayName: "Qwen2.5 Coder 7B", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "7.6B", downloadBytes: 4_683_087_074, maxContext: 32_768, kvKBPerToken: 56, category: .coding,
              summary: "One of the most popular local coding models. Writes, explains and fixes code.", featured: true,
              matchKeys: ["qwen25coder7b"], huggingFaceHint: "Qwen/Qwen2.5-Coder-7B-Instruct"),

        // Large
        .init(ollamaTag: "gemma3:12b", displayName: "Gemma 3 12B", publisher: "Google DeepMind", license: "Gemma Terms",
              parameters: "12B", downloadBytes: 8_164_039_587, maxContext: 131_072, kvKBPerToken: 120, category: .large,
              summary: "Higher quality writing and knowledge. Best on 24 GB+ Macs.",
              matchKeys: ["gemma312b"], huggingFaceHint: "google/gemma-3-12b-it"),
        .init(ollamaTag: "qwen3:14b", displayName: "Qwen3 14B", publisher: "Alibaba Qwen", license: "Apache 2.0",
              parameters: "14.8B", downloadBytes: 9_276_198_077, maxContext: 40_960, kvKBPerToken: 160, category: .large,
              summary: "Big step up in quality with optional thinking. Best on 24 GB+ Macs.", thinking: true,
              matchKeys: ["qwen314b"], huggingFaceHint: "Qwen/Qwen3-14B"),
        .init(ollamaTag: "gpt-oss:20b", displayName: "gpt-oss 20B", publisher: "OpenAI", license: "Apache 2.0",
              parameters: "21B (MoE)", downloadBytes: 13_793_441_427, maxContext: 131_072, kvKBPerToken: 48, category: .large,
              summary: "OpenAI's open-weight reasoning model. Needs a 24 GB+ Mac.", thinking: true,
              matchKeys: ["gptoss20b"], huggingFaceHint: "openai/gpt-oss-20b"),
    ]

    static func entry(forOllamaTag tag: String) -> CatalogModel? {
        let t = tag.hasSuffix(":latest") ? String(tag.dropLast(7)) : tag
        return all.first { $0.ollamaTag == t }
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
