# Changelog

## 2.0.0 beta

On `main` since 10 November 2026. Not tagged as a release yet.

Every number this project quotes comes from a run someone made in the app. Where there is one run, it says one run. No held-out results exist yet.

### New

- **Side by side.** Ask once and see the plain model and the harness answer the same question next to each other, with a line from code about what it could check. One click saves a picture of it to share.
- **A three-question demo** on the empty chat page: two sums and a small program, the kind of thing small models get wrong and the harness can check.
- **Setup without Terminal.** With nothing installed, the chat page has a Get Ollama button and then one button for a starter model picked for the Mac's memory. A failed download says what to do about it.
- **Held-out test.** 120 public questions (GSM8K, GSM-Plus, IFEval, MBPP) that the harness is never tuned on, graded by code. The app shows totals and keeps the questions and replies closed. A separate 60-question practice set is where failures get studied.
- **Repeat runs.** Run a Harness Test three times and see every round's score, the mean and the spread. For any two runs on the same questions, the app says how often chance alone would flip that many answers that unevenly.
- **Harness v6, the evidence loop.** It answers from memory first, looks things up only where that helps, reads a page as a few quoted sentences, and settles letter counts, word counts, weekdays and day spans with plain code. Not the default and not scored yet, so it shows in the lab edition only.
- **Dev harness v2, the checked build.** After an app works it runs extra checks, tries one fix for each thing it finds, and keeps the fix only if it holds. It reports what it could not fix. Not the default and not scored yet, so it shows in the lab edition only.
- **A copy of your data before every new build touches it.** Chats, test history, Dev mode's chats and comparisons, and shared notes are copied once per build into `Backups`, and the newest five copies are kept.

### Changed

- **Harness on now means one thing:** v3, the loop, and the app offers no other. The earlier and newer versions stay in the code so results can be repeated. One Terminal line turns a copy into the lab edition, which shows them: see "The harness" in the README.
- **New installs start with the harness on.** Existing installs keep their setting.
- **Web lookups ask first.** Before the harness searches or opens a page it shows what it will send and where. "Always" and "Never" are in Settings › Harness.
- **Tests has a Lab switch.** With it off, Tests shows the Hardware Test. With it on, the Model and Harness tests and Publish are there too.
- The Harness Test says before it starts that its knowledge tasks use the web.
- Every custom button lights up under the pointer, dims while pressed and greys out when it can't be used.
- Heat is shown in plain words ("Heat: normal", "hottest 43°C"), and meters use a plain mark.
- Home and the sidebar say what is missing (Ollama not installed, not running, no model yet) and lead to the next step.
- With the harness on, the default prompt no longer tells the model it has no tools. A prompt you wrote is left alone.
- The version shows in Settings › Updates beside the commit.

### Fixed

- In the smallest window, the Harness Test page grew wider than the window and the model pill under the message box was squeezed out of shape.
- A model download that failed in the model picker stayed on its progress ring.
- A model that couldn't be removed failed without a word.
- A chat whose last reply failed was marked Completed on Home.
- Sizes mixed "2,5 GB" and "16.0 GB" on Macs set to a region that writes decimals with a comma.
- Dev chat files and saved comparisons that can't be read are set aside, not replaced.
- `archive.org` is no longer a trusted site, because it can serve any site's pages.

### Notes for people updating

- Saved chats and test history are read as before. Runs made with this version carry new fields that older builds ignore.
- Update only moves forward. If you go back to an older build by hand, the copy in `Backups` is there.

## 1.0.0

The first release: chat with Ollama, LM Studio, llama.cpp and MLX LM, the harness, Dev mode with Preview and Compare, the Model, Hardware and Harness tests, and Publish.
