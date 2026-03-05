# CLI Agents as Personas on Zo Computer

Turn any CLI tool into a first-class AI persona with consistent identity, shared memory, and optional swarm orchestration.

## The Idea

Zo Computer treats external CLI tools (Claude Code, Hermes, Gemini, Codex) as **personas** — the same abstraction used for its native API-based agents. A thin bash "bridge script" is the only integration surface. Whether you call one agent directly or coordinate a swarm of twelve, the pattern is the same.

## Architecture

### Three-Layer Identity

Every persona — CLI or API — draws from three layers:

| Layer | File | Purpose |
| --- | --- | --- |
| Constitution |  | Shared principles (safety, tool discipline, communication style) |
| Role |  | Domain expertise, tone, responsibilities |
| Memory |  | Runtime facts, decisions, active context |

### Bridge Scripts

A bridge script wraps a CLI tool with a standard contract:

```markdown
Input:  bash bridge.sh "prompt" [workdir]
Output: plain text on stdout
Errors: stderr + non-zero exit code
```

Each bridge handles binary resolution, timeout enforcement, output cleanup, and environment configuration. The orchestrator (or any caller) doesn't need to know *how* the CLI works — just that it accepts a prompt and returns text.

**Available bridges:**

| Bridge | CLI Tool | Invocation | Speed |
| --- | --- | --- | --- |
|  | Claude Code | `claude -p "..." --output-format text` | \~25-120s |
|  | Hermes Agent | `python cli.py -q "..."` | \~15-60s |
|  | Gemini CLI | `gemini -p "..." --yolo --output-format text` | \~2-12s (daemon) |
|  | Codex CLI | `codex exec "..."` | \~3s |

---

## Integration Mode 1: Direct (No Orchestrator)

Call a bridge script directly. No registry, no DAG, no dependencies.

### Basic Usage

```bash
# Ask Claude Code to review a file
bash Skills/zo-swarm-executors/bridges/claude-code-bridge.sh \
  "Review src/auth.ts for security issues"

# Ask Hermes to research something
bash Skills/zo-swarm-executors/bridges/hermes-bridge.sh \
  "Find the top 5 competitors to Acme Corp and summarize their pricing"

# Fast code generation with Codex
bash Skills/zo-swarm-executors/bridges/codex-bridge.sh \
  "Create a rate-limiting middleware for Express.js"
```

### With Identity Context

Inject the persona layers yourself:

```bash
SOUL=$(cat SOUL.md)
IDENTITY=$(cat IDENTITY/security-engineer.md)

bash Skills/zo-swarm-executors/bridges/claude-code-bridge.sh \
  "You are operating under these principles:
$SOUL

Your role:
$IDENTITY

Task: Audit the authentication flow in src/auth/ for OWASP Top 10 vulnerabilities."
```

### From a Zo Agent (Scheduled)

Create a scheduled agent that runs a bridge on a cron:

```bash
# Weekly security scan via Claude Code
bash Skills/zo-swarm-executors/bridges/claude-code-bridge.sh \
  "Run a security review of all files in src/. Focus on injection, auth bypass, and secrets exposure. Save results to /home/workspace/Reports/security-scan-$(date +%F).md"
```

### From a zo.space API Route

Expose a bridge as an HTTP endpoint:

```typescript
import type { Context } from "hono";
import { $ } from "bun";

export default async (c: Context) => {
  const { prompt } = await c.req.json();
  const result = await $`bash /home/workspace/Skills/zo-swarm-executors/bridges/claude-code-bridge.sh ${prompt}`.text();
  return c.json({ result });
};
```

### Environment Variables

| Variable | Bridge | Default |
| --- | --- | --- |
| `CLAUDE_CODE_MODEL` | claude-code | CLI default (Opus 4.6) |
| `CLAUDE_CODE_TIMEOUT` | claude-code | 600s |
| `HERMES_PROJECT_DIR` | hermes | `/home/workspace/hermes-agent` |
| `GEMINI_MODEL` | gemini | `gemini-2.5-flash` |
| `GEMINI_NO_DAEMON` | gemini | `0` (daemon enabled) |
| `CODEX_MODEL` | codex | `gpt-5.2-codex` |

---

## Integration Mode 2: Swarm Orchestration

The orchestrator coordinates multiple personas across a dependency graph, routing each task to the right executor.

### How It Works

1. **Load persona registry** — Maps persona IDs to capabilities and executor type
2. **Build DAG** — Tasks declare dependencies (`dependsOn: ["task-1"]`)
3. **Route** — `executor === "local"` → bridge script; otherwise → Zo `/zo/ask` API
4. **Execute** — DAG streaming launches tasks the moment their dependencies resolve
5. **Pass context** — Output from completed tasks is injected into dependent prompts
6. **Collect** — Results aggregated with timing, retries, success/failure status

### Persona Registry

