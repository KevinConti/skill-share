# Unified Skill Specification System

## Overview

This document defines a system for creating skills that can be compiled for multiple AI agent skill providers from a single source. Skill developers write shared instructions once, declare provider-specific metadata separately, and use the `npx skill-universe` compiler to generate native skill packages for each target platform.

## Target Users

Developers who wish to create skills that work across multiple AI agent platforms.

## Supported Providers

- OpenClaw
- Claude Code
- OpenAI Codex

## Key Terms

| Term | Definition |
|------|------------|
| **Skill** | A package of instructions, metadata, and optional scripts that extends an AI agent's capabilities for a specific task. |
| **Provider** | An AI agent platform that consumes skills (OpenClaw, Claude Code, or Codex). |
| **skill.yaml** | The universal metadata file declaring a skill's identity, version, dependencies, and configuration. Shared across all providers. |
| **INSTRUCTIONS.md** | The shared instruction content. Supports Handlebars template syntax for provider-specific sections. |
| **providers/X/** | A subdirectory for provider X containing metadata, optional instructions, and optional scripts. The existence of this directory declares that the skill supports provider X. |
| **metadata.yaml** | A provider-specific metadata file (inside `providers/X/`) containing only the fields that differ for that platform. |
| **instructions.md** | An optional provider-specific instruction file (inside `providers/X/`) appended to the rendered INSTRUCTIONS.md during compilation. |
| **SKILL.md** | The compiled output file consumed by a provider. Each provider has its own format. |
| **skill-universe** | The CLI compiler that merges universal and provider-specific sources into native skill packages. Invoked via `npx skill-universe`. |
| **Registry** | A distribution system for publishing, searching, and installing skills. |

---

## Input Format

### Directory Structure

```
skill-name/
├── skill.yaml              # Universal metadata (required)
├── INSTRUCTIONS.md          # Shared instructions (required)
├── scripts/                 # Shared scripts (optional)
├── assets/                  # Shared templates/resources (optional)
├── references/              # Shared documentation (optional)
└── providers/               # Provider-specific overrides (optional)
    ├── openclaw/
    │   ├── metadata.yaml    # OpenClaw-specific metadata
    │   ├── instructions.md  # OpenClaw-specific instructions (appended)
    │   └── scripts/         # OpenClaw-specific scripts (merged)
    ├── claude-code/
    │   ├── metadata.yaml    # Claude Code-specific metadata
    │   ├── instructions.md
    │   └── scripts/
    └── codex/
        ├── metadata.yaml    # Codex-specific metadata
        ├── instructions.md
        └── scripts/
```

### Provider Support

A skill supports a provider if and only if the directory `providers/X/` exists and contains a `metadata.yaml` file. There is no separate declaration — the directory structure is the source of truth.

### skill.yaml — Universal Metadata

Contains only fields that are shared across all providers.

```yaml
name: fastmail
description: Read and send email via the Fastmail JMAP API
version: 1.0.0
license: MIT
homepage: https://github.com/user/fastmail-skill
repository: https://github.com/user/fastmail-skill

metadata:
  author: Your Name
  author_email: you@example.com
  tags: [email, fastmail, jmap]

# Dependencies on other skills
dependencies:
  - name: email-helper
    version: ^2.0.0
    optional: true

# Configuration schema for users to fill in
config:
  - name: api_token
    description: Fastmail API token
    required: true
    secret: true
  - name: account_id
    description: Fastmail account ID
    required: true
  - name: cache_ttl
    description: Cache TTL in seconds
    required: false
    default: 300
```

#### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Skill identifier (lowercase, hyphens allowed) |
| `description` | string | What the skill does and when to use it |
| `version` | string | Semantic version (MAJOR.MINOR.PATCH) |

#### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `license` | string | SPDX license identifier |
| `homepage` | string | Project homepage URL |
| `repository` | string | Source repository URL |
| `metadata.author` | string | Author name |
| `metadata.author_email` | string | Author email |
| `metadata.tags` | list | Search/discovery tags |
| `dependencies` | list | Skill dependencies (see [Dependencies](#dependencies)) |
| `config` | list | User configuration schema (see [Configuration](#configuration)) |

### INSTRUCTIONS.md — Shared Instructions

Markdown with optional [Handlebars template syntax](#templating). Contains the instructions that are common to all providers, with the ability to include provider-specific sections inline.

```markdown
# Fastmail Skill

Use the Fastmail JMAP API to read and send email.

## Prerequisites

Ensure `python3` and the `requests` library are available.

## Usage

### Check inbox

Run the fastmail CLI to list recent messages:

    fastmail list --limit 20

### Send email

    fastmail send --to recipient@example.com --subject "Hello" --body "Message"

{{#provider "openclaw"}}
## OpenClaw Notes

Install via uv for faster dependency resolution:

    uv pip install fastmail-cli
{{/provider}}

{{#provider "claude-code"}}
## Claude Code Notes

This skill runs in a forked subagent. File operations are isolated from the main session.
{{/provider}}

## Error Handling

If authentication fails, verify that the API token is correct and has not expired.
```

### providers/X/metadata.yaml — Provider-Specific Metadata

Each file contains only the metadata fields specific to that provider. These are merged with `skill.yaml` during compilation to produce the correct frontmatter for each provider's SKILL.md format.

#### providers/openclaw/metadata.yaml

```yaml
emoji: "📧"
requires:
  bins: [python3, curl]
install:
  - id: pip
    kind: pip
    package: fastmail-cli
    bins: [fastmail]
    label: Install Fastmail CLI (pip)
  - id: brew
    kind: brew
    formula: fastmail-cli
    bins: [fastmail]
    label: Install Fastmail CLI (brew)
```

| Field | Type | Description |
|-------|------|-------------|
| `emoji` | string | Icon displayed with the skill |
| `requires.bins` | list | Required binary executables |
| `install` | list | Installation instructions (see [OpenClaw Skills](skill-specs/openclaw-skills.md) for `kind` options) |

#### providers/claude-code/metadata.yaml

```yaml
disable-model-invocation: false
user-invocable: true
allowed-tools: [Read, Grep, Bash]
model: claude-sonnet-4-20250514
context: fork
agent: claude-code
argument-hint: "[email address]"
```

| Field | Type | Description |
|-------|------|-------------|
| `disable-model-invocation` | boolean | Only trigger manually with /skill-name |
| `user-invocable` | boolean | Show in / menu (default: true) |
| `allowed-tools` | list | Tools the agent can use without asking |
| `model` | string | Specific model version |
| `context` | string | `fork` to run in a subagent |
| `agent` | string | Subagent type |
| `argument-hint` | string | Autocomplete hint |

#### providers/codex/metadata.yaml

```yaml
interface:
  display_name: "Fastmail"
  short_description: "Read and send email"
  brand_color: "#3B82F6"

policy:
  allow_implicit_invocation: true

dependencies:
  tools: []
```

| Field | Type | Description |
|-------|------|-------------|
| `interface` | object | UI metadata (display_name, short_description, icons, brand_color, default_prompt) |
| `policy` | object | Invocation policy (allow_implicit_invocation) |
| `dependencies` | object | Tool dependencies (MCP servers, etc.) |

### providers/X/instructions.md — Provider-Specific Instructions

Optional markdown appended to the rendered INSTRUCTIONS.md during compilation. This file is also processed through the template engine.

Use this for longer provider-specific content that would clutter the main INSTRUCTIONS.md. For short provider-specific sections, prefer inline `{{#provider}}` blocks in INSTRUCTIONS.md instead.

### providers/X/scripts/ — Provider-Specific Scripts

Optional directory containing scripts that are specific to a provider. During compilation, scripts are merged as follows:

1. All files from the shared `scripts/` directory are copied to the output
2. All files from `providers/X/scripts/` are copied to the output, **overriding** any shared scripts with the same filename

This allows a shared default with per-provider overrides where needed.

### providers/X/assets/ — Provider-Specific Assets

Same merge behavior as scripts: shared `assets/` are copied first, then `providers/X/assets/` overrides matching filenames.

---

## Templating

INSTRUCTIONS.md and `providers/X/instructions.md` are processed through a Handlebars-compatible template engine during compilation. This allows provider-specific content inline, variable interpolation, and conditional logic.

### Template Context

The template engine receives the following context when compiling for a given provider:

```yaml
# Current compilation target
provider: "openclaw"

# Universal metadata from skill.yaml
name: "fastmail"
version: "1.0.0"
description: "Read and send email via the Fastmail JMAP API"

# Provider-specific metadata from providers/X/metadata.yaml
meta:
  emoji: "📧"
  requires:
    bins: [python3, curl]

# Configuration fields from skill.yaml
config:
  - name: api_token
    description: Fastmail API token
    required: true
    secret: true
```

### Provider Block Helper

The `{{#provider}}` helper renders content only when compiling for the named provider:

```markdown
{{#provider "openclaw"}}
This content only appears in the OpenClaw output.
{{/provider}}

{{#provider "claude-code"}}
This content only appears in the Claude Code output.
{{/provider}}
```

Multiple providers can be specified:

```markdown
{{#provider "openclaw" "codex"}}
This content appears in both OpenClaw and Codex outputs.
{{/provider}}
```

### Variable Interpolation

Insert values from the template context:

```markdown
# {{name}} v{{version}}

{{description}}
```

Access provider-specific metadata:

```markdown
{{#provider "openclaw"}}
Skill icon: {{meta.emoji}}
{{/provider}}
```

### Standard Conditionals

Standard Handlebars `{{#if}}` and `{{#unless}}` are supported:

```markdown
{{#if meta.requires.bins}}
## System Requirements

This skill requires the following binaries: {{#each meta.requires.bins}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}
{{/if}}
```

### Escaping

To output literal Handlebars syntax without processing, use raw blocks:

```markdown
{{{{raw}}}}
This {{will not}} be processed as a template.
{{{{/raw}}}}
```

Or escape individual expressions with a backslash: `\{{not processed}}`.

---

## Provider Support Detection

### Query

```bash
npx skill-universe check skill-name
```

### Output Format

```
skill-name v1.0.0
Supported providers:
  - openclaw
  - claude-code
  - codex
```

Support is determined by the existence of `providers/X/metadata.yaml`.

---

## Compilation

### How It Works

For each target provider, the compiler:

1. **Discovers providers**: Scans `providers/` for subdirectories containing `metadata.yaml`.
2. **Merges metadata**: Reads `skill.yaml` (universal) and `providers/X/metadata.yaml` (provider-specific), then produces the frontmatter format expected by that provider. **Provider values override universal values** when field names conflict.
3. **Renders templates**: Processes `INSTRUCTIONS.md` through the Handlebars template engine with the merged context. If `providers/X/instructions.md` exists, renders it and appends the result.
4. **Merges scripts and assets**: Copies shared `scripts/` and `assets/`, then copies `providers/X/scripts/` and `providers/X/assets/` on top. **Provider files override shared files** with the same filename.
5. **Emits output**: Writes the compiled SKILL.md and supporting files into the provider's expected directory structure.

### Merge Precedence

When the same field name appears in both `skill.yaml` and `providers/X/metadata.yaml`, the **provider-specific value wins**. This applies at the top level of each file — nested objects are replaced entirely, not deep-merged.

Example: if `skill.yaml` has `description: "General description"` and `providers/openclaw/metadata.yaml` has `description: "OpenClaw-specific description"`, the OpenClaw output uses the provider-specific description.

### Command Line

```bash
# Compile for all supported providers
npx skill-universe compile skill-name

# Compile for specific providers
npx skill-universe compile skill-name --providers openclaw,claude-code

# Compile for a single provider
npx skill-universe compile skill-name --target codex
```

### Output Directory Structure

```
dist/
├── openclaw/
│   └── skill-name/
│       └── SKILL.md
├── claude-code/
│   └── skill-name/
│       ├── SKILL.md
│       ├── scripts/
│       └── template.md
└── codex/
    └── .agents/
        └── skills/
            └── skill-name/
                ├── SKILL.md
                ├── scripts/
                └── agents/
                    └── openai.yaml
```

### Provider-Specific Output Formats

**OpenClaw**: Produces a single SKILL.md with `metadata.openclaw` block in frontmatter. Universal metadata fields (name, description) are placed at the top level. OpenClaw-specific fields (emoji, requires, install) are nested under `metadata.openclaw`.

**Claude Code**: Produces SKILL.md with flat frontmatter (name, description, allowed-tools, context, etc.). Copies scripts/ and assets/ into the output directory. Templates are placed as template.md alongside SKILL.md.

**Codex**: Produces SKILL.md with minimal frontmatter (name, description). Generates `agents/openai.yaml` from the provider's metadata.yaml fields (interface, policy, dependencies). Uses `.agents/skills/` directory convention. Copies scripts/, references/, and assets/.

---

## Registry

Skills are distributed via GitHub Releases. The CLI uses the GitHub CLI (`gh`) for registry operations.

### Publishing

```bash
# Publish to GitHub Releases (infers repo from git remote)
npx skill-universe publish skill-dir

# Publish to a specific repo
npx skill-universe publish skill-dir --repo owner/repo
```

Publishing creates a GitHub Release tagged with the version from `skill.yaml` and uploads a tarball of the skill source directory.

### Searching and Installing

```bash
# Search for skills (searches GitHub repos tagged skill-universe)
npx skill-universe search email

# Install a skill from GitHub Releases
npx skill-universe install owner/repo

# Install a specific version
npx skill-universe install owner/repo@v1.2.0

# Install for a specific provider only
npx skill-universe install owner/repo --target claude-code

# List available versions for a repo
npx skill-universe list owner/repo

# List locally installed skills
npx skill-universe list --installed
```

---

## Versioning

### Semantic Versioning

Skills use Semantic Versioning (semver):

- `MAJOR` — Breaking changes
- `MINOR` — New features (backward compatible)
- `PATCH` — Bug fixes

### Version Constraints

Consumers can specify version ranges in dependencies:

```yaml
dependencies:
  - name: email-helper
    version: ^1.0.0    # Compatible with 1.x.x
  - name: formatter
    version: ~1.1.0    # Compatible with 1.1.x
  - name: core-lib
    version: 1.0.0     # Exact version
```

---

## Dependencies

### Skill Dependencies

Skills can declare dependencies on other skills:

```yaml
dependencies:
  - name: email-helper
    version: ^2.0.0
    optional: false
  - name: calendar
    version: ^1.0.0
    optional: true
```

- **Required** dependencies (`optional: false` or omitted) must be installed for the skill to function.
- **Optional** dependencies enhance functionality but are not required.
- Circular dependencies are detected and rejected by the compiler.

### System Dependencies

System-level requirements (binaries, packages) are declared per-provider in `providers/X/metadata.yaml`, since installation methods differ across platforms. See each provider's metadata schema above.

---

## Configuration

### User Configuration

Skills define configuration that users must provide via `skill.yaml`:

```yaml
config:
  - name: api_token
    description: API token for authentication
    required: true
    secret: true
  - name: cache_ttl
    description: Cache TTL in seconds
    required: false
    default: 300
```

### Environment Variables

Compiled skills access configuration via environment variables with the `SKILL_CONFIG_` prefix:

- `SKILL_CONFIG_API_TOKEN`
- `SKILL_CONFIG_CACHE_TTL`

Or via config file: `~/.config/skill-name/config.json`

---

## CLI Commands

| Command | Description |
|---------|-------------|
| `npx skill-universe init` | Create a new skill from template |
| `npx skill-universe check` | Check provider support |
| `npx skill-universe compile` | Compile for specific providers |
| `npx skill-universe import` | Import a provider-specific skill into unified format |
| `npx skill-universe publish` | Publish to GitHub Releases |
| `npx skill-universe search` | Search for skills |
| `npx skill-universe install` | Install from GitHub Releases |
| `npx skill-universe list` | List versions or installed skills |

---

## File Format Summary

| File | Required | Purpose |
|------|----------|---------|
| `skill.yaml` | Yes | Universal metadata (name, version, deps, config) |
| `INSTRUCTIONS.md` | Yes | Shared instructions with template support |
| `providers/X/metadata.yaml` | No | Provider-specific metadata; declares provider support |
| `providers/X/instructions.md` | No | Provider-specific instructions (appended after rendering) |
| `providers/X/scripts/` | No | Provider-specific scripts (merged with shared, overrides on conflict) |
| `providers/X/assets/` | No | Provider-specific assets (merged with shared, overrides on conflict) |
| `scripts/*` | No | Shared executable scripts |
| `assets/*` | No | Shared templates, resources |
| `references/*` | No | Documentation |

---

## References

- [Agent Skills Standard](https://agentskills.io)
- [Claude Code Skills](https://code.claude.com/docs/en/skills)
- [OpenClaw Skills](https://docs.openclaw.ai)
- [Codex Skills](https://developers.openai.com/codex/skills)
- [Handlebars](https://handlebarsjs.com) — Template syntax reference
