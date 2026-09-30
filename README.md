# Agent Beacon Handoff Helper

A user-friendly Bash helper for setting up and using [Agent Beacon](https://github.com/Asymptote-Labs/agent-beacon) for **cross-agent development handoffs**.
The project was initially discovered through the
[Agent Beacon CI Telemetry GitHub Action](https://github.com/marketplace/actions/agent-beacon-ci-telemetry).

The goal is simple:

> Start work in one AI coding agent, continue in another, and carry the useful project context with you.

For example:

```text
Codex Desktop
      ↓
Agent Beacon
      ↓
Project Memory
      ↓
Antigravity
      ↓
Continue working
      ↓
Promote progress
      ↓
Codex / another agent
```

> **Unofficial project:** This repository is an independent helper for Agent Beacon. It is not developed, maintained, or officially supported by Asymptote Labs.

---

## Why This Exists

AI coding tools are useful, but switching between them can be painful.

You may:

- reach a token or usage limit in one agent
- switch from Codex to Antigravity
- move from Claude Code to another coding agent
- want another agent to understand previous investigation and decisions
- want reusable project knowledge instead of repeatedly copying entire conversations

Agent Beacon provides telemetry and memory capabilities that can help with this.

This helper wraps the common setup, diagnostics, configuration, and handoff workflow into a safer interactive menu.

---

## Quick Start

Run directly from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/NitinUbhadiya/agent-beacon-handoff-helper/main/beacon-handoff.sh)
```

No manual download is required.

### Prefer to inspect the script first?

For security-sensitive or company environments, review the script before executing it:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/NitinUbhadiya/agent-beacon-handoff-helper/main/beacon-handoff.sh \
  -o beacon-handoff.sh

less beacon-handoff.sh

chmod +x beacon-handoff.sh
./beacon-handoff.sh
```

Running remote shell code always requires trusting the source repository.

---

## Main Menu

The helper provides four main areas:

```text
1) Project setup — install Beacon memory skills
2) AI app / agent / CLI / Desktop setup
3) Handoff prompts & diagnostics
4) One-time Beacon installation / endpoint setup
0) Exit
```

The installation option is intentionally last because Beacon normally only needs to be installed once per machine.

---

## 1. Project Setup

Installs Beacon's project memory skills:

```text
beacon-memory-recall
beacon-memory-distill
beacon-memory-promote
```

into:

```text
<project>/.agents/skills/
```

Use this option for each repository where you want cross-agent memory.

The helper detects existing installations and avoids unnecessary reinstallation.

Project paths can be entered as either:

```text
/Users/example/projects/my-project
```

or:

```text
~/projects/my-project
```

---

## 2. AI Agent Setup

The helper currently includes dedicated flows for:

### Codex Desktop / Codex CLI

Configures Codex OTLP telemetry to use the local Beacon collector:

```text
http://127.0.0.1:4317
```

The helper safely handles:

- existing `~/.codex/config.toml`
- existing `[otel]` sections
- malformed configuration
- duplicate OTel sections
- timestamped backups
- temporary-file writes
- TOML validation
- atomic replacement
- raw prompt capture settings

### Raw prompt privacy

Raw Codex prompt capture is **opt-in**.

The helper defaults:

```toml
log_user_prompt = false
```

unless the user explicitly enables it.

It can also safely toggle this setting later.

---

## Antigravity

### Antigravity CLI

Beacon can configure supported hooks using:

```bash
beacon endpoint repair
```

The helper clearly warns before running repair because the command may reconcile more than agent hooks, including service and telemetry configuration.

### Antigravity IDE / Desktop

Automatic Beacon telemetry capture for the Antigravity IDE/Desktop should not currently be assumed.

The tested workflow is therefore:

```text
Codex
  ↓
Beacon captures Codex work
  ↓
Antigravity recalls Beacon memory
  ↓
Work continues in Antigravity
  ↓
Antigravity promotes important progress
  ↓
Codex recalls promoted project memory
```

This allows cross-agent handoff even when the IDE itself is not automatically captured.

---

## 3. Handoff Prompts

The helper includes ready-to-copy prompts.

On macOS, prompts can automatically be copied to the clipboard.

### Recall Previous Agent Work

Use when entering a project from another AI agent:

```text
Use the beacon-memory-recall skill to recall my recent work for this project.

Summarize:
- what I was trying to do
- what files/commands/tools were used
- what was already completed
- current problem/status
- what should be done next

Do not make changes yet.
```

---

### Promote Current Work

Use before leaving an agent when its session is not automatically captured:

```text
Use beacon-memory-promote to save the important progress, decisions, current status, and next steps from this session so another agent can continue later.
```

---

### Distill Durable Knowledge

Use when useful findings should become longer-lived project knowledge:

```text
Use beacon-memory-distill to review the useful work from this project/session and prepare durable project knowledge. Do not promote low-value or temporary details.
```

---

### Continue After Recall

After another agent successfully recalls the previous context:

```text
Continue from the Beacon-recalled context.

Proceed with the next pending step, but inspect and explain before making any code changes.
```

---

## Diagnostics

The helper provides shortcuts for:

### Endpoint Status

```bash
beacon endpoint status
```

Useful for checking:

- Beacon service status
- telemetry collector status
- detected agents
- enabled/disabled harnesses
- forwarding configuration
- local log location

---

### Terminal Trace Browser

```bash
beacon traces
```

Lets you inspect captured agent sessions, prompts, tool calls, commands, and related telemetry.

---

### Local Dashboard

```bash
beacon endpoint dashboard
```

Typically opens:

```text
http://127.0.0.1:8765/
```

for browser-based inspection of local activity.

---

## Privacy

This project intentionally uses conservative privacy defaults.

### Beacon Destination

During Beacon's interactive installation, **Beacon Managed/Cloud may be preselected**.

If your telemetry must remain on your machine, explicitly choose:

```text
Local only
```

The helper warns about this before launching endpoint setup.

### Local Beacon does not automatically mean local-only forwarding

Codex may send telemetry to:

```text
127.0.0.1:4317
```

while Beacon itself may still have another forwarding destination configured.

Always verify with:

```bash
beacon endpoint status
```

when company or project policy requires strictly local telemetry.

### Raw prompts

Raw Codex prompts may contain:

- source code
- project details
- customer information
- URLs
- commands
- credentials accidentally included in prompts
- other sensitive information

For this reason, raw prompt capture defaults to **disabled** in this helper.

---

## Supported Systems

### macOS

Designed and tested on Apple Silicon macOS, including M-series Macs.

The helper includes PATH handling for common Homebrew locations such as:

```text
/opt/homebrew/bin
/usr/local/bin
```

### Linux

Automatic installation is limited to the Linux distribution families supported by the upstream Beacon installer flow, including:

```text
Debian / Ubuntu
Fedora
RHEL
Rocky Linux
AlmaLinux
```

Common `x86_64` and ARM64 architectures are handled.

Other Linux distributions may still work with a manually installed Beacon CLI, but are not automatically installed by this helper.

---

## Dependencies

Depending on the selected operation, the helper may use:

```text
bash
curl
Beacon CLI
Node.js / npx
Python 3
Homebrew (macOS installation)
```

The script checks required commands before attempting operations where possible.

---

## Example Cross-Agent Workflow

A practical workflow may look like:

```text
1. Work in Codex Desktop

2. Beacon automatically captures the Codex session

3. Codex limit is reached

4. Open the same repository in Antigravity

5. Use:
   beacon-memory-recall

6. Antigravity receives the previous goal, findings,
   files, commands, status, and next steps

7. Continue development in Antigravity

8. Before leaving Antigravity use:
   beacon-memory-promote

9. Return to Codex

10. Use beacon-memory-recall

11. Continue from the Antigravity progress
```

This avoids manually copying long conversations between agents.

---

## Safe Configuration Changes

When changing Codex configuration, the helper is designed to avoid destructive writes.

It uses a flow similar to:

```text
Inspect existing config
        ↓
Validate state
        ↓
Create backup
        ↓
Create temporary file
        ↓
Validate TOML
        ↓
Atomic replacement
```

Existing custom `[otel]` configurations are not blindly overwritten.

---

## Project Memory vs Telemetry

These are related but different concepts.

### Telemetry

Captures activity such as:

```text
prompts
tool calls
commands
agent events
session activity
```

### Project Memory

Stores useful distilled/promoted knowledge that another compatible agent can reuse.

For a reliable handoff workflow, you may use both.

---

## Current Version

```text
Beacon Handoff Helper v0.3.1
```

The script has been tested for:

- repeat execution / idempotency
- existing Beacon installations
- existing Codex OTel configuration
- malformed OTel configuration
- project paths containing spaces
- `~/...` paths
- partial Beacon skill installations
- EOF handling
- Ctrl+C behavior
- privacy-safe defaults
- Apple Silicon PATH handling

---

## Security Notes

This helper executes commands and modifies configuration files related to local AI development tools.

Before using it in a company environment:

- review the script
- understand Beacon's telemetry behavior
- verify your organization's data policy
- prefer `Local only` unless remote forwarding is explicitly approved
- avoid enabling raw prompt capture unless needed
- review project Agent Skills before allowing agents to execute them

No script can guarantee that third-party tools or future versions of dependencies retain the same behavior.

---

## Credits

This project is built around:

**Agent Beacon**  
Developed by **Asymptote Labs**

https://github.com/Asymptote-Labs/agent-beacon

Agent Beacon provides the underlying telemetry, trace, endpoint, and memory capabilities.

This repository only provides an independent helper layer for:

```text
installation
configuration
privacy-safe defaults
diagnostics
project skills
cross-agent handoff workflows
```

Thank you to the Agent Beacon / Asymptote Labs team for making the underlying project available.

---

## Disclaimer

This repository is an **unofficial independent project**.

It is not affiliated with, endorsed by, sponsored by, or maintained by Asymptote Labs.

Agent Beacon, its commands, installation behavior, APIs, configuration formats, and supported agents may change over time. Always refer to the official Agent Beacon documentation when troubleshooting upstream behavior.

---

## Contributing

Issues and pull requests are welcome.

Useful contributions include:

- additional agent integrations
- Linux distribution testing
- shell portability improvements
- safer configuration handling
- improved diagnostics
- documentation improvements
- additional cross-agent handoff workflows

When reporting a problem, include:

```text
Operating system
Beacon version
Agent being configured
Relevant helper menu option
Error/output
```

Please remove credentials, customer information, prompts, or other sensitive data before posting logs publicly.
