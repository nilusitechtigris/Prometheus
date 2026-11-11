# Changelog

## 2.0.0 beta

On `main` since 10 November 2026. Not tagged as a release yet.

Every number this project quotes comes from a run someone made in the app. Where there is one run, it says one run. No held-out results are published yet.

### New

- **Side by side.** Ask once and see the plain model and the harness answer the same question next to each other, with a line from code about what it could check. One click saves a picture of it to share.
- **A three-question demo** on the empty chat page: two sums and a small program, the kind of thing small models get wrong and the harness can check.
- **Setup without Terminal.** With nothing installed, the chat page has a Get Ollama button and then one button for a starter model picked for the Mac's memory. A failed download says what to do about it.
- **Held-out test.** 120 public questions (GSM8K, GSM-Plus, IFEval, MBPP) that the harness is never tuned on, graded by code. The app shows totals and keeps the questions and replies closed. A separate 60-question practice set is where failures get studied.
- **Repeat runs.** Run a Harness Test three times and see every round's score, the mean and the spread. For any two runs on the same questions, the app says how often chance alone would flip that many answers that unevenly.
- **Harness v6, the evidence loop.** It answers from memory first, looks things up only where that helps, reads a page as a few quoted sentences, and settles letter counts, word counts, weekdays and day spans with plain code. Not the default and not scored yet, so it shows in the lab edition only.
- **Dev harness v2, the checked build.** After an app works it runs extra checks, tries one fix for each thing it finds, and keeps the fix only if it holds. It reports what it could not fix. Not the default and not scored yet, so it shows in the lab edition only.
- **One harness, v7.** It sends each task down one route and switches on only the parts that route needs, and it starts from the plain model's reply where it can. A request for code has its reply's code run on the examples in the message, and a fact is only looked up when the model isn't sure of it. Lab edition only, and not scored yet.
- **By route** on the Harness Test: for each kind of task, the questions that went right with the harness and without, and how many flipped each way. It works on runs already made.
- **A copy of your data before every new build touches it.** Chats, test history, Dev mode's chats and comparisons, and shared notes are copied once per build into `Backups`, and the newest five copies are kept.

### Changed

- **A new look.** The sidebar is gone: a header holds the name, and a dock at the foot of the window holds the pages. Home is one question and a box to answer it in, and asking there starts a chat. There are two dark themes, Ember and Rose, as two dots at the end of the title bar; they replace lime and the other themes, and a theme saved by an older copy becomes Ember. One glass flame is lit in the middle of Home each time you come to it.
- **Harness on now means one thing:** v3, the loop, and the app offers no other. The earlier and newer versions stay in the code so results can be repeated. One Terminal line turns a copy into the lab edition, which shows them: see [the harness](docs/harness.md).
- **New installs start with the harness on.** Existing installs keep their setting.
- **Web lookups ask first.** Before the harness searches or opens a page it shows what it will send and where. "Always" and "Never" are in Settings › Harness.
- **Telemetry is a page of its own.** GPU load, memory and heat show at the foot of the window on every page, on one line with the dock. A click there, or ⌥⌘1, opens the Telemetry page, and Back, Esc or ⌥⌘1 returns to the page you were on. It used to be a strip under the chat.
- **Tests opens on an overview:** one card each for the Model test, this Mac and the Harness test, with the last result. Publish is in the lab edition only.
- **Five pages in the dock: Home, Chat, Models, Tests, Settings.** Ask is now Home and History is now Chat. Dev is no longer a page of its own: it is the other face of Chat, behind a switch (Ask, Dev) at the top left of the Chat page that stays in the same place on both, and ⇧⌘D flips it from anywhere. The Dev button under the message box and the last task at the foot of Home are gone.
- **Home starts either kind of work.** Under its question are a **Dev** toggle, the project the agent will work in, and **Compare**, which does the task with the harness off and with it on. They sit on one line with the model, the harness and the context window, as icons that light up when they are on; only the model keeps its name, and each icon explains itself in a card while the pointer rests on it. Send starts the work on the Chat page, and asks for a project folder first if Dev has none. The app always opens with Dev off.
- **On Home, the model, the harness and the context window are chosen in place,** each in its own menu under the question. The model and the harness used to lead away to Models and Settings.
- **The list of chats has a button in the Chat page's top bar** that hides and shows it. Hidden from its own header, it used to come back only after leaving the page.
- **One look for every panel.** Tiles on the test pages, cards on Models, Telemetry's panels and the groups in Settings share one colour, one corner, one edge and the same small glow. The glow used to be on one card of the Tests overview only, and stronger.
- **Tabs you can see are buttons.** The tests on Tests and the sections of Settings are pills, like the kinds of model on Models.
- **Settings sits in the middle of the page,** like the other pages.
- **Dev's top bar is one line of pills of one height,** and the headers of Files, the editor, the agent and the Terminal line up across the window.
- **A short README.** It says what the app is, shows it and gets you installed. The details moved to pages under `docs/`: install and update, Dev mode, the tests, the harness, privacy and safety, and the project layout. Every picture is from 2.0.
- The Harness Test says before it starts that its knowledge tasks use the web.
- Every custom button lights up under the pointer, dims while pressed and greys out when it can't be used.
- Heat is shown in plain words ("Heat: normal", "hottest 43°C"), and meters use a plain mark.
- Home and the header say what is missing (Ollama not installed, not running, no model yet) and lead to the next step.
- With the harness on, the default prompt no longer tells the model it has no tools. A prompt you wrote is left alone.
- The version shows in Settings › Updates beside the commit.

### Fixed

- The Tests overview put the chosen model's name under a harness score that came from another model. It now names the run's own model.
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
