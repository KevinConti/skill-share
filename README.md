# Unified Skill Specification

A specification for creating cross-platform AI agent skills. Write shared instructions once, declare provider-specific metadata separately, and compile into native skill packages for multiple platforms.

## The Problem

AI agent skill formats are platform-specific. A skill written for Claude Code won't work on OpenClaw or Codex — each has different frontmatter schemas, directory structures, and distribution methods. Developers who want to support multiple platforms must maintain separate copies.

## The Solution

Separate **content** (instructions) from **packaging** (metadata, directory layout, scripts):

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

- `skill.yaml` — Universal metadata (name, version, dependencies, config)
- `INSTRUCTIONS.md` — Shared instructions with [Handlebars](https://handlebarsjs.com) template support for inline provider-specific sections
- `providers/X/metadata.yaml` — Provider-specific metadata (only what differs)
- `providers/X/instructions.md` — Optional provider-specific instruction additions
- `providers/X/scripts/` — Optional provider-specific scripts (override shared scripts)

Provider support is declared by directory structure: if `providers/X/metadata.yaml` exists, the skill supports provider X. No redundant lists. Provider values override universal values on conflict.

## Supported Providers

| Provider | Output Format |
|----------|--------------|
| [OpenClaw](https://docs.openclaw.ai) | Single SKILL.md with `metadata.openclaw` block |
| [Claude Code](https://code.claude.com/docs/en/skills) | SKILL.md + templates/scripts directory |
| [OpenAI Codex](https://developers.openai.com/codex/skills) | `.agents/skills/` structure + `openai.yaml` |

## Documentation

| Document | Description |
|----------|-------------|
| [Unified Skill Spec](docs/unified-skill-spec.md) | Core specification — input format, templating, compilation, registry |
| [Quick Start Guide](docs/quickstart.md) | Create your first cross-platform skill |
| [Spec Overview](docs/spec.md) | Provider comparison and documentation index |
| [Claude Code Skills](docs/skill-specs/claudecode-skills.md) | Claude Code native format reference |
| [OpenClaw Skills](docs/skill-specs/openclaw-skills.md) | OpenClaw native format reference |
| [Codex Skills](docs/skill-specs/openai-codex-skills.md) | OpenAI Codex native format reference |
| [Validation Test Plan](spec-validation/spec-validation.md) | Test scenarios for the `skillc` CLI |

## Examples

See [`examples/hello-world/`](examples/hello-world/) for a complete working example.

## Status

This project is in the **specification phase**. The documents define the input format, compilation behavior, and registry operations. The `skillc` CLI implementation is not yet started.

## Related

- [Agent Skills Standard](https://agentskills.io)
- [Handlebars](https://handlebarsjs.com) — Template engine syntax reference
