# skill-universe

[![npm version](https://img.shields.io/npm/v/skill-universe)](https://www.npmjs.com/package/skill-universe)

A cross-platform AI agent skill compiler. Write shared instructions once, declare provider-specific metadata separately, and compile into native skill packages for multiple platforms.

## The Problem

AI agent skill formats are platform-specific. A skill written for Claude Code won't work on OpenClaw or Codex — each has different frontmatter schemas, directory structures, and distribution methods. Developers who want to support multiple platforms must maintain separate copies.

## The Solution

Separate **content** (instructions) from **packaging** (metadata, directory layout, scripts):

```
skill.yaml + INSTRUCTIONS.md + providers/X/metadata.yaml
                    │
            skill-universe compile
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

## Installation

```bash
npm install -g skill-universe
```

## Quick Usage

```bash
# Create a new skill
skill-universe init my-skill

# Check provider support
skill-universe check my-skill

# Compile for all providers
skill-universe compile my-skill

# Compile for a single provider
skill-universe compile my-skill --target claude-code
```

## CLI

```
skill-universe compile <skill-dir>                          Compile all providers
skill-universe compile <skill-dir> --target <provider>      Compile single provider
skill-universe compile <skill-dir> --providers <list>       Compile selected providers
skill-universe compile <skill-dir> --output <dir>           Compile with custom output
skill-universe check <skill-dir>                            Check supported providers
skill-universe init <skill-dir>                             Create a new skill
skill-universe import <source>                              Import a provider-specific skill
skill-universe import <source> --provider <provider>        Import with explicit provider
skill-universe import <source> --output <dir>               Import to custom output dir
skill-universe publish <skill-dir>                          Publish to GitHub Releases
skill-universe publish <skill-dir> --repo <owner/repo>     Publish to specific repo
skill-universe search <query>                               Search for skills
skill-universe install <owner/repo>                         Install a skill
skill-universe install <owner/repo> --target <provider>    Install for specific provider
skill-universe list <owner/repo>                            List available versions
skill-universe list --installed                             List installed skills
skill-universe version                                      Show version
skill-universe help                                         Show help
```

## Documentation

| Document | Description |
|----------|-------------|
| [Unified Skill Spec](https://github.com/KevinConti/skill-share/blob/master/docs/unified-skill-spec.md) | Core specification — input format, templating, compilation, registry |
| [Quick Start Guide](https://github.com/KevinConti/skill-share/blob/master/docs/quickstart.md) | Create your first cross-platform skill |
| [Spec Overview](https://github.com/KevinConti/skill-share/blob/master/docs/spec.md) | Provider comparison and documentation index |
| [Claude Code Skills](https://github.com/KevinConti/skill-share/blob/master/docs/skill-specs/claudecode-skills.md) | Claude Code native format reference |
| [OpenClaw Skills](https://github.com/KevinConti/skill-share/blob/master/docs/skill-specs/openclaw-skills.md) | OpenClaw native format reference |
| [Codex Skills](https://github.com/KevinConti/skill-share/blob/master/docs/skill-specs/openai-codex-skills.md) | OpenAI Codex native format reference |

## Examples

See [`examples/hello-world/`](https://github.com/KevinConti/skill-share/tree/master/examples/hello-world) for a complete working example.

## Related

- [Agent Skills Standard](https://agentskills.io)
- [Handlebars](https://handlebarsjs.com) — Template engine syntax reference

## License

ISC
