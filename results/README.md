# Shared test results

Test results from people's own Macs. Each publish adds two files: a `.md` report to read, with a row for each task and every reply, and a `.json` file with the same runs for tools.

## Add yours

1. In Prometheus, open **Tests › Publish**, tick the runs you want to share and press **Publish**. It saves both files, copies the `.json` one and opens a new file on GitHub with its name filled in.
2. Sign in if GitHub asks, click in the empty file and press **⌘V**.
3. Press **Commit changes…**, then **Propose changes** and **Create pull request**.
4. Add the `.md` report the same way: press **Copy and Open** on its row in Prometheus.

GitHub makes the fork and the branch for you. Its **Upload files** page only works for people who can push to this repository, so Prometheus doesn't use it. A file is public once you submit it.

## What's in a file

The file name is the machine, chip, memory and time, as in `mac-mini-m4-pro-48gb-2026-11-06-1523.json`.

| Field | What it holds |
| --- | --- |
| `format` | The layout of this file, currently 1 |
| `app` | The commit of the app that wrote it |
| `createdAt` | When it was written |
| `machine` | `name`, `identifier`, `chip`, `cpuCores`, `gpuCores`, `memoryGB`, `macOS` |
| `modelRuns` | Model Test and Harness Test runs |
| `hardwareRuns` | Hardware Test runs |

In `modelRuns`, each run has its setup (`model`, `quant`, `backend`, `contextLength`, `thinking`), its speed (`tokensPerSecond`, `timeToFirstToken`, `promptTokensPerSecond`) and one entry in `items` for each question. A run also has its `score`, `points`, `maxPoints` and `passedTasks`. An item holds the question's `id`, `level`, `category` and `prompt`, the `expected` answer, the model's full `answer` and its `finalAnswer`, the end of its `thinking`, whether it `passed`, its `points` and `maxPoints`, `seconds`, `thinkingTokens`, `outputTokens`, `totalTokens`, `promptTokens`, `stopReason`, `ranOutOfTokens` and, in harness runs, the `toolLog` of steps it took. Levels 1 to 4 are worth 1, 2, 4 and 8 points.

Harness runs also have `harness`, `harnessVersion`, `injectionWith` and `injectionWithout`, and `baselineRunID` points to the harness-off run in the same file that they compare with. If it's missing, the run was made with the harness on only. Runs from Harness - Normal have `quick: true` and 9 items, with no poisoned pages.

Runs from Harness - Held-out have `questionSet`, such as `heldout-v1`, and `suiteVersion: 101`. They ask the 120 public questions in [`benchmarks/heldout`](../benchmarks/heldout), which the harness is never tuned on. Every question is worth one point, so the score is the share answered right. They have no poisoned pages, and `pythonVersion` says which Python graded the code questions. Runs with `questionSet: practice-v1` and `suiteVersion: 102` ask the 60 practice questions instead. The harness may be tuned on those, so a practice run is not evidence of anything.

The `.md` report of a held-out run gives totals and right answers by source, without the replies. The `.json` file has every reply, so anyone can check the grading. If you work on the harness, don't read them: a change made because of a held-out reply spends the set.

Runs made together as repeats share a `repeatGroup`, and `repeatIndex` counts them from 1. Each repeat has its own harness-off run.

## Comparing runs

- Only compare runs with the same `suiteVersion`: the questions, points or token limits differ between versions.
- Never compare a `quick` run with a full one, or either with a `questionSet` run: they ask different questions, so their scores mean different things.
- Where there are repeats, look at all of them. A gap smaller than the spread between repeats of one setup isn't a result. The test asks the plain model at temperature 0, so repeats mostly show how much the harness itself varies.
- For two runs on the same questions, count the questions that flipped each way. If chance would often split them that unevenly, the gap isn't a result either.
- Compare on the same `model`, `quant`, `contextLength` and `thinking`, because those change the score as well.
- These are single runs, and thinking models vary from run to run, so don't read much into small differences.
