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

## Getting Started

### Prerequisites

- [Gleam](https://gleam.run) >= 1.14.0
- [Node.js](https://nodejs.org) (for the JavaScript build target)

### Build

```bash
cd skillc && gleam build
```

### Quick Usage

```bash
# Create a new skill
skillc init my-skill

# Check provider support
skillc check my-skill

# Compile for all providers
skillc compile my-skill

# Compile for a single provider
skillc compile my-skill --target claude-code
```

## CLI

```
skillc compile <skill-dir>                          Compile all providers
skillc compile <skill-dir> --target <provider>      Compile single provider
skillc compile <skill-dir> --providers <list>       Compile selected providers
skillc compile <skill-dir> --output <dir>           Compile with custom output
skillc check <skill-dir>                            Check supported providers
skillc init <skill-dir>                             Create a new skill
skillc import <source>                              Import a provider-specific skill
skillc import <source> --provider <provider>        Import with explicit provider
skillc import <source> --output <dir>               Import to custom output dir
skillc publish <skill-dir>                          Publish to GitHub Releases
skillc publish <skill-dir> --repo <owner/repo>     Publish to specific repo
skillc search <query>                               Search for skills
skillc install <owner/repo>                         Install a skill
skillc install <owner/repo> --target <provider>    Install for specific provider
skillc list <owner/repo>                            List available versions
skillc list --installed                             List installed skills
skillc version                                      Show version
skillc help                                         Show help
```

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

For simple text-only skills that need no metadata differences across agents, `skills` is lighter-weight and has broader agent coverage. For skills that need provider-specific metadata, scripts, configuration, or conditional content, `skill-universe` produces genuinely native output rather than one-size-fits-all copies. The two can work together — compile with `skill-universe`, distribute the output with `skills`.

## Roadmap

- **Expand provider coverage** — Add providers beyond OpenClaw, Claude Code, and Codex (e.g., Cursor, Windsurf, Gemini CLI). Each new provider gets genuinely adapted output, not just another directory path.
- **`skills` CLI compatibility** — Compile output that is directly installable via `npx skills add`, bridging the two ecosystems so authors compile with `skillc` and distribute through the `skills` registry.
- **Interactive skill discovery** — Add a browsable `skillc find` command with interactive selection, similar to `npx skills find`.
- **Update detection** — `skillc check --updates` and `skillc update` commands to notify when installed skills have newer versions available.
- **GitLab and arbitrary git URL support** — Extend publishing and installation beyond GitHub-only sources.
- **CI/CD mode** — `--yes` and `--all` flags for non-interactive compilation and batch operations in pipelines.
- **Agent auto-detection** — Detect locally installed agents and compile/install only for those providers automatically.
- **Global installation scope** — `-g` flag for user-level skill installation alongside project-scoped installs.

## Status

The `skillc` CLI v1.0.0 is implemented in [Gleam](https://gleam.run) with compilation, import, scaffolding, and GitHub Releases-based registry commands. The test suite covers 276 test cases across all modules.

## Related

- [Agent Skills Standard](https://agentskills.io)
- [Handlebars](https://handlebarsjs.com) — Template engine syntax reference
