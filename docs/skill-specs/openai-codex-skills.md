# OpenAI Codex Skills Configuration

## Overview

OpenAI Codex skills extend Codex with task-specific capabilities. A skill packages instructions, resources, and optional scripts so Codex can follow a workflow reliably. Skills build on the [Agent Skills](https://agentskills.io) open standard.

Skills are available in the Codex CLI, IDE extension, and Codex app.

This document describes Codex's native skill format — the output that `npx skill-universe compile` produces for the `codex` provider. For the unified input format, see the [Unified Skill Specification](../unified-skill-spec.md).

## Directory Structure

```
skill-name/
├── SKILL.md              # Required: instructions + metadata
├── scripts/              # Optional: executable code
├── references/           # Optional: documentation
├── assets/              # Optional: templates, resources
└── agents/
    └── openai.yaml      # Optional: UI metadata, invocation policy, dependencies
```

## SKILL.md Format

### Frontmatter

```yaml
---
name: skill-name
description: Explain exactly when this skill should and should not trigger
---

Skill instructions for Codex to follow.
```

### Progressive Disclosure

Codex uses progressive disclosure to manage context efficiently:
- Starts with skill's metadata (name, description, file path, optional metadata from agents/openai.yaml)
- Loads full SKILL.md instructions only when it decides to use the skill

## Skill Scope & Locations

| Scope | Location | Use Case |
|-------|----------|----------|
| REPO | $CWD/.agents/skills | Skills relevant to a specific working folder |
| REPO | $CWD/../.agents/skills | Skills in parent folder |
| REPO | $REPO_ROOT/.agents/skills | Root skills available to entire repo |
| USER | $HOME/.agents/skills | User-specific skills across repos |
| ADMIN | /etc/codex/skills | Machine/container-level skills |
| SYSTEM | Bundled with Codex | Built-in skills (e.g., skill-creator, plan skills) |

Codex scans `.agents/skills` in every directory from CWD up to repo root.

## Invocation

### Explicit Invocation
- Include skill directly in your prompt
- In CLI/IDE: run `/skills` or type `$` to mention a skill
- Use `$skill-name` syntax (e.g., `$skill-installer`)

### Implicit Invocation
- Codex chooses a skill when the task matches the skill description
- Write descriptions with clear scope and boundaries

## Creating Skills

### Using the Built-in Creator
```
$skill-creator
```
The creator asks what the skill does, when it should trigger, and whether it should include scripts.

### Manual Creation
Create a folder with SKILL.md:
```yaml
---
name: skill-name
description: Explain exactly when this skill should and should not trigger.
---

Skill instructions for Codex to follow.
```

## agents/openai.yaml

Optional configuration for UI metadata and dependencies:

```yaml
interface:
  display_name: "Optional user-facing name"
  short_description: "Optional user-facing description"
  icon_small: "./assets/small-logo.svg"
  icon_large: "./assets/large-logo.png"
  brand_color: "#3B82F6"
  default_prompt: "Optional surrounding prompt"

policy:
  allow_implicit_invocation: false  # Default: true

dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      description: "OpenAI Docs MCP server"
      transport: "streamable_http"
      url: "https://developers.openai.com/mcp"
```

## Installation

Use the built-in installer:
```
$skill-installer install owner/repo/skill-name
```

Or disable skills in config:
```toml
[[skills.config]]
path = "/path/to/skill/SKILL.md"
enabled = false
```

## Best Practices

- Keep each skill focused on one job
- Prefer instructions over scripts unless you need deterministic behavior
- Write imperative steps with explicit inputs and outputs
- Test prompts against the skill description to confirm trigger behavior

## References

- [Codex Skills Documentation](https://developers.openai.com/codex/skills)
- [Agent Skills Standard](https://agentskills.io)
- [OpenAI Skills GitHub](https://github.com/openai/skills)
- [Provider Comparison](../spec.md#provider-comparison) — Feature comparison across all providers
