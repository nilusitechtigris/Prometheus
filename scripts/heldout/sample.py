#!/usr/bin/env python3
"""Draws the frozen question sets from four public benchmarks.

    python3 scripts/heldout/sample.py            # downloads the sources, writes benchmarks/heldout/
    python3 scripts/heldout/sample.py --check    # only checks the files on disk against MANIFEST.json

Two files come out. `heldout-v1.jsonl` is the held-out set: the harness is never tuned on it, nobody reads
its questions to decide a change, and its results are only ever reported. `practice-v1.jsonl` is drawn from
the same sources and shares no question (or question it was made from) with the held-out set. That one is
for looking at failures.

Everything that decides the draw is in this file: the pinned source versions, the seed, the split rule and
what is left out. Running it again gives the same files, byte for byte, and MANIFEST.json holds their hashes.
Only the standard library is used.
"""
import argparse, hashlib, json, os, random, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "benchmarks", "heldout"))
SEED = 20261110
VERSION = 1

SOURCES = {
    "gsm8k": {
        "url": "https://raw.githubusercontent.com/openai/grade-school-math/3101c7d5072418e28b9008a6636bde82a006892c/grade_school_math/data/test.jsonl",
        "license": "MIT", "name": "GSM8K (test split)",
        "cite": "Cobbe et al., 2021. Training Verifiers to Solve Math Word Problems. arXiv:2110.14168",
    },
    "gsmplus": {
        "url": "https://huggingface.co/datasets/qintongli/GSM-Plus/resolve/3b708db57b96a16e8e3368ed2956990c0809440e/data/testmini-00000-of-00001.jsonl",
        "license": "CC BY-SA 4.0", "name": "GSM-Plus (testmini split)",
        "cite": "Li et al., 2024. GSM-Plus: A Comprehensive Benchmark for Evaluating the Robustness of LLMs as Mathematical Problem Solvers. arXiv:2402.19255",
    },
    "ifeval": {
        "url": "https://huggingface.co/datasets/google/IFEval/resolve/966cd89545d6b6acfd7638bc708b98261ca58e84/ifeval_input_data.jsonl",
        "license": "Apache 2.0", "name": "IFEval",
        "cite": "Zhou et al., 2023. Instruction-Following Evaluation for Large Language Models. arXiv:2311.07911",
    },
    "mbpp": {
        "url": "https://raw.githubusercontent.com/google-research/google-research/f82046ba5aabbbb427dbfd38a254d26bff08b533/mbpp/sanitized-mbpp.json",
        "license": "CC BY 4.0", "name": "MBPP, sanitized (test split, task ids 11 to 510)",
        "cite": "Austin et al., 2021. Program Synthesis with Large Language Models. arXiv:2108.07732",
    },
}

# How many questions each set takes from each source.
COUNTS = {"heldout": {"gsm8k": 20, "gsmplus": 20, "ifeval": 40, "mbpp": 40},
          "practice": {"gsm8k": 10, "gsmplus": 10, "ifeval": 20, "mbpp": 20}}

# Left out before the draw, and why.
# GSM-Plus "critical thinking" items have no numeric answer: the right reply is that information is missing.
GSMPLUS_SKIPPED_TYPES = {"critical thinking"}
# IFEval instructions whose reference checker needs a language detector or a trained sentence splitter, which
# the app's checker (a port of the rest) doesn't have. A prompt using any of them is not drawn.
IFEVAL_SKIPPED = {"language:response_language", "change_case:english_capital", "change_case:english_lowercase",
                  "length_constraints:number_sentences", "change_case:capital_word_frequency"}
# Rows someone looked at while this script was written, to learn the file layouts. They can't be in either set.
SEEN_IFEVAL_KEYS = {1000}
SEEN_GSM_SEEDS = ("Three of the women at the cocktail party are wearing 4 inch heels",)

ANSWER_FORM = "Work it out, then finish with a last line in exactly this form:\nAnswer: <your answer>"


def fetch(name, cache):
    path = os.path.join(cache, name + os.path.splitext(SOURCES[name]["url"])[1])
    if not os.path.exists(path):
        os.makedirs(cache, exist_ok=True)
        request = urllib.request.Request(SOURCES[name]["url"], headers={"User-Agent": "prometheus-heldout-sampler"})
        with urllib.request.urlopen(request, timeout=120) as reply, open(path, "wb") as out:
            out.write(reply.read())
    with open(path, "rb") as file:
        data = file.read()
    return data, hashlib.sha256(data).hexdigest()


