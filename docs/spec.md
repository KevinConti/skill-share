# Skill Specs Overview

This directory contains documentation for the unified skill specification system and reference material for each supported AI agent platform.

## How It Works

Skill authors write shared instructions in `INSTRUCTIONS.md` (with Handlebars template support) and universal metadata in `skill.yaml`. Provider-specific metadata lives in `providers/X/metadata.yaml` subdirectories. The `skillc` compiler merges these into native skill packages for each target platform.

```
skill.yaml + INSTRUCTIONS.md + providers/X/metadata.yaml
                    │
              skillc compile
          (template rendering + merge)
                    │
    ┌───────────────┼───────────────┐
    ▼               ▼               ▼
 OpenClaw       Claude Code       Codex
 SKILL.md       SKILL.md         SKILL.md
                + scripts/       + openai.yaml
```

**Key design principles:**
- **Directory-as-declaration**: A provider is supported if `providers/X/metadata.yaml` exists. No redundant lists.
- **Content/packaging separation**: Instructions are shared; metadata and scripts can differ per provider.
- **Provider wins**: When metadata conflicts, provider-specific values override universal values.
- **Template-driven**: Handlebars syntax in INSTRUCTIONS.md for inline provider-specific sections.

See the [Unified Skill Specification](unified-skill-spec.md) for the full spec.

## Provider Reference

These documents describe each platform's native skill format — the output that `skillc` produces:

- [Claude Code Skills](skill-specs/claudecode-skills.md) — SKILL.md with flat frontmatter, subagent execution, templates
- [OpenClaw Skills](skill-specs/openclaw-skills.md) — Single SKILL.md with metadata.openclaw block, auto binary detection
- [OpenAI Codex Skills](skill-specs/openai-codex-skills.md) — .agents/skills/ structure, progressive disclosure, openai.yaml

## Provider Comparison

All three systems support the [Agent Skills](https://agentskills.io) standard but with different extensions:

| Feature | Claude Code | OpenClaw | Codex |
|---------|-------------|----------|-------|
| Directory structure | Multiple files (SKILL.md, templates, scripts) | Single SKILL.md | SKILL.md + openai.yaml |
| Subagent execution | `context: fork` | Not supported | Not supported |
| Tool restrictions | `allowed-tools` list | All tools available | Via `dependencies.tools` |
| Binary detection | Not supported | `requires.bins` | Not supported |
| Install instructions | Not supported | `metadata.openclaw.install` | Not supported |
| Progressive disclosure | Not supported | Not supported | Metadata-first loading |
| NPM distribution | `npx skills add` | Not supported | Via installer |
| Manual invocation | `/skill-name` | Automatic only | `$skill-name` |
| Templates/examples | Supported | Not supported | Via assets/ |

## Other Documents

- [Unified Skill Specification](unified-skill-spec.md) — The core spec defining the input format, templating, and compilation system
- [Quick Start Guide](quickstart.md) — Step-by-step tutorial for creating your first skill
- [Spec Validation Test Plan](../spec-validation/spec-validation.md) — Test scenarios for the `skillc` CLI
