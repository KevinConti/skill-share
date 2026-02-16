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
         npx skill-universe compile
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

## Quick Usage

```bash
# Create a new skill
npx skill-universe init my-skill

# Check provider support
npx skill-universe check my-skill

# Compile for all providers
npx skill-universe compile my-skill

# Compile for a single provider
npx skill-universe compile my-skill --target claude-code
```

## CLI

```
npx skill-universe compile <skill-dir>                          Compile all providers
npx skill-universe compile <skill-dir> --target <provider>      Compile single provider
npx skill-universe compile <skill-dir> --providers <list>       Compile selected providers
npx skill-universe compile <skill-dir> --output <dir>           Compile with custom output
npx skill-universe check <skill-dir>                            Check supported providers
npx skill-universe init <skill-dir>                             Create a new skill
npx skill-universe import <source>                              Import a provider-specific skill
npx skill-universe import <source> --provider <provider>        Import with explicit provider
npx skill-universe import <source> --output <dir>               Import to custom output dir
npx skill-universe publish <skill-dir>                          Publish to GitHub Releases
npx skill-universe publish <skill-dir> --repo <owner/repo>     Publish to specific repo
npx skill-universe search <query>                               Search for skills
npx skill-universe install <owner/repo>                         Install a skill
npx skill-universe install <owner/repo> --target <provider>    Install for specific provider
npx skill-universe list <owner/repo>                            List available versions
npx skill-universe list --installed                             List installed skills
npx skill-universe version                                      Show version
npx skill-universe help                                         Show help
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

## How is this different from `skills`?

The [`skills`](https://www.npmjs.com/package/skills) CLI (from Vercel) is a package manager that distributes plain Markdown files to agent-specific directories. `skill-universe` is a compiler — it transforms a single source into structurally different output per provider. They solve different problems: distribution vs. adaptation.

| | `skill-universe` | `skills` (Vercel) |
|---|---|---|
| **What it is** | Compiler / build tool | Package manager / installer |
| **Core idea** | Write once, compile to native formats | Distribute plain Markdown to directory paths |
| **Content adaptation** | Handlebars templates, provider blocks, metadata merging | None — identical file copied to every agent |
| **Provider-specific metadata** | `allowed-tools`, `context`, `model`, `emoji`, `requires.bins`, per-provider scripts | `name` and `description` only |
| **Configuration** | Schema-defined config fields, env var mapping, `.env` generation | None |
| **Dependencies** | Semver constraints (`^1.0.0`, `~1.1.0`) with circular detection | None |
| **Agent coverage** | 3 providers with structurally different output each | 30+ agents, same file in different directories |
| **Distribution** | GitHub Releases with versioned tarballs | Git repos cloned via CLI |
| **Build step required** | Yes | No |

No agent strictly *requires* provider-specific metadata — a plain SKILL.md with just `name`, `description`, and instructions will load everywhere. That's why `skills` works: the minimum bar is low. But without metadata, skills lose access to features like tool restrictions (`allowed-tools`), subagent execution (`context: fork`), binary dependency checks (`requires.bins`), UI branding, and MCP server declarations. `skill-universe` produces output that takes full advantage of each provider's native capabilities, rather than settling for the lowest common denominator.

## Roadmap

- **Expand provider coverage** — Add providers beyond OpenClaw, Claude Code, and Codex (e.g., Cursor, Windsurf, Gemini CLI). Each new provider gets genuinely adapted output, not just another directory path.
- **Compile-and-install** — After compilation, automatically install each provider's output into the correct local agent directory (e.g., `.claude/skills/`, `.cursor/skills/`), removing the manual copy step.
- **Interactive skill discovery** — Add a browsable `find` command with interactive selection, similar to `npx skills find`.
- **Update detection** — `check --updates` and `update` commands to notify when installed skills have newer versions available.
- **GitLab and arbitrary git URL support** — Extend publishing and installation beyond GitHub-only sources.
- **CI/CD mode** — `--yes` and `--all` flags for non-interactive compilation and batch operations in pipelines.
- **Agent auto-detection** — Detect locally installed agents and compile/install only for those providers automatically.
- **Global installation scope** — `-g` flag for user-level skill installation alongside project-scoped installs.

## Related

- [Agent Skills Standard](https://agentskills.io)
- [Handlebars](https://handlebarsjs.com) — Template engine syntax reference

## License

ISC
