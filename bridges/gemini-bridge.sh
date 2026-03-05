#!/usr/bin/env bash
# Gemini CLI bridge script — invokes Gemini CLI in one-shot (headless) mode
# If the gemini-daemon is running, routes through it for ~10x faster startup.
# Falls back to direct CLI invocation otherwise.
#
# Usage:
#   ./gemini-bridge.sh "Your prompt here"
#   ./gemini-bridge.sh "Your prompt here" /path/to/workdir
#
# Environment:
#   GEMINI_MODEL       — override model (default: gemini-2.5-flash)
#   GEMINI_TIMEOUT     — timeout in seconds (default: 300)
#   GEMINI_NO_DAEMON   — set to '1' to skip daemon and use direct CLI

set -euo pipefail

PROMPT="${1:?Usage: gemini-bridge.sh \"prompt\" [workdir]}"
WORKDIR="${2:-/home/workspace}"
TIMEOUT="${GEMINI_TIMEOUT:-300}"
DEFAULT_MODEL="gemini-2.5-flash"
MODEL="${GEMINI_MODEL:-$DEFAULT_MODEL}"

DAEMON_SOCKET="/tmp/gemini-daemon.sock"

# --- Daemon path: ~1-2s per call instead of ~12s ---
if [ "${GEMINI_NO_DAEMON:-}" != "1" ] && [ -S "$DAEMON_SOCKET" ]; then
  RESPONSE=$(curl -s --unix-socket "$DAEMON_SOCKET" \
    -X POST http://localhost/prompt \
    -H 'Content-Type: application/json' \
    --max-time "$TIMEOUT" \
    -d "$(jq -n --arg p "$PROMPT" --arg m "$MODEL" --arg w "$WORKDIR" \
         '{prompt: $p, model: $m, workdir: $w}')" 2>/dev/null) || true

  if [ -n "$RESPONSE" ]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null)
    if [ -z "$ERROR" ]; then
      echo "$RESPONSE" | jq -r '.output // empty' 2>/dev/null
      exit 0
    fi
    echo "BRIDGE_WARN: daemon returned error: $ERROR, falling back to direct CLI" >&2
  fi
fi

# --- Direct CLI fallback ---
GEMINI_BIN=""
if command -v gemini &>/dev/null; then
  GEMINI_BIN="gemini"
elif [ -x "/usr/bin/gemini" ]; then
  GEMINI_BIN="/usr/bin/gemini"
elif [ -x "/usr/local/bin/gemini" ]; then
  GEMINI_BIN="/usr/local/bin/gemini"
elif [ -x "$HOME/.local/bin/gemini" ]; then
  GEMINI_BIN="$HOME/.local/bin/gemini"
else
  echo "ERROR: gemini binary not found. Install with: npm install -g @google/gemini-cli" >&2
  exit 1
fi

cd "$WORKDIR"
STDERR_LOG="/tmp/gemini-bridge-stderr-$$.log"

timeout "$TIMEOUT" "$GEMINI_BIN" -p "$PROMPT" --yolo --output-format text -m "$MODEL" --sandbox=false 2>"$STDERR_LOG"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "BRIDGE_ERROR: exit=$EXIT_CODE stderr=$(cat "$STDERR_LOG" 2>/dev/null | head -5)" >&2
fi
rm -f "$STDERR_LOG"
exit $EXIT_CODE
