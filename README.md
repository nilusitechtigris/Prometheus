<p align="center"><img src="assets/icon.png" width="128" alt="Prometheus icon"></p>

<h1 align="center">Prometheus</h1>
<p align="center"><b>The fire is yours.</b></p>

Prometheus is a native macOS app (SwiftUI, Apple Silicon) for chatting with local LLMs. It includes live observability and a curated list of verified models. Everything runs on your Mac.

## Features

- **Chat**: streaming responses, Markdown (code blocks with copy, tables, lists, math blocks), collapsible "thinking" for reasoning models, stop/regenerate, saved conversations with search.
- **Per-reply stats card** under every answer: speed · time (first token + generation, with a bar; the first-token segment keeps its health colour) · tokens (output + thinking, with a bar) · model temp (the sampling temperature used). It collapses to a small arrow, and the choice applies to every reply. Times are always shown in seconds (0.20 s).
- **Controls under the message box**: Framework · Model + quant · Context · Think · Temp
- **Model and quant selection** (⇧⌘M):
  - Always shows the quantization (Q4_K_M, Q8_0, FP16, Q4_0 QAT, MXFP4) and who made the quantized file (Ollama, Google, OpenAI, or the publisher on LM Studio and MLX).
  - Switch between quants of the same model in one click. A variant you don't have yet is downloaded first.
  - Verified models only by default. The Model Library lets you download, use and remove models with one click (Ollama), and shows a memory-fit badge for your Mac.
- **Framework selection**: Ollama (recommended), LM Studio, llama.cpp `llama-server`, and MLX LM. A green dot shows which ones are running.
- **Context window**: pick 2K–128K tokens, limited to what the model supports, with a memory estimate for each size. Older messages are trimmed automatically when they don't fit.
- **Telemetry** (rail › Telemetry, or ⌥⌘1): a panel docked at the right of the window on every page, with **Generation** and **Hardware** stacked. It's open by default and takes its width from the page beside it, so nothing covers the chat. Collapse it with the button at its top, and drag its left edge to resize it.
  - **Generation**: averages for this chat with the exact model + quant selected. A new chat, model or quant starts at zero; reopening an old chat restores its numbers. Shows first-token time (cold starts left out), tokens/sec, prompt speed and reply length, plus context-window usage.
  - **Hardware**: compact cards with each part's load next to its temperature, in data-path order: GPU, then memory (with pressure and swap), then CPU. Includes the macOS thermal state.
  - Temperatures come from the SMC. No admin rights needed.
  - Every metric uses green / yellow / red ranges
