<p align="center"><img src="assets/icon.png" width="128" alt="Prometheus icon"></p>

<h1 align="center">Prometheus</h1>
<p align="center"><b>Bring the fire home.</b></p>
<p align="center">A native Mac app for running open AI models on your own machine, with a harness that helps small models do more.</p>

![The Prometheus home page](docs/screenshots/home.png)

## What it is

Prometheus runs open models such as Qwen, Llama and Gemma on your Mac, through Ollama, LM Studio, llama.cpp or MLX LM. There's no account and no cloud service, and your chats stay on your Mac.

Small models are fast and private, but they get arithmetic wrong, misremember facts and break rules like "exactly three words". The **harness** is an optional layer that helps with this. It can run code in a sandbox, search trusted sites, and check replies in code before you see them. It's off by default, because its searches leave your Mac.

The app also measures all of this for you: how capable a model is, how fast your Mac is, and how much each version of the harness really helps.

## Start it

You'll need an Apple Silicon Mac with macOS 14 or later, plus Xcode or the Command Line Tools (`xcode-select --install`). There's no prebuilt download yet, so you build it yourself.

**1. Build and open the app**

```bash
git clone https://github.com/nilusitechtigris/Prometheus.git
```

```bash
cd Prometheus && make run
```

To keep a copy in your Applications folder, run this as well:

```bash
make install
```

**2. Start a framework.** Ollama is the easiest:

```bash
brew install ollama && brew services start ollama
```

If Ollama is installed but not running, the app shows a **Start Ollama** button.

**3. Download a model.** Open **Models** in the sidebar and pick one. It shows which models fit your Mac. Qwen3 4B Instruct 2507 is a good first choice on 16 GB.

**4. Chat.** Open **Chat** and send a message. To try the harness, click the **Harness** button under the message box and pick a version.

## What's inside

### Chat

![A chat with the harness on and hardware telemetry below it](docs/screenshots/chat.png)

- Streaming replies with Markdown, code blocks, tables and collapsible thinking
- Stop, regenerate, and saved chats with search (⌘F). Select several chats to delete them together
- Speed, time and token numbers under every reply
- Framework, model and quantization, context window, Think, Harness and temperature under the message box
- Live hardware telemetry along the bottom (⌥⌘1): GPU, memory and CPU load and temperatures, with no admin rights needed

### Models

![The Model Library](docs/screenshots/models.png)

Verified open models from Meta, Google, Microsoft, Alibaba Qwen, Mistral AI, IBM, DeepSeek and OpenAI, with each one's license and a memory estimate for your Mac. With Ollama, you can download, use and remove them in one click, and switch between quantizations of a model. See who made the quantized file (⇧⌘M).

### Tests

One page with three tabs, all laid out the same way:

- **Model Test** (⌥⌘3): 24 auto-graded questions across math, reasoning, knowledge, instructions, code and long context. Each topic has four levels worth 1, 2, 4 and 8 points. A score of 100 is the level of Claude Opus 5.5 at max effort, from a blind run of the same questions.
- **Hardware Test** (⌥⌘4, about 30 seconds): CPU, GPU, memory bandwidth and disk speed, plus 15 seconds of sustained GPU load to check for throttling.
- **Harness Test** (⌥⌘5): the same 24 questions with the harness off and on, then 7 poisoned web pages both ways.

## The harness

Every version stays available, in chat and in the Harness Test, so you can compare them on your own models.

| Version | What it does |
| --- | --- |
| **v1 Model tools** | The model gets the tools and decides when to call them. |
| **v2 Pipeline** | The harness works out what the task needs and runs one tool, then the model answers from what it found. Kept exactly as it was. |
| **v3 Loop** | The pipeline, plus code that checks each reply and goes round again until it passes. |
| **v4 Thinking loop** | The newest. The loop, with the model thinking through every step it takes part in. Needs Think on: with it off, it works like v3. |

![The Harness Test results](docs/screenshots/harness.png)

The Versions tab puts them side by side, question by question, for runs on the same model and setup:

![Each harness version compared, question by question](docs/screenshots/harness-versions.png)

### Results so far

Scores out of 100, with thinking on:

