# Local AI Agent

A native macOS app (SwiftUI, Apple Silicon) for chatting with local LLMs. It includes live observability and a curated list of verified models. Everything runs on your Mac.

## Features

- **Chat**: streaming responses, Markdown (code blocks with copy, tables, lists, math blocks), collapsible "thinking" for reasoning models, stop/regenerate, saved conversations with search.
- **Per-reply stats card** under every answer: speed · time (first token + generation, with a bar; the first-token segment keeps its health colour) · tokens (output + thinking, with a bar).
- **Controls under the message box**: Framework · Model + quant · Context · Think · Temp
- **Model and quant selection** (⇧⌘M):
  - Always shows the quantization (Q4_K_M, Q8_0, FP16, Q4_0 QAT, MXFP4) and who made the quantized file (Ollama, Google, OpenAI, or the publisher on LM Studio and MLX).
  - Switch between quants of the same model in one click. A variant you don't have yet is downloaded first.
  - Verified models only by default. The Model Library lets you download, use and remove models with one click (Ollama), and shows a memory-fit badge for your Mac.
- **Framework selection**: Ollama (recommended), LM Studio, llama.cpp `llama-server`, and MLX LM. A green dot shows which ones are running.
- **Context window**: pick 2K–128K tokens, limited to what the model supports, with a memory estimate for each size. Older messages are trimmed automatically when they don't fit.
- **Telemetry** (the Telemetry button at the top right, or ⌥⌘I). The compact vitals in the toolbar hide while the panel is open.
  - **Generation widget**: averages for this chat with the exact model + quant selected. A new chat, model or quant starts at zero; reopening an old chat restores its numbers. Shows first-token time (cold starts left out), tokens/sec, prompt speed and reply length, plus context-window usage.
  - **Hardware widget**: compact cards with each part's load next to its temperature, in data-path order: GPU, then memory (with pressure and swap), then CPU. Includes the macOS thermal state.
  - Temperatures come from the SMC. No admin rights needed.
  - Every metric uses green / yellow / red ranges
- **Look and feel**:
  - Six colour themes (View › Theme, or Settings › Appearance) and a static ambient mesh background
  - Liquid Glass for the composer and controls on macOS 26+
  - Green, yellow and red always keep their health meaning, whatever the theme

## Run it

Requirements: an Apple Silicon Mac, macOS 14 or later, and Command Line Tools or Xcode.

```bash
make run        # builds "build/Local AI Agent.app" and opens it
make install    # copies it to /Applications
```

Then start a framework. Ollama is the easiest:

```bash
brew install ollama && brew services start ollama
```

If Ollama is installed but not running, the app shows a **Start Ollama** button.

## Safety model

The catalog (`Sources/LocalAIAgent/Models/ModelCatalog.swift`) only lists official open-weight models from Meta, Google, Microsoft, Alibaba Qwen, Mistral AI, IBM, DeepSeek and OpenAI. These are widely used models, and the app verified each Ollama tag against the registry. They download as GGUF files: tensors only, no executable code, checksum-verified. Models outside the catalog are disabled unless you turn on **Settings › Safety › Allow unverified models**.

## Project layout

```
Sources/SensorsC/           C bridge: Apple SMC + HID temperature sensors
Sources/LocalAIAgent/
  App/                      App entry, settings, debug hooks
  Backends/                 Ollama + OpenAI-compatible clients (streaming)
  Services/                 Backend/chat controllers, persistence
  Telemetry/                CPU/GPU/memory/thermal sampling
  Models/                   Chat types, curated catalog, health thresholds
  Views/                    Chat, sidebar, toolbar, inspector, library, settings
scripts/build-app.sh        Builds and ad-hoc signs the .app bundle
```

Conversations are stored in `~/Library/Application Support/LocalAIAgent/conversations.json`.

> **Note:** The macOS 27 SDK in Command Line Tools declares SwiftUI's `@State` as a macro whose plugin only ships with Xcode. `build-app.sh` detects this and builds against the newest installed SDK that doesn't need the macro (26.5 here).
