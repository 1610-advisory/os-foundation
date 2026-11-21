#!/usr/bin/env python3
"""Classify made-up notes with a local Ollama model and score the holds.

Stdlib only. Talks to http://localhost:11434/api/generate. Does not call a
hosted model and does not pull a model.

Hold when the model's label is not clean and its score is at least the
threshold. Thresholds are applied after the run, so one pass feeds 0.5, 0.7,
and 0.9.

Usage:
  python3 tests/classifier/run.py
  python3 tests/classifier/run.py --model gemma4:31b
  python3 tests/classifier/run.py --set hard --model qwen3.6:35b
  python3 tests/classifier/run.py --summarize

The main set writes tests/classifier/RESULTS.md. The hard set prints a
summary and leaves that file alone. Hard-set raw replies go in
tests/classifier/hard/raw/.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROMPT_PATH = ROOT / "prompt.md"
RESULTS = ROOT / "RESULTS.md"
OLLAMA = "http://localhost:11434/api/generate"
MODELS = ("gemma4:31b", "qwen3.6:35b")
THRESHOLDS = (0.5, 0.7, 0.9)
CLASSES = ("clean", "fee", "candid", "other-client", "person")
LABELS_OK = set(CLASSES)
# Hard notes are long. 8192 covers the prompt plus a 1,500-word note.
HARD_NUM_CTX = 8192


def set_paths(name: str) -> dict:
    if name == "main":
        return {
            "notes": ROOT / "notes",
            "labels": ROOT / "labels.csv",
            "raw": ROOT / "raw",
            "expect": 50,
            "num_ctx": None,
            "write_results": True,
        }
    if name == "hard":
        return {
            "notes": ROOT / "hard" / "notes",
            "labels": ROOT / "hard" / "labels.csv",
            "raw": ROOT / "hard" / "raw",
            "expect": 40,
            "num_ctx": HARD_NUM_CTX,
            "write_results": False,
        }
    raise SystemExit(f"unknown set: {name}")


def slug(model: str) -> str:
    return model.replace(":", "-").replace("/", "-")


def load_labels(labels_path: Path, notes_dir: Path, expect: int) -> list[tuple[str, str]]:
    rows = []
    for line in labels_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("file,"):
            continue
        file, expected = [part.strip() for part in line.split(",", 1)]
        if expected not in LABELS_OK:
            raise SystemExit(f"bad label for {file}: {expected}")
        if not (notes_dir / file).is_file():
            raise SystemExit(f"missing note: {file}")
        rows.append((file, expected))
    if len(rows) != expect:
        raise SystemExit(f"expected {expect} notes, found {len(rows)}")
    return rows


def load_done(path: Path) -> dict[str, dict]:
    done = {}
    if not path.is_file():
        return done
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("ok"):
            done[row["file"]] = row
    return done


def normalize_label(value) -> str | None:
    if not isinstance(value, str):
        return None
    label = value.strip().lower().replace("_", "-").replace(" ", "-")
    if label in ("otherclient", "other-clients"):
        label = "other-client"
    if label in LABELS_OK:
        return label
    return None


def parse_response(text: str) -> tuple[str | None, float | None]:
    raw = (text or "").strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        if raw.lower().startswith("json"):
            raw = raw[4:]
        raw = raw.strip()
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        return None, None
    if not isinstance(obj, dict):
        return None, None
    label = normalize_label(obj.get("label"))
    score = obj.get("score")
    if isinstance(score, str):
        try:
            score = float(score)
        except ValueError:
            score = None
    if isinstance(score, bool) or not isinstance(score, (int, float)):
        return label, None
    score = float(score)
    if score < 0 or score > 1:
        return label, None
    return label, score


def generate(model: str, prompt: str, timeout: int, num_ctx: int | None) -> dict:
    options: dict = {"temperature": 0, "num_predict": 80}
    if num_ctx is not None:
        options["num_ctx"] = num_ctx
    body = {
        "model": model,
        "prompt": prompt,
        "format": "json",
        "stream": False,
        "think": False,
        "keep_alive": "30m",
        "options": options,
    }
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        OLLAMA, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def classify_one(
    model: str, prompt: str, note: str, timeout: int, num_ctx: int | None
) -> dict:
    full = prompt.rstrip() + "\n\n## Note\n\n" + note
    last_error = "no attempt"
    for _ in range(2):
        started = time.perf_counter()
        try:
            out = generate(model, full, timeout, num_ctx)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = str(exc)
            continue
        seconds = time.perf_counter() - started
        text = out.get("response") or ""
        label, score = parse_response(text)
        if label is None or score is None:
            last_error = "bad json: " + text[:180]
            continue
        return {
            "ok": True,
            "label": label,
            "score": score,
            "seconds": round(seconds, 3),
            "raw": text,
            "eval_count": out.get("eval_count"),
        }
    return {"ok": False, "error": last_error, "seconds": None, "label": None, "score": None}


def warmup(model: str, timeout: int, num_ctx: int | None) -> None:
    prompt = 'Reply with JSON only: {"label":"clean","score":0.5}'
    classify_one(model, prompt, "warmup", timeout, num_ctx)


def run_model(
    model: str,
    rows: list[tuple[str, str]],
    prompt: str,
    timeout: int,
    notes_dir: Path,
    raw_dir: Path,
    num_ctx: int | None,
) -> None:
    raw_dir.mkdir(parents=True, exist_ok=True)
    path = raw_dir / f"{slug(model)}.jsonl"
    done = load_done(path)
    pending = [row for row in rows if row[0] not in done]
    print(f"{model}: {len(done)} done, {len(pending)} to run", flush=True)
    if not pending:
        return
    print(f"{model}: warmup", flush=True)
    warmup(model, timeout, num_ctx)
    with path.open("a") as handle:
        for index, (file, expected) in enumerate(pending, start=1):
            note = (notes_dir / file).read_text()
            result = classify_one(model, prompt, note, timeout, num_ctx)
            record = {
                "model": model,
                "file": file,
                "expected": expected,
                **result,
            }
            handle.write(json.dumps(record) + "\n")
            handle.flush()
            status = (
                f"{result['label']} {result['score']}"
                if result["ok"]
                else result.get("error")
            )
            print(
                f"{model} {index}/{len(pending)} {file} expected={expected} {status}",
                flush=True,
            )


def held(row: dict, threshold: float) -> bool:
    label = row.get("label")
    score = row.get("score")
    if not row.get("ok") or label is None or score is None:
        return False
    return label != "clean" and score >= threshold


def load_raw(model: str, raw_dir: Path) -> list[dict]:
    path = raw_dir / f"{slug(model)}.jsonl"
    if not path.is_file():
        return []
    latest: dict[str, dict] = {}
    for line in path.read_text().splitlines():
        if line.strip():
            row = json.loads(line)
            latest[row["file"]] = row
    return [latest[name] for name in sorted(latest)]


def pct(num: int, den: int) -> str:
    if den == 0:
        return "n/a"
    return f"{num}/{den} ({100.0 * num / den:.0f}%)"


def summarize(models: list[str], raw_dir: Path, expect: int) -> str:
    lines = ["# Leak classifier results", ""]
    lines.append(
        "Local Ollama only (`format: json`, `think: false`, temperature 0). "
        "A hold is a label other than clean with score at or above the threshold. "
        "Recall is exact label match. A miss is a leak note that was not held."
    )
    lines.append("")
    for model in models:
        rows = load_raw(model, raw_dir)
        lines.append(f"## {model}")
        lines.append("")
        if len(rows) != expect:
            lines.append(f"Incomplete run: {len(rows)} of {expect} notes.")
            lines.append("")
            continue
        n_clean = sum(1 for row in rows if row["expected"] == "clean")
        seconds = [row["seconds"] for row in rows if row.get("seconds") is not None]
        mean = sum(seconds) / len(seconds) if seconds else 0
        lines.append(f"Seconds per note: {mean:.1f} (n={len(seconds)}).")
        lines.append("")
        lines.append("| Threshold | Clean false holds | Fee held | Person held | Candid held | Other-client held | Fee+person misses |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")
        for threshold in THRESHOLDS:
            false_holds = [row for row in rows if row["expected"] == "clean" and held(row, threshold)]
            def held_count(kind: str) -> str:
                group = [row for row in rows if row["expected"] == kind]
                got = sum(1 for row in group if held(row, threshold))
                return pct(got, len(group))
            fee_person = [
                row for row in rows
                if row["expected"] in ("fee", "person") and not held(row, threshold)
            ]
            lines.append(
                f"| {threshold:.1f} | {len(false_holds)}/{n_clean} | {held_count('fee')} | "
                f"{held_count('person')} | {held_count('candid')} | {held_count('other-client')} | "
                f"{len(fee_person)} |"
            )
        lines.append("")
        lines.append("Exact-label recall:")
        lines.append("")
        lines.append("| Class | Recall | Wrong labels |")
        lines.append("| --- | --- | --- |")
        for kind in CLASSES:
            group = [row for row in rows if row["expected"] == kind]
            right = [row for row in group if row.get("label") == kind]
            wrong = sorted({row.get("label") or "invalid" for row in group if row.get("label") != kind})
            lines.append(f"| {kind} | {pct(len(right), len(group))} | {', '.join(wrong) if wrong else '-'} |")
        lines.append("")
        lines.append("Misses (not held) by file:")
        lines.append("")
        for threshold in THRESHOLDS:
            missed = [
                row for row in rows
                if row["expected"] != "clean" and not held(row, threshold)
            ]
            if not missed:
                lines.append(f"- {threshold:.1f}: none")
                continue
            bits = [
                f"{row['file']} (expected {row['expected']}, got {row.get('label')} {row.get('score')})"
                for row in missed
            ]
            lines.append(f"- {threshold:.1f}: " + "; ".join(bits))
        lines.append("")
        lines.append("False holds on clean notes:")
        lines.append("")
        for threshold in THRESHOLDS:
            false_holds = [row for row in rows if row["expected"] == "clean" and held(row, threshold)]
            if not false_holds:
                lines.append(f"- {threshold:.1f}: none")
                continue
            bits = [
                f"{row['file']} (got {row.get('label')} {row.get('score')})"
                for row in false_holds
            ]
            lines.append(f"- {threshold:.1f}: " + "; ".join(bits))
        lines.append("")
        label_misses = [row for row in rows if row.get("label") != row["expected"]]
        lines.append("Label mismatches (held or not):")
        lines.append("")
        if not label_misses:
            lines.append("- none")
        else:
            for row in label_misses:
                lines.append(
                    f"- {row['file']}: expected {row['expected']}, got {row.get('label')} {row.get('score')}"
                )
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", action="append", dest="models")
    parser.add_argument("--set", dest="set_name", choices=("main", "hard"), default="main")
    parser.add_argument("--summarize", action="store_true")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    chosen = set_paths(args.set_name)
    models = args.models or list(MODELS)
    if not args.summarize:
        rows = load_labels(chosen["labels"], chosen["notes"], chosen["expect"])
        prompt = PROMPT_PATH.read_text()
        for model in models:
            run_model(
                model,
                rows,
                prompt,
                args.timeout,
                chosen["notes"],
                chosen["raw"],
                chosen["num_ctx"],
            )
    text = summarize(
        models if args.models else list(MODELS),
        chosen["raw"],
        chosen["expect"],
    )
    if chosen["write_results"]:
        RESULTS.write_text(text)
        print(f"wrote {RESULTS}", flush=True)
    else:
        print(text, flush=True)


if __name__ == "__main__":
    main()
