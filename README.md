# zo-swarm-executors

Local executor system for the zo-swarm-orchestrator. Manages bridge scripts, health checks, and registry for AI agents running directly on the machine.

## Architecture

![Architecture diagram showing zo-swarm-orchestrator routing to zo-swarm-executors via bridge scripts](docs/images/architecture.png)

## Setup

### Prerequisites

- [Bun](https://bun.sh/) runtime (for TypeScript scripts)
- Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)
- Hermes Agent project at `/home/workspace/hermes-agent` with `.venv/`

### Install

```bash
cd /home/workspace/Skills/zo-swarm-executors
bun install
```

### Verify

```bash
# Health check all executors
bun scripts/doctor.ts

# Integration test
bun scripts/test-harness.ts
```

## Usage

### Doctor (Health Checks)

```bash
bun scripts/doctor.ts                    # All executors
bun scripts/doctor.ts --executor hermes  # Specific executor
bun scripts/doctor.ts --json             # JSON output
```

Checks: bridge exists, bridge executable, health command passes, required env vars set.

### Test Harness

```bash
bun scripts/test-harness.ts                    # All executors
bun scripts/test-harness.ts --executor hermes  # Specific executor
bun scripts/test-harness.ts --timeout 180      # Custom timeout
```

Sends a test prompt through each bridge and validates the response contains `BRIDGE_OK`.

### Registry Management

```bash
bun scripts/register.ts list       # List executors
bun scripts/register.ts validate   # Validate schema
bun scripts/register.ts add <file> # Add executor from JSON
bun scripts/register.ts remove <id> # Remove executor
```

## Adding a Custom Executor

1. **Create a bridge script:**
   ```bash
   cp bridges/template-bridge.sh bridges/my-agent-bridge.sh
   # Edit to invoke your agent CLI
   chmod +x bridges/my-agent-bridge.sh
   ```

2. **Create executor metadata** (`my-agent.json`):
   ```json
   {
     "id": "my-agent",
     "name": "My Agent",
     "executor": "local",
     "bridge": "Skills/zo-swarm-executors/bridges/my-agent-bridge.sh",
     "description": "Description of what this agent does",
     "expertise": ["research", "analysis"],
     "best_for": ["Research tasks", "Data analysis"],
     "config": {
       "defaultTimeout": 300,
       "model": null,
       "envVars": {}
     },
     "healthCheck": {
       "command": "command -v my-agent",
       "expectedPattern": "my-agent",
       "description": "Verify my-agent is installed"
     }
   }
   ```

3. **Register and verify:**
   ```bash
   bun scripts/register.ts add my-agent.json
   bun scripts/doctor.ts --executor my-agent
   bun scripts/test-harness.ts --executor my-agent
   ```

## Bridge Protocol

Bridges follow a simple contract:

- **Input:** `$1` = prompt text, `$2` = workdir (optional)
- **Output:** `stdout` = clean text response, `stderr` = diagnostics
- **Exit:** `0` = success, non-zero = failure
- **Shell:** `#!/usr/bin/env bash`, `set -euo pipefail`, must be `chmod +x`

See [docs/BRIDGE_PROTOCOL.md](docs/BRIDGE_PROTOCOL.md) for the full specification.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SWARM_WORKSPACE` | `/home/workspace` | Workspace root |
| `SWARM_EXECUTOR_REGISTRY` | Auto-detected | Registry JSON path |
| `CLAUDE_CODE_BIN` | Auto-detected | Claude Code binary |
| `CLAUDE_CODE_MODEL` | CLI default | Override model |
| `CLAUDE_CODE_TIMEOUT` | `600` | Timeout (seconds) |
| `HERMES_PROJECT_DIR` | `/home/workspace/hermes-agent` | Hermes project path |
| `HERMES_VENV` | `$HERMES_PROJECT_DIR/.venv/bin/activate` | Hermes venv |

## Related

- [zo-swarm-orchestrator](../zo-swarm-orchestrator/) — The orchestration engine that consumes this registry
- [docs/BRIDGE_PROTOCOL.md](docs/BRIDGE_PROTOCOL.md) — Bridge contract specification
- [docs/identities/](docs/identities/) — Reference persona identity files
