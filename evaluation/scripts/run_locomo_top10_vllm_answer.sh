#!/usr/bin/env bash
# Reuse an existing complete LOCOMO top-10 retrieval set, changing only the Answerer.
# Run from any working directory. Requires the local vLLM service and a remote Judge API.
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$EVAL_DIR"

SOURCE_DIR="results/locomo/predicted_qwen38-locomo-full"
PROJECT="qwen38-locomo-top10-vllm-answer"
RESULT_DIR="results/locomo/predicted_${PROJECT}"
LOG_DIR="logs"
mkdir -p "$LOG_DIR"

# Export JUDGE_BASE_URL and JUDGE_API_KEY before launching, or source the
# environment file used by your existing remote Judge configuration.
: "${JUDGE_BASE_URL:?Set JUDGE_BASE_URL to the ORIGINAL remote Judge API endpoint}"
: "${JUDGE_API_KEY:?Set JUDGE_API_KEY to the ORIGINAL remote Judge API key}"

if [[ ! -d "$RESULT_DIR" ]]; then
    [[ -d "$SOURCE_DIR" ]] || { echo "Missing source retrieval directory: $SOURCE_DIR" >&2; exit 1; }
    mkdir -p "$RESULT_DIR"
    python - "$SOURCE_DIR" "$RESULT_DIR" <<'PY'
import json
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
files = sorted(source.glob("conv*_q*.json"))
if not files:
    raise SystemExit("No per-question JSON files in source directory")
for path in files:
    data = json.loads(path.read_text(encoding="utf-8"))
    results = (data.get("retrieval") or {}).get("search_results")
    if not isinstance(results, list):
        raise SystemExit(f"Missing retrieval.search_results: {path}")
    # Keep original top-10 retrieval, question, ground truth and metadata.
    data.pop("cutoff_results", None)
    (destination / path.name).write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
print(f"Copied {len(files)} top-10 retrieval records; original results unchanged.")
PY
fi

# No --resume: evaluate-only skips a question when newly generated cutoff_results exist.
# No --rejudge: restarting this script keeps already completed NEW Answerer results.
nohup python -u -m benchmarks.locomo.run \
  --project-name "$PROJECT" \
  --run-id qwen38locomofull20261023 \
  --provider openai \
  --answerer-model Qwen3.8-27B-NVFP4 \
  --answerer-base-url http://127.0.0.1:8000/v1 \
  --answerer-api-key EMPTY \
  --judge-provider openai \
  --judge-model qwen3.5-397b-a17b \
  --judge-base-url "$JUDGE_BASE_URL" \
  --judge-api-key "$JUDGE_API_KEY" \
  --conversations 0,1,2,3,4,5,6,7,8,9 \
  --categories 1,2,3,4 \
  --max-workers 1 \
  --top-k 10 \
  --top-k-cutoffs 10 \
  --rpm 60 \
  --disable-thinking \
  --vllm \
  --evaluate-only \
  --show-llm-output \
  > "$LOG_DIR/qwen38-locomo-top10-vllm-answer.log" 2>&1 < /dev/null &

echo $! > "$LOG_DIR/qwen38-locomo-top10-vllm-answer.pid"
echo "Benchmark PID: $(cat "$LOG_DIR/qwen38-locomo-top10-vllm-answer.pid")"
echo "Log: $LOG_DIR/qwen38-locomo-top10-vllm-answer.log"
