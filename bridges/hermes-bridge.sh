#!/usr/bin/env bash
# Hermes bridge script — invokes Hermes CLI in single-query mode
# Strips banner/chrome, returns only the response text
#
# Usage:
#   ./hermes-bridge.sh "Your prompt here"
#   ./hermes-bridge.sh "Your prompt here" /path/to/workdir
#
# Environment:
#   HERMES_PROJECT_DIR — path to hermes-agent project (default: /home/workspace/hermes-agent)
#   HERMES_VENV        — path to venv activate script (default: $HERMES_PROJECT_DIR/.venv/bin/activate)
#   HERMES_TIMEOUT     — timeout in seconds (default: 300)

set -euo pipefail

PROMPT="${1:?Usage: hermes-bridge.sh \"prompt\" [workdir]}"
WORKDIR="${2:-/home/workspace}"
TIMEOUT="${HERMES_TIMEOUT:-300}"
PROJECT_DIR="${HERMES_PROJECT_DIR:-/home/workspace/hermes-agent}"
VENV_ACTIVATE="${HERMES_VENV:-$PROJECT_DIR/.venv/bin/activate}"

# OmniRoute failover — route API calls through OmniRoute proxy
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://omniroute-marlandoj.zocomputer.io/v1}"
export OPENAI_API_KEY="${OMNIROUTE_API_KEY:-02cfc434d560577253444213a884d7cdcf4ab142f21aecea51b3a29fff01784b}"
# v4.7: Tiered model routing — orchestrator sets SWARM_RESOLVED_MODEL per task
# Priority: SWARM_RESOLVED_MODEL > LLM_MODEL > (empty = OmniRoute default)
export LLM_MODEL="${SWARM_RESOLVED_MODEL:-${LLM_MODEL:-}}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: Hermes project dir not found: $PROJECT_DIR" >&2
  exit 1
fi

if [ ! -f "$VENV_ACTIVATE" ]; then
  echo "ERROR: Hermes venv not found: $VENV_ACTIVATE" >&2
  exit 1
fi

cd "$PROJECT_DIR"
source "$VENV_ACTIVATE"

STDERR_LOG="/tmp/hermes-bridge-stderr-$$.log"
OUTPUT_FILE="/tmp/hermes-bridge-output-$$.txt"

# Run Hermes in quiet single-query mode, strip banner chrome
timeout "$TIMEOUT" python cli.py -q "$PROMPT" 2>"$STDERR_LOG" \
  | sed -n '/^╭─ ⚕ Hermes/,/^╰──/p' \
  | sed '1d;$d' \
  | sed 's/\r//g' \
  | sed '/^$/d' > "$OUTPUT_FILE"
EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -ne 0 ]; then
  echo "BRIDGE_ERROR: exit=$EXIT_CODE stderr=$(head -5 "$STDERR_LOG" 2>/dev/null)" >&2
  rm -f "$STDERR_LOG" "$OUTPUT_FILE"
  exit $EXIT_CODE
fi

# Safety check: if sed pipeline stripped everything, fall back to raw output
if [ ! -s "$OUTPUT_FILE" ]; then
  echo "BRIDGE_WARN: banner parsing returned empty output, retrying with raw capture" >&2
  timeout "$TIMEOUT" python cli.py -q "$PROMPT" 2>/dev/null > "$OUTPUT_FILE"
  EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    echo "BRIDGE_ERROR: raw retry failed, exit=$EXIT_CODE" >&2
    rm -f "$STDERR_LOG" "$OUTPUT_FILE"
    exit $EXIT_CODE
  fi
fi

cat "$OUTPUT_FILE"
rm -f "$STDERR_LOG" "$OUTPUT_FILE"
exit 0
