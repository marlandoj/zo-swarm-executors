#!/usr/bin/env bash
# Claude Code bridge script — invokes Claude Code CLI in one-shot mode
# Returns only the response text, suitable for scripted/orchestrator invocation
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

# Run Claude Code in print mode (non-interactive, one-shot)
# Permissions: bypassPermissions covers built-in tools but NOT MCP tools.
# We must explicitly --allowedTools for MCP tools discovered via .mcp.json
# (--dangerously-skip-permissions is blocked when running as root)
# --output-format text: returns clean text without JSON wrapping

# Pre-approve built-in tools
ALLOWED_TOOLS="Write Edit Bash Read Glob Grep NotebookEdit"

# Pre-approve ALL Zo MCP tools — bypassPermissions does not cover MCP tools,
# so we must list them explicitly. Allow all mcp__zo__* tools since the
# orchestrator controls task dispatch and this runs in a trusted context.
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__change_hardware mcp__zo__connect_telegram"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__create_agent mcp__zo__create_or_rewrite_file"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__create_persona mcp__zo__create_rule"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__create_stripe_payment_link mcp__zo__create_stripe_price"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__create_stripe_product mcp__zo__create_website"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__delete_agent mcp__zo__delete_persona"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__delete_rule mcp__zo__delete_space_asset"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__delete_space_route mcp__zo__delete_user_service"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__edit_agent mcp__zo__edit_file mcp__zo__edit_file_llm"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__edit_image mcp__zo__edit_persona mcp__zo__edit_rule"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__find_similar_links mcp__zo__generate_d2_diagram"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__generate_image mcp__zo__generate_video"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__get_space_errors mcp__zo__get_space_route"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__grep_search mcp__zo__image_search"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__list_agents mcp__zo__list_app_tools"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__list_files mcp__zo__list_personas"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__list_rules mcp__zo__list_space_assets"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__list_space_routes mcp__zo__list_stripe_orders"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__list_stripe_payment_links mcp__zo__list_user_services"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__maps_search mcp__zo__open_webpage"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__proxy_local_service mcp__zo__read_file"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__read_webpage mcp__zo__redo_space_route"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__register_user_service mcp__zo__run_bash_command"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__run_parallel_cmds mcp__zo__run_sequential_cmds"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__save_webpage mcp__zo__send_email_to_user"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__send_sms_to_user mcp__zo__service_doctor"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__set_active_persona mcp__zo__tool_docs"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__transcribe_audio mcp__zo__transcribe_video"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__undo_space_route mcp__zo__update_space_asset"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__update_space_route mcp__zo__update_stripe_orders"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__update_stripe_payment_link mcp__zo__update_stripe_product"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__update_user_service mcp__zo__update_user_settings"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__use_app_airtable mcp__zo__use_app_gmail"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__use_app_google_calendar mcp__zo__use_app_google_drive"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__use_webpage mcp__zo__view_webpage"
ALLOWED_TOOLS="$ALLOWED_TOOLS mcp__zo__web_research mcp__zo__web_search mcp__zo__x_search"

# Log stderr for debugging; stdout is the response
STDERR_LOG="/tmp/claude-code-bridge-stderr-$$.log"

EXTRA_ARGS=""
if [ -n "${CLAUDE_CODE_MODEL:-}" ]; then
  EXTRA_ARGS="--model $CLAUDE_CODE_MODEL"
fi

timeout "$TIMEOUT" "$CLAUDE_BIN" -p "$PROMPT" --output-format text --allowedTools $ALLOWED_TOOLS $EXTRA_ARGS 2>"$STDERR_LOG"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "BRIDGE_ERROR: exit=$EXIT_CODE stderr=$(cat "$STDERR_LOG" 2>/dev/null | head -5)" >&2
fi
rm -f "$STDERR_LOG"
exit $EXIT_CODE
