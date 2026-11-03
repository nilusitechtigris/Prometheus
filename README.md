# Local AI Agent

A native macOS app (SwiftUI, Apple Silicon) for chatting with local LLMs. It includes live observability and a curated list of verified models. Everything runs on your Mac.

## Features

- **Chat**: streaming responses, Markdown (code blocks with copy, tables, lists, math blocks), collapsible "thinking" for reasoning models, stop/regenerate, saved conversations with search.
- **Model selection**: verified models only by default. The Model Library lets you download, use and remove models with one click (Ollama), and shows a memory-fit badge for your Mac.
- **Framework selection**: Ollama (recommended), LM Studio, llama.cpp `llama-server`, and MLX LM. A green dot shows which ones are running.
- **Context window**: pick 2K–128K tokens, limited to what the model supports, with a memory estimate for each size. Older messages are trimmed automatically when they don't fit.
- **Observability** (⌥⌘I):
  - Time to first token, tokens/sec (updates live while generating), prompt-processing speed, tokens in/out, model load time
  - Context-window usage
  - Loaded models, their GPU/CPU split, and a one-click Unload
  - CPU (with per-core bars), GPU, and memory (with pressure, swap, and a breakdown), each with a sparkline
  - CPU, GPU, and memory temperatures read from the SMC, plus the macOS thermal state. No admin rights needed.
  - Every metric uses green / yellow / red ranges (see "How ranges are defined" in the panel)

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
