# OpenClaw Skills Configuration

## Overview

OpenClaw skills provide specialized instructions for specific tasks. They are auto-discovered from `~/development/openclaw/skills/`.

This document describes OpenClaw's native SKILL.md format — the output that `skillc compile` produces for the `openclaw` provider. For the unified input format, see the [Unified Skill Specification](../unified-skill-spec.md).

## Directory Structure

```
skill-name/
└── SKILL.md    # Required - instructions + metadata
```

Unlike Claude Code, OpenClaw does not support subdirectories with templates, examples, or scripts.

## SKILL.md Format

### Metadata Block

OpenClaw uses a YAML metadata block with custom `metadata.openclaw` field:

```yaml
---
name: skill-name
description: What the skill does and when to use it
metadata:
  {
    "openclaw":
      {
        "emoji": "📧",
        "requires": { "bins": ["python3", "curl"] },
        "install":
          [
            {
              "id": "brew",
              "kind": "brew",
              "formula": "fastmail-cli",
              "bins": ["fastmail"],
              "label": "Install Fastmail CLI (brew)"
            },
            {
              "id": "pip",
              "kind": "pip",
              "package": "fastmail-cli",
              "bins": ["fastmail"],
              "label": "Install Fastmail CLI (pip)"
            }
          ]
      }
  }
---

# Skill instructions here...
```

### Metadata Fields

- **emoji**: Icon displayed with the skill
- **requires.bins**: List of required binary executables
- **install**: Array of installation instructions with:
  - **id**: Unique identifier
  - **kind**: Package manager (brew, apt, pip, npm, cargo, etc.)
  - **formula** / **package**: Package name
  - **bins**: List of executables provided
  - **label**: Human-readable description

### Installation Kinds

Supported package managers:
- `brew` - Homebrew
- `apt` - Debian/Ubuntu apt
- `pip` - Python pip
- `npm` - Node.js npm
- `cargo` - Rust cargo
- `go` - Go get
- `custom` - Custom installation commands

## How Skills Work

1. When a task matches a skill's description, OpenClaw automatically loads it
2. Skills run inline with the main context (no subagent support)
3. All tools are available - no restricted tool list

## Invocation

Skills are invoked automatically when relevant to the task. There is no manual `/skill-name` command syntax like Claude Code.

## Dual Compatibility

To create a skill that works with both OpenClaw and Claude Code natively (without using the unified compilation system), use both frontmatter formats:

```yaml
---
name: fastmail
description: Read email via Fastmail JMAP API

# Claude Code
disable-model-invocation: true

# OpenClaw
metadata:
  {
    "openclaw":
      {
        "emoji": "📧",
        "requires": { "bins": ["python3"] }
      }
  }
---

# Skill instructions...
```

Note: Features like `context: fork` and `allowed-tools` will only work in Claude Code.

## Examples

See existing skills:
- `/home/ubuntu/development/openclaw/skills/github/SKILL.md`
- `/home/ubuntu/development/openclaw/skills/gog/SKILL.md`
- `/home/ubuntu/development/openclaw/skills/weather/SKILL.md`

## References

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw Community](https://discord.com/invite/clawd)
- [Provider Comparison](../spec.md#provider-comparison) — Feature comparison across all providers
