# The held-out questions

Two fixed samples of public benchmarks, drawn once by [`scripts/heldout/sample.py`](../../scripts/heldout/sample.py).

| File | Questions | What it's for |
| --- | --- | --- |
| `heldout-v1.jsonl` | 120 | Reporting. The harness is never tuned on it. |
| `practice-v1.jsonl` | 60 | Looking at failures and trying changes. |

Each set takes a sixth of its questions from GSM8K, a sixth from GSM-Plus, a third from IFEval and a third from MBPP. The two share no question, and no GSM-Plus question sits across the split from the GSM8K question it was made from.

## The rules

1. Nobody reads the held-out questions or their replies to decide a change to the harness. Only totals are looked at.
2. A change is tried on the practice set, the app's own tests and questions people send in.
3. If a change is ever made because of something seen in the held-out set, that set is spent. The seed in the script goes up, a new set is drawn, and results from the old one are marked as such.
4. Every reported score says which file it came from (`MANIFEST.json` has the hashes), how many runs, and the model, quantization, framework, context and thinking setting.

## What a score here can't show

- The questions are public, so a model may have seen them in training. Harness off and on run on the same model and the same questions, so the gap between them still means something, but it can understate what the harness adds on new questions.
- The IFEval questions test the form of a reply, not whether it's true. Their checks are a port of the reference checkers and five instruction kinds are left out (see the script), so these are "IFEval-derived" results, not IFEval scores.
- MBPP is graded with its three tests for each task, which the question shows.
- 120 questions can show a gain of about 15 points. Smaller gaps, and gaps inside one source's 20 or 40 questions, are within the noise.
- Nothing here measures web lookups, long documents or prompt injection. The app's own Harness Test covers those.

Licences and citations are in [NOTICE.md](NOTICE.md). These files are not under the Apache License that covers the code.

## Checking the files

```bash
python3 scripts/heldout/sample.py --check
```

It compares the files with the hashes in `MANIFEST.json`. Running the script without `--check` downloads the sources at their pinned versions and writes the same files again.
