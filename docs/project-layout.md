# Project layout

```
assets/art/                 AI-generated pictures; originals/ holds the unedited exports
assets/fonts/               Geist and Geist Mono (SIL Open Font License)
benchmarks/heldout/         The held-out and practice questions, their licences and the rules for using them
docs/                       The longer pages the README links to, and the pictures in screenshots/
Sources/SensorsC/           C bridge: Apple SMC + HID temperature sensors
Sources/LocalAIAgent/
  App/                      App entry, settings, debug hooks
  Backends/                 Ollama + OpenAI-compatible clients (streaming)
  Services/                 Backend/chat controllers, persistence, model + hardware tests
  Services/Harness/         The harness versions, shared notes, trusted sites, web tools, calculator, injection guard and test
  Services/Dev/             Dev mode: project files, sandboxed runs, Python and JavaScript parsing, the coding agent, the web app builder and its style kit, comparisons, and the checks
  Telemetry/                CPU/GPU/memory/thermal sampling
  Models/                   Chat types, curated catalog, health thresholds
  Views/                    Forge layout and chats, chat, telemetry widgets, test dashboards, library, settings
results/                    Test results people have published, and the file format
scripts/build-app.sh        Builds and ad-hoc signs the .app bundle
scripts/dev_tasks.py        The coding tasks Dev mode's agent is measured on
scripts/heldout/sample.py   Draws the held-out and practice questions from their public sources, the same way every time
scripts/setup-mac.sh        Takes a new Mac from nothing to the running app
scripts/update-app.sh       Updates the app to the newest code; the Update button runs this too
```

Conversations are stored in `~/Library/Application Support/LocalAIAgent/conversations.json`. Copies made before a new build opens them are in `Backups` in the same folder.

---

[Back to the README](../README.md)