| Model | Context | Off | v1 | v2 | v3 |
| --- | --- | --- | --- | --- | --- |
| Qwen3 1.7B Q4_K_M | 4K | 24 | 25 | 42 | not run |
| Qwen3 1.7B FP16 | 8K | 28 | not run | not run | 48 |

These are single runs, so don't read much into small differences, and the two rows use different setups. The v3 run came before a calculator fix that affected one 4-point question, and v4 hasn't been scored yet. Injection protection stopped 7 of 7 poisoned pages in these runs, against 0 of 7 without it.

### How v3 works

1. **Understand**: works out what kind of task this is.
2. **Act**: runs the right tool. A math or code task runs in the sandbox, a fact is looked up, and a long text is cut down to the passages that matter.
3. **Answer**: the model replies with that evidence in front of it.
4. **Check**: code tests the reply. Was it cut off? Does it state the tool's result? Is the answer in the sources? Does it break a rule such as a word count? If it fails, it goes back to Act with what it learned.

It stops when a reply passes, when a round changes nothing, or at the rounds set in Settings › Safety, and it keeps the best attempt so far. It only ever sees the question, never the expected answer.

### What v4 adds

v3 turns thinking off at almost every step, to save tokens. v4 leaves it on. With Think on, the model reasons before it classifies a task, picks a search, writes a program, answers or rewrites a sentence, and it sees what Check found wrong when it goes round again.

Each step gets extra tokens for this, a quarter of the context up to 2,048. If thinking uses them all, that step goes again without thinking, so a step can't end up with less than it would have had in v3. Check stays code, and anything plain code can settle, such as a simple sum, doesn't call the model at all. It takes longer than v3, and with Think off the two work the same.

### Can the models call tools themselves?

Yes. All six Qwen3 models tried so far (1.7B, 4B and 8B, in several quantizations) produce real tool calls, in 34 of 44 prompts in a short check, and all of them used a calculator result correctly. All 10 misses had thinking on and ran out of tokens before making a call, so try v1 with Think off. Being able to call a tool doesn't make the reply right, though: the 1.7B models sometimes search the web for arithmetic, or search for a fact and still get it wrong. That's why v2 onwards don't leave it to the model.

## Privacy and safety

- **Harness off:** the only internet access is downloading models you choose, through your framework.
- **Harness on:** search terms go to Wikipedia, Stack Overflow, arXiv and MDN, and pages come only from a list of 100 trusted sites. Every search and page is listed above the reply.
- **Code** runs in a deny-by-default macOS sandbox with no internet, no other programs and no access to your files, limited to 10 seconds, 1 GB of memory and 10 MB of files.
- **Prompt injection:** hidden text and text aimed at the assistant are removed before the model reads a page, and links to untrusted sites are removed from its replies. This is basic protection: it blocks common attacks, not every possible one.
- **Tools in chat:** in v2, v3 and v4 only the harness uses them, so a web page can't steer one. In v1 the model holds them, so once it has read the web it can't search again and can only open links it was given.
- **Models:** The catalog (`Sources/LocalAIAgent/Models/ModelCatalog.swift`) only lists official open-weight models from Meta, Google, Microsoft, Alibaba Qwen, Mistral AI, IBM, DeepSeek and OpenAI. These are widely used models, and the app verified each Ollama tag against the registry. They download as GGUF files: tensors only, no executable code, checksum-verified. Models outside the catalog are disabled unless you turn on **Settings › Safety › Allow unverified models**.

The harness needs Ollama, and a model that supports tools for v1.

## Project layout

```
assets/art/                 AI-generated pictures; originals/ holds the unedited exports
assets/fonts/               Geist and Geist Mono (SIL Open Font License)
docs/screenshots/           The pictures in this file
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

## License

The code is licensed under the [Apache License 2.0](LICENSE). A few things in this repository have their own terms, listed in [NOTICE](NOTICE):

- **Fonts:** Geist and Geist Mono are under the [SIL Open Font License](assets/fonts/OFL.txt).
- **Pictures:** the backgrounds and the icon were made with Canva's AI tools. They aren't under the Apache License, and Canva's [AI Product Terms](https://www.canva.com/policies/ai-product-terms/) apply to them.
- **Models:** none are included. You download them yourself, and each has its own license, shown in the Model Library.

Prometheus isn't related to the Prometheus monitoring system.
