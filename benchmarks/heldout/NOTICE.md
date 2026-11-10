# Where these questions come from

The files in this folder are samples of public benchmarks, reformatted. They are not under the Apache License that covers the code in this repository: each keeps its source's licence.

| Source | Licence | Version drawn from | Citation |
| --- | --- | --- | --- |
| GSM8K (test split) | MIT | [file](https://raw.githubusercontent.com/openai/grade-school-math/3101c7d5072418e28b9008a6636bde82a006892c/grade_school_math/data/test.jsonl) | Cobbe et al., 2021. Training Verifiers to Solve Math Word Problems. arXiv:2110.14168 |
| GSM-Plus (testmini split) | CC BY-SA 4.0 | [file](https://huggingface.co/datasets/qintongli/GSM-Plus/resolve/3b708db57b96a16e8e3368ed2956990c0809440e/data/testmini-00000-of-00001.jsonl) | Li et al., 2024. GSM-Plus: A Comprehensive Benchmark for Evaluating the Robustness of LLMs as Mathematical Problem Solvers. arXiv:2402.19255 |
| IFEval | Apache 2.0 | [file](https://huggingface.co/datasets/google/IFEval/resolve/966cd89545d6b6acfd7638bc708b98261ca58e84/ifeval_input_data.jsonl) | Zhou et al., 2023. Instruction-Following Evaluation for Large Language Models. arXiv:2311.07911 |
| MBPP, sanitized (test split, task ids 11 to 510) | CC BY 4.0 | [file](https://raw.githubusercontent.com/google-research/google-research/f82046ba5aabbbb427dbfd38a254d26bff08b533/mbpp/sanitized-mbpp.json) | Austin et al., 2021. Program Synthesis with Large Language Models. arXiv:2108.07732 |

What was changed: a fixed sample was drawn (`scripts/heldout/sample.py`), each question was given the app's answer form or a line asking for one code block, and answers were moved into a `check` field. GSM-Plus is share-alike, so its questions here stay under CC BY-SA 4.0. The instruction checks for the IFEval questions are a port of the reference checkers (Apache 2.0) and are not identical to them, so results are "IFEval-derived", not IFEval scores.

SHA-256 of each source file as downloaded:

- `gsm8k`: `3730d312f6e3440559ace48831e51066acaca737f6eabec99bccb9e4b3c39d14`
- `gsmplus`: `6653b4b941956da12ba0af2eae660800db13a901123553b163b77be2d20eb7d5`
- `ifeval`: `6a85310ca8ce15eff755aa08a3a4ff931c7e273e7515ebb3c492ea85fd8288f2`
- `mbpp`: `ca95deaa9a01ef0a6f439f88bcf0dd3db3563d22f22aad6cae04ebb9a8d8c8e9`