def side(identity):
    """Which set a source question may go to. A third of each source is for practice, the rest is held out.
    It depends only on the question itself, so a question and anything made from it stay on one side."""
    digest = hashlib.sha256(("prometheus-split-v1|" + identity).encode()).digest()
    return "practice" if digest[0] % 3 == 0 else "heldout"


def squeeze(text):
    return re.sub(r"\s+", " ", text).strip()


def number(text):
    text = text.replace(",", "").replace("$", "").strip()
    try:
        float(text)
        return text
    except ValueError:
        return None


def load(cache):
    pools = {"heldout": {k: [] for k in SOURCES}, "practice": {k: [] for k in SOURCES}}
    hashes = {}

    raw, hashes["gsm8k"] = fetch("gsm8k", cache)
    for index, line in enumerate(raw.decode().splitlines()):
        row = json.loads(line)
        answer = number(row["answer"].split("####")[-1])
        question = squeeze(row["question"])
        if answer is None or question.startswith(SEEN_GSM_SEEDS):
            continue
        pools[side(question)]["gsm8k"].append({
            "id": f"gsm8k-{index}", "source": "gsm8k", "category": "math", "_seed": question,
            "prompt": f"{row['question'].strip()}\n\n{ANSWER_FORM}", "check": {"type": "number", "value": answer}})

    raw, hashes["gsmplus"] = fetch("gsmplus", cache)
    for index, line in enumerate(raw.decode().splitlines()):
        row = json.loads(line)
        answer = number(str(row["answer"]))
        seed = squeeze(row["seed_question"])
        kind = row["perturbation_type"].strip().lower()
        if answer is None or kind in GSMPLUS_SKIPPED_TYPES or seed.startswith(SEEN_GSM_SEEDS):
            continue
        # By its seed question, so a variant never sits across the split from the question it was made from.
        pools[side(seed)]["gsmplus"].append({
            "id": f"gsmplus-{index}", "source": "gsmplus", "category": "math", "variant": kind, "_seed": seed,
            "prompt": f"{row['question'].strip()}\n\n{ANSWER_FORM}", "check": {"type": "number", "value": answer}})

    raw, hashes["ifeval"] = fetch("ifeval", cache)
    for line in raw.decode().splitlines():
        row = json.loads(line)
        ids = row["instruction_id_list"]
        if row["key"] in SEEN_IFEVAL_KEYS or any(i in IFEVAL_SKIPPED for i in ids):
            continue
        instructions = [{"id": i, "kwargs": {k: v for k, v in (kw or {}).items() if v is not None}}
                        for i, kw in zip(ids, row["kwargs"])]
        pools[side(f"ifeval-{row['key']}")]["ifeval"].append({
            "id": f"ifeval-{row['key']}", "source": "ifeval", "category": "instructions",
            "prompt": row["prompt"], "check": {"type": "ifeval", "instructions": instructions}})

    raw, hashes["mbpp"] = fetch("mbpp", cache)
    for row in json.loads(raw.decode()):
        if not 11 <= row["task_id"] <= 510:
            continue
        tests = "\n".join(row["test_list"])
        prompt = (f"{row['prompt'].strip()}\n\nYour code should pass these tests:\n\n{tests}\n\n"
                  "Reply with one Python code block that holds the whole solution.")
        pools[side(f"mbpp-{row['task_id']}")]["mbpp"].append({
            "id": f"mbpp-{row['task_id']}", "source": "mbpp", "category": "coding",
            "prompt": prompt, "check": {"type": "python_tests", "imports": row.get("test_imports", []), "tests": row["test_list"]}})
    return pools, hashes