```json
{
  "personas": [
    {
      "id": "claude-code",
      "name": "Claude Code",
      "expertise": ["code-generation", "debugging", "architecture"],
      "best_for": ["Complex multi-file code changes", "Codebase-aware analysis"],
      "executor": "local",
      "bridge": "Skills/zo-swarm-executors/bridges/claude-code-bridge.sh"
    },
    {
      "id": "research-analyst",
      "name": "Research Analyst",
      "expertise": ["data gathering", "synthesis", "trend analysis"],
      "best_for": ["competitive analysis", "deep research"]
    }
  ]
}
```

- `executor: "local"` **+** `bridge` → routed to CLI via bridge script
- **No executor field** → routed to Zo API (`/zo/ask`)

### Task Definition

```json
[
  {
    "id": "plan",
    "persona": "product-manager",
    "prompt": "Create a review plan for the e-commerce site at example.com",
    "dependsOn": []
  },
  {
    "id": "security-audit",
    "persona": "claude-code",
    "prompt": "Audit the codebase for security vulnerabilities based on the plan: {{plan.output}}",
    "dependsOn": ["plan"]
  },
  {
    "id": "ux-review",
    "persona": "frontend-developer",
    "prompt": "Review the site's UX and accessibility based on the plan: {{plan.output}}",
    "dependsOn": ["plan"]
  },
  {
    "id": "synthesis",
    "persona": "technical-writer",
    "prompt": "Synthesize all findings into a final report: {{security-audit.output}} {{ux-review.output}}",
    "dependsOn": ["security-audit", "ux-review"]
  }
]
```

### DAG Execution Modes

**Streaming (default)** — Tasks launch immediately when dependencies resolve. Uses `Promise.race` to detect completions and schedule newly-ready tasks without waiting for an entire wave.

**Waves (legacy)** — Tasks grouped into waves; all tasks in a wave must complete before the next wave starts.

### Split Concurrency

The orchestrator maintains separate concurrency pools:

```markdown
Zo API pool:     maxConcurrency (default: 3)
Local CLI pool:  localConcurrency (default: 4)
─────────────────────────────────────────────
Effective total: 7 parallel tasks
```

This prevents slow API calls from blocking fast local executors and vice versa.

### Running the Orchestrator

```bash
cd Skills/zo-swarm-orchestrator

# Basic execution
bun scripts/orchestrate-v4.ts --tasks tasks/my-review.json

# With streaming DAG (default)
bun scripts/orchestrate-v4.ts --tasks tasks/my-review.json --dag-mode=streaming

# With legacy wave execution
bun scripts/orchestrate-v4.ts --tasks tasks/my-review.json --dag-mode=waves
```

### Resilience Features

| Feature | Behavior |
| --- | --- |
| Retry with backoff | 3 retries with exponential delay |
| Circuit breaker | Per-persona; opens after 2 consecutive failures |
| Dependency failure propagation | Downstream tasks auto-skip if upstream fails |
| Deadlock detection | Detects unresolvable dependency cycles |
| Timeout enforcement | Per-bridge configurable (default 300-600s) |

---

## Shared Memory

All personas — CLI and API — read and write to a shared SQLite database with hybrid search:

```bash
# Store a fact
bun .zo/memory/scripts/memory-next.ts store \
  --entity "claude-code" --key "pattern" \
  --value "Prefer Edit tool over sed for code changes"

# Semantic + keyword search
bun .zo/memory/scripts/memory-next.ts hybrid "code editing best practices"
```

The orchestrator pre-warms relevant memory before each task and stores results back after completion. This gives every persona access to the collective knowledge of the swarm.

---

## Writing Your Own Bridge

Use `file template-bridge.sh` as a starting point:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROMPT="${1:?Usage: my-bridge.sh \"prompt\" [workdir]}"
WORKDIR="${2:-/home/workspace}"
TIMEOUT="${MY_TOOL_TIMEOUT:-300}"

cd "$WORKDIR"

# Your CLI invocation here
timeout "$TIMEOUT" my-tool --prompt "$PROMPT" 2>/dev/null
```

Then register in `file executor-registry.json`:

```json
{
  "id": "my-tool",
  "name": "My Tool",
  "executor": "local",
  "bridge": "Skills/zo-swarm-executors/bridges/my-bridge.sh",
  "expertise": ["my-domain"],
  "best_for": ["tasks my tool excels at"],
  "healthCheck": {
    "command": "command -v my-tool",
    "expectedPattern": "my-tool"
  }
}
```

---

## File Structure

```markdown
Skills/zo-swarm-executors/
├── bridges/                    # Bridge scripts (the core interface)
│   ├── claude-code-bridge.sh
│   ├── hermes-bridge.sh
│   ├── gemini-bridge.sh
│   ├── codex-bridge.sh
│   └── template-bridge.sh
├── registry/
│   └── executor-registry.json  # Detailed executor metadata
├── scripts/                    # Management tools
│   ├── doctor.ts               # Health checker
│   └── test-harness.ts         # Integration tester
├── types/                      # TypeScript interfaces
└── docs/                       # Protocol documentation

Skills/zo-swarm-orchestrator/
├── scripts/
│   └── orchestrate-v4.ts       # Main orchestrator
├── assets/
│   └── persona-registry.json   # Persona → executor routing
├── config.json                 # Concurrency, timeouts, token limits
└── tasks/                      # Task definition files
```

---

## License

MIT