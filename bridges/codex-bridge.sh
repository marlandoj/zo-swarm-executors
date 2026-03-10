#!/usr/bin/env bash
# Codex CLI bridge script — invokes OpenAI Codex CLI in non-interactive mode
# Returns only the response text, suitable for scripted/orchestrator invocation
#
# Codex is the fastest local executor (~3s per call, Rust binary).
# Uses danger-full-access sandbox since the orchestrator runs in a trusted env.
#
# Usage:
#   ./codex-bridge.sh "Your prompt here"
#   ./codex-bridge.sh "Your prompt here" /path/to/workdir
#
# Environment:
#   CODEX_MODEL   — override model (default: uses config.toml default)
#   CODEX_TIMEOUT — timeout in seconds (default: 300)

set -euo pipefail

PROMPT="${1:?Usage: codex-bridge.sh \"prompt\" [workdir]}"
WORKDIR="${2:-/home/workspace}"
TIMEOUT="${CODEX_TIMEOUT:-600}"

# OmniRoute failover — route API calls through OmniRoute proxy
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://omniroute-marlandoj.zocomputer.io/v1}"
export OPENAI_API_KEY="${OMNIROUTE_API_KEY:-02cfc434d560577253444213a884d7cdcf4ab142f21aecea51b3a29fff01784b}"
CODEX_MODEL="${SWARM_RESOLVED_MODEL:-${CODEX_MODEL:-}}"

CODEX_BIN=""
if command -v codex &>/dev/null; then
  CODEX_BIN="codex"
elif [ -x "/usr/bin/codex" ]; then
  CODEX_BIN="/usr/bin/codex"
elif [ -x "/usr/local/bin/codex" ]; then
  CODEX_BIN="/usr/local/bin/codex"
else
  echo "ERROR: codex binary not found. Install from https://github.com/openai/codex" >&2
  exit 1
fi

STDERR_LOG="/tmp/codex-bridge-stderr-$$.log"
OUTPUT_FILE="/tmp/codex-bridge-output-$$.txt"

EXTRA_ARGS=""
if [ -n "${CODEX_MODEL:-}" ]; then
  EXTRA_ARGS="-m $CODEX_MODEL"
fi

timeout "$TIMEOUT" "$CODEX_BIN" exec "$PROMPT" \
  --sandbox danger-full-access \
  -C "$WORKDIR" \
  -o "$OUTPUT_FILE" \
  $EXTRA_ARGS >/dev/null 2>"$STDERR_LOG"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "BRIDGE_ERROR: exit=$EXIT_CODE stderr=$(cat "$STDERR_LOG" 2>/dev/null | head -5)" >&2
fi

if [ -f "$OUTPUT_FILE" ]; then
  cat "$OUTPUT_FILE"
  rm -f "$OUTPUT_FILE"
fi

rm -f "$STDERR_LOG"
exit $EXIT_CODE
