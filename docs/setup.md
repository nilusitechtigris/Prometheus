# Install and update

You'll need an Apple Silicon Mac with macOS 14 or later. There's no prebuilt download yet, so you build it yourself.

## On a new Mac

Paste this into Terminal. It works on a Mac with nothing installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/nilusitechtigris/Prometheus/main/scripts/setup-mac.sh)"
```

It asks for your password once, then installs whatever's missing: the Command Line Tools, Homebrew, Ollama and Node. It puts the code in `~/Prometheus`, builds the app into your Applications folder, downloads a first model that fits your Mac and opens the app.

It's safe to run again, because it skips what's already done. To see what it would do first, or to change the folder or skip the model, add `-- --dry-run` or `-- --help` to the end of the command. To install MLX LM as well, add `-- --mlx`.

## By hand

You'll need Xcode or the Command Line Tools (`xcode-select --install`).

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

**2. Get a framework.** Ollama is the easiest, and the app walks you through it. If Ollama isn't on your Mac, the chat page has a **Get Ollama** button. It opens Ollama's own download page, and the app carries on by itself once Ollama is running. If Ollama is installed but not running, there's a **Start Ollama** button.

To do it in Terminal instead:

```bash
brew install ollama && brew services start ollama
```

To run MLX models as well, install MLX LM, then pick it in **Settings › Frameworks**. The app starts and stops it for you:

```bash
brew install mlx-lm
```

The harness runs JavaScript with Node, so install that too if you'll use it:

```bash
brew install node
```

**3. Download a model.** With no model yet, the chat page offers a starter picked for your Mac's memory, with one button. On 16 GB that's Qwen3 4B Instruct 2507. **Models** in the dock at the foot of the window has the rest, and shows which ones fit your Mac.

**4. Chat.** Open **Chat** and send a message, or press **See the harness at work** for the three-question demo. The **Harness** button under the message box turns the harness off and on.

## Updating

Open **Settings › Updates** and press **Update**. The app downloads the newest code from GitHub, builds it and restarts itself. You can keep using it during the build, and it waits for a running test, reply or download before it restarts. If anything goes wrong, your copy keeps working.

Before a new build first opens your saved data, it copies your chats, test history, Dev mode's chats and comparisons, and shared notes into a `Backups` folder beside them, and keeps the newest five copies.

It keeps the code in `~/Prometheus`, the same place the new Mac command uses, and it needs the Command Line Tools. It only ever moves forward, because an older build can erase saved chats it can't read. So it won't touch a copy built from code that isn't on `main`, or a `~/Prometheus` folder with changes of its own.

If your copy doesn't have the Updates tab yet, quit the app and paste this into Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/nilusitechtigris/Prometheus/main/scripts/update-app.sh)"
```

## Building with the Command Line Tools only

The macOS 27 SDK in Command Line Tools declares SwiftUI's `@State` as a macro whose plugin only ships with Xcode. `build-app.sh` detects this and builds against the newest installed SDK that doesn't need the macro (26.5 here).

---

[Back to the README](../README.md)