- **Tests** (rail › Tests): one page with a Model, Hardware and Harness tab, each laid out the same way: main card and four tiles, two panels, all runs, then a Details panel with tabs.
  - **Model Test** (⌥⌘3): 24 auto-graded questions on any installed model, chosen in the dashboard without changing the model you chat with. Six topics (math, reasoning, knowledge, instructions, code, long context), each with Basic, Intermediate, Advanced and Expert questions. Each level is worth double the one below it (1, 2, 4, 8 points), so most of the score sits in the expert questions, and the score is the share of the 90 points. 100 is the level of Opus 5.5 at max effort, which scored 90 of 90 in a blind run of these questions (no tools, answers unseen). Also measures tokens/sec, first-token time and prompt reading speed. The dashboard shows the score and tier, a skill map of topics by level, every question (expand one to see what it checks, what was asked, and the model's reply), a quality-vs-speed chart and a leaderboard of every model and quant you've tested.
  - **Hardware Test** (⌥⌘4, about 30 s): CPU single and multi-core, CPU and GPU memory bandwidth, GPU FP16 matrix math (Metal Performance Shaders), disk read/write with the cache bypassed, and 15 s of sustained GPU load to check for throttling. The dashboard shows temperatures and load through the run, and estimates each catalog model's generation speed on this Mac from the measured bandwidth (tokens/sec ≈ bandwidth ÷ model size), next to the speeds the model test measured.
  - **Harness Test** (⌥⌘5): the same 24 questions on the same model with the harness off and on, reusing a matching run without it if there is one, then 7 poisoned web pages both ways. Small models rarely call tools by themselves, so the harness drives each question in a loop: it works out what the task needs, makes the right tool run, gives the model the evidence, then checks the reply in code. If the reply fails, it goes round again with what it learned, up to the rounds set in Settings › Safety (3 by default, and capped at a minute a round). Check looks for replies that were cut off or left out the tool's result, answers that aren't in the sources, and broken rules such as word counts, first letters, banned letters or JSON only. Rounds can read the next page, search again, fix a program with its error message, or ask for eight options for one sentence and let code pick one that passes. It stops when a round changes nothing, and it keeps the best attempt so far. Long pages and documents are cut down to the few passages that match the question, following names and references from one note to the next, so the harness suits very small models with small context windows. It only ever sees the question, never the expected answer. The tools are web search (Wikipedia, Stack Overflow, arXiv and MDN through their official APIs), a page reader limited to 100 trusted sites, an exact calculator, and a code runner for Python and JavaScript. Code runs in a deny-by-default macOS sandbox with no internet, no other programs and no access to your files, limited to 10 seconds, 1 GB of memory and 10 MB of files. There's also basic prompt injection protection: invisible text, hidden comments, images, encoded blobs and text aimed at the assistant are removed before the model reads a page, and links to untrusted sites and known secrets are removed from its replies. The allowlist is enforced in code, and query strings and redirects off the list are refused. Tools need Ollama and a model that supports them. During a harness test, the test's fixed search terms go to those search services. The Harness tab draws these steps as a diagram.
  - Chat waits while a test runs, so the numbers stay clean. Results are saved in `tests.json` next to the conversations.
- **Harness in chat**: turn it on or off at any time with the Harness button under the message box. It's off by default, and chat stays fully local while it's off. With it on, each reply goes through the same loop as the Harness Test, and the steps and rounds show above the reply, including every search and page. Search terms then leave this Mac, going to Wikipedia, Stack Overflow, arXiv and MDN, and pages come from the trusted sites. In chat only the harness uses the tools, never the model, so a web page can't steer one with your chat in view. Needs Ollama.
- **Chats**: a column docked beside the conversation on the Chat page. Search covers titles and messages (⌘F), and right-clicking a chat renames or deletes it. The rail's Chat button or ⌥⌘2 opens and collapses the column.
- **Look and feel**:
  - The Forge layout: near-black with one accent color and Geist type, built around chat with a slim icon rail, a top bar and a status bar. The rail also opens and collapses the telemetry panel.
  - Greek line drawings, all SwiftUI shapes: a Greek key frieze under the top bar, a Doric column on the rail, a laurel wreath around the flame on the welcome screen, and α β γ on the Tests tabs
  - Seven colour themes (View › Theme, or Settings › Appearance) and a static ambient mesh background
  - Green, yellow and red always keep their health meaning, whatever the theme
  - The Prometheus brand: a blue flame with the AI spark at its heart over a Greek key, and a Prometheus theme with a background lit from below. The mark and wordmark stay the same in every theme. The icon is drawn by `scripts/make-icon.swift`.

## Run it

Requirements: an Apple Silicon Mac, macOS 14 or later, and Command Line Tools or Xcode.

```bash
make run        # builds "build/Prometheus.app" and opens it
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
assets/fonts/               Geist fonts (SIL Open Font License)
Sources/SensorsC/           C bridge: Apple SMC + HID temperature sensors
Sources/LocalAIAgent/
  App/                      App entry, settings, debug hooks
  Backends/                 Ollama + OpenAI-compatible clients (streaming)
  Services/                 Backend/chat controllers, persistence, model + hardware tests
  Services/Harness/         Trusted sites, web tools, calculator, injection guard and test
  Telemetry/                CPU/GPU/memory/thermal sampling
  Models/                   Chat types, curated catalog, health thresholds
  Views/                    Forge layout and chats, chat, telemetry widgets, test dashboards, library, settings
scripts/build-app.sh        Builds and ad-hoc signs the .app bundle
```

Conversations are stored in `~/Library/Application Support/LocalAIAgent/conversations.json`.

> **Note:** The macOS 27 SDK in Command Line Tools declares SwiftUI's `@State` as a macro whose plugin only ships with Xcode. `build-app.sh` detects this and builds against the newest installed SDK that doesn't need the macro (26.5 here).
