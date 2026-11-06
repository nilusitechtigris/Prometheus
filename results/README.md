# Shared test results

Test results from people's own Macs. Each file is one publish from the app.

## Add yours

1. In Prometheus, open **Tests › Publish**, tick the runs you want to share and press **Publish**.
2. Drag the file from Finder onto the GitHub page that opens.
3. Press **Propose changes**, then **Create pull request**.

GitHub asks you to sign in, and makes the fork and the branch for you. The file is public once you submit it.

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

In `modelRuns`, each run has its setup (`model`, `quant`, `backend`, `contextLength`, `thinking`), its speed (`tokensPerSecond`, `timeToFirstToken`, `promptTokensPerSecond`) and one entry in `items` for each question. An item holds the question's `id`, `level` and `category`, the `expected` answer, the model's `answer`, whether it `passed`, and its time and token counts. Levels 1 to 4 are worth 1, 2, 4 and 8 points.

Harness runs also have `harness`, `harnessVersion`, `injectionWith` and `injectionWithout`, and `baselineRunID` points to the harness-off run in the same file that they compare with. If it's missing, the run was made with the harness on only.

## Comparing runs

- Only compare runs with the same `suiteVersion`: the questions, points or token limits differ between versions.
- Compare on the same `model`, `quant`, `contextLength` and `thinking`, because those change the score as well.
- These are single runs, and thinking models vary from run to run, so don't read much into small differences.