def draw(pools):
    sets = {}
    for which, counts in COUNTS.items():
        chosen = []
        for source in ("gsm8k", "gsmplus", "ifeval", "mbpp"):
            pool = sorted(pools[which][source], key=lambda item: item["id"])
            rng = random.Random(f"{SEED}|{which}|{source}")
            if source == "gsmplus":
                # The same number from each kind of change, as far as it goes. Each comes from a different GSM8K
                # question, and none from a question this set already took from GSM8K itself, so no problem
                # counts twice.
                used = {item["_seed"] for item in chosen if item["source"] == "gsm8k"}
                by_kind = {}
                for item in pool:
                    by_kind.setdefault(item["variant"], []).append(item)
                for kind in by_kind:
                    rng.shuffle(by_kind[kind])
                picked, kinds = [], sorted(by_kind)
                while len(picked) < counts[source] and any(by_kind.values()):
                    for kind in kinds:
                        while by_kind[kind] and len(picked) < counts[source]:
                            item = by_kind[kind].pop()
                            if item["_seed"] not in used:
                                used.add(item["_seed"])
                                picked.append(item)
                                break
            else:
                picked = rng.sample(pool, counts[source])
            if len(picked) != counts[source]:
                sys.exit(f"not enough {source} questions for {which}")
            chosen += sorted(picked, key=lambda item: item["id"])
        sets[which] = chosen
    return sets


def serialise(items):
    # Keys that start with an underscore were only for making the draw.
    rows = [{key: value for key, value in item.items() if not key.startswith("_")} for item in items]
    return "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows).encode()


def notice(hashes):
    lines = ["# Where these questions come from", "",
             "The files in this folder are samples of public benchmarks, reformatted. They are not under the "
             "Apache License that covers the code in this repository: each keeps its source's licence.", "",
             "| Source | Licence | Version drawn from | Citation |", "| --- | --- | --- | --- |"]
    for key, source in SOURCES.items():
        lines.append(f"| {source['name']} | {source['license']} | [file]({source['url']}) | {source['cite']} |")
    lines += ["", "What was changed: a fixed sample was drawn (`scripts/heldout/sample.py`), each question was given the "
              "app's answer form or a line asking for one code block, and answers were moved into a `check` field. "
              "GSM-Plus is share-alike, so its questions here stay under CC BY-SA 4.0. The instruction checks for the "
              "IFEval questions are a port of the reference checkers (Apache 2.0) and are not identical to them, so "
              "results are \"IFEval-derived\", not IFEval scores.", "",
              "SHA-256 of each source file as downloaded:", ""]
    lines += [f"- `{key}`: `{value}`" for key, value in sorted(hashes.items())]
    return ("\n".join(lines) + "\n").encode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", default=os.path.join(HERE, ".cache"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    manifest_path = os.path.join(OUT, "MANIFEST.json")
    if args.check:
        manifest = json.load(open(manifest_path))
        for name, expected in manifest["files"].items():
            actual = hashlib.sha256(open(os.path.join(OUT, name), "rb").read()).hexdigest()
            print(("ok   " if actual == expected["sha256"] else "DIFF ") + name)
            if actual != expected["sha256"]:
                sys.exit(1)
        return

    pools, hashes = load(args.cache)
    sets = draw(pools)
    held = {item["id"] for item in sets["heldout"]}
    assert not held & {item["id"] for item in sets["practice"]}
    for which, items in sets.items():
        seeds = [item["_seed"] for item in items if "_seed" in item]
        assert len(seeds) == len(set(seeds)), f"{which} has two questions from one GSM8K problem"
    assert not ({i["_seed"] for i in sets["heldout"] if "_seed" in i} & {i["_seed"] for i in sets["practice"] if "_seed" in i})
    os.makedirs(OUT, exist_ok=True)
    files = {f"heldout-v{VERSION}.jsonl": serialise(sets["heldout"]), f"practice-v{VERSION}.jsonl": serialise(sets["practice"]),
             "NOTICE.md": notice(hashes)}
    manifest = {"version": VERSION, "seed": SEED, "sources": {k: {"url": v["url"], "sha256": hashes[k]} for k, v in SOURCES.items()},
                "files": {}, "counts": {}, "pools": {}}
    for name, data in files.items():
        with open(os.path.join(OUT, name), "wb") as out:
            out.write(data)
        manifest["files"][name] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    for which in sets:
        manifest["counts"][which] = {source: sum(1 for i in sets[which] if i["source"] == source) for source in SOURCES}
        manifest["pools"][which] = {source: len(pools[which][source]) for source in SOURCES}
    with open(manifest_path, "w") as out:
        json.dump(manifest, out, indent=2, sort_keys=True)
        out.write("\n")
    # Counts and hashes only: the held-out questions themselves are not for reading.
    print(json.dumps({"counts": manifest["counts"], "pools": manifest["pools"],
                      "files": {k: v["sha256"][:16] for k, v in manifest["files"].items()}}, indent=2))


if __name__ == "__main__":
    main()
