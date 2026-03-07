#!/usr/bin/env bash
# Claude Code bridge script — invokes Claude Code CLI in one-shot mode
# Returns only the response text, suitable for scripted/orchestrator invocation
#
# MCP tool permissions are discovered dynamically from .mcp.json servers
# so new tools are automatically approved without updating this script.
#
# Usage:
#   ./claude-code-bridge.sh "Your prompt here"
#   ./claude-code-bridge.sh "Your prompt here" /path/to/workdir
#
# Environment:
#   CLAUDE_CODE_MODEL   — override model (default: uses CLI default)
#   CLAUDE_CODE_TIMEOUT — timeout in seconds (default: 600)

set -euo pipefail

PROMPT="${1:?Usage: claude-code-bridge.sh \"prompt\" [workdir]}"
WORKDIR="${2:-/home/workspace}"
TIMEOUT="${CLAUDE_CODE_TIMEOUT:-600}"

# Resolve claude binary — check PATH, then known install locations
CLAUDE_BIN="${CLAUDE_CODE_BIN:-}"
if [ -z "$CLAUDE_BIN" ]; then
  if command -v claude &>/dev/null; then
    CLAUDE_BIN="claude"
  elif [ -x "$HOME/.local/bin/claude" ]; then
    CLAUDE_BIN="$HOME/.local/bin/claude"
  elif [ -x "/root/.local/bin/claude" ]; then
    CLAUDE_BIN="/root/.local/bin/claude"
  elif [ -x "/usr/local/bin/claude" ]; then
    CLAUDE_BIN="/usr/local/bin/claude"
  else
    echo "ERROR: claude binary not found. Install with: npm install -g @anthropic-ai/claude-code" >&2
    exit 1
  fi
fi

cd "$WORKDIR"

# Unset CLAUDECODE to allow spawning from within a Claude Code session
unset CLAUDECODE

# Pre-approve built-in tools
ALLOWED_TOOLS="Write Edit Bash Read Glob Grep NotebookEdit"

# Dynamically discover MCP tool names from .mcp.json servers.
# A single Python script handles parsing, HTTP requests, and name formatting
# to avoid shell quoting issues with nested languages.
MCP_CONFIG="$WORKDIR/.mcp.json"
TOOLS_CACHE="/tmp/claude-bridge-mcp-tools-cache.txt"
CACHE_MAX_AGE=3600  # 1 hour

USE_CACHE=false
if [ -f "$TOOLS_CACHE" ]; then
  CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$TOOLS_CACHE" 2>/dev/null || echo 0) ))
  if [ "$CACHE_AGE" -lt "$CACHE_MAX_AGE" ]; then
    USE_CACHE=true
  fi
fi

if [ "$USE_CACHE" = true ]; then
  MCP_TOOLS=$(cat "$TOOLS_CACHE")
elif [ -f "$MCP_CONFIG" ]; then
  MCP_TOOLS=$(python3 - "$MCP_CONFIG" <<'PYEOF'
import json, sys, urllib.request

mcp_config_path = sys.argv[1]
try:
    with open(mcp_config_path) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(0)

tool_names = []
for srv_name, srv in cfg.get("mcpServers", {}).items():
    url = srv.get("url", "")
    if not url:
        continue
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    for k, v in srv.get("headers", {}).items():
        headers[k] = v
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}).encode()
    try:
        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        for t in data.get("result", {}).get("tools", []):
            name = t.get("name", "")
            if name:
                tool_names.append(f"mcp__{srv_name}__{name}")
    except Exception:
        pass

if tool_names:
    print(" ".join(tool_names))
PYEOF
  ) || true

  if [ -n "${MCP_TOOLS:-}" ]; then
    echo "$MCP_TOOLS" > "$TOOLS_CACHE"
  fi
fi

if [ -n "${MCP_TOOLS:-}" ]; then
  ALLOWED_TOOLS="$ALLOWED_TOOLS $MCP_TOOLS"
fi

# Log stderr for debugging; stdout is the response
STDERR_LOG="/tmp/claude-code-bridge-stderr-$$.log"

EXTRA_ARGS=""
if [ -n "${CLAUDE_CODE_MODEL:-}" ]; then
  EXTRA_ARGS="--model $CLAUDE_CODE_MODEL"
fi

timeout "$TIMEOUT" "$CLAUDE_BIN" -p "$PROMPT" --output-format text --allowedTools $ALLOWED_TOOLS $EXTRA_ARGS 2>"$STDERR_LOG"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "BRIDGE_ERROR: exit=$EXIT_CODE stderr=$(head -5 "$STDERR_LOG" 2>/dev/null)" >&2
fi
rm -f "$STDERR_LOG"
exit $EXIT_CODE
