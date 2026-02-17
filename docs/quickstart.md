# Quick Start Guide

Create a cross-platform skill in 4 steps.

## Prerequisites

- Familiarity with YAML and Markdown
- The `skill-universe` CLI (`npx skill-universe`)

## Step 1: Create the Skill Directory

```bash
mkdir -p my-skill/providers/{openclaw,claude-code,codex}
```

## Step 2: Write skill.yaml

Define your skill's identity and configuration. This file contains only universal metadata — no provider-specific fields.

```yaml
# my-skill/skill.yaml
name: my-skill
description: What the skill does and when to use it
version: 1.0.0

metadata:
  author: Your Name
  tags: [example]

config:
  - name: api_key
    description: API key for the service
    required: true
    secret: true
```

Note: there is no `providers` list here. Provider support is declared by the existence of `providers/X/metadata.yaml` files (Step 4).

## Step 3: Write INSTRUCTIONS.md

Write the instructions that are common to all providers. You can use [Handlebars template syntax](unified-skill-spec.md#templating) for inline provider-specific sections.

```markdown
# My Skill

Instructions that apply to all providers go here.

## Usage

1. Step one
2. Step two
3. Step three

\{{#provider "openclaw"}}
## OpenClaw Notes

Additional instructions for OpenClaw users.
\{{/provider}}

\{{#provider "claude-code"}}
## Claude Code Notes

Additional instructions for Claude Code users.
\{{/provider}}
```

The `{{#provider "name"}}` blocks are stripped for non-matching providers during compilation. You can also use `{{name}}`, `{{version}}`, and other variables from skill.yaml.

## Step 4: Add Provider Metadata

Create a `metadata.yaml` inside each provider's subdirectory. Only include fields specific to that provider.

**providers/openclaw/metadata.yaml** — Binary requirements and install instructions:
```yaml
emoji: "🔧"
requires:
  bins: [python3]
install:
  - id: pip
    kind: pip
    package: my-tool
    bins: [my-tool]
    label: Install my-tool (pip)
```

**providers/claude-code/metadata.yaml** — Tool permissions and execution model:
```yaml
user-invocable: true
allowed-tools: [Read, Grep, Bash]
context: fork
```

**providers/codex/metadata.yaml** — UI metadata and invocation policy:
```yaml
interface:
  display_name: "My Skill"
  short_description: "What it does"

policy:
  allow_implicit_invocation: true
```

### Optional: Provider-Specific Instructions and Scripts

For longer provider-specific content, add `providers/X/instructions.md` (appended after the rendered INSTRUCTIONS.md):

```markdown
<!-- providers/openclaw/instructions.md -->

## Extended OpenClaw Setup

Detailed instructions that would clutter the main file...
```

For provider-specific scripts, add them to `providers/X/scripts/`. They override shared `scripts/` files with the same filename.

## Compile

```bash
# Compile for all providers
npx skill-universe compile my-skill --output dist

# Compile for a specific provider
npx skill-universe compile my-skill --target claude-code --output dist
```

Output appears in `dist/` (explicit via `--output dist`; default output root is `~/.skill-universe`):

```
dist/
├── openclaw/my-skill/SKILL.md
├── claude-code/my-skill/SKILL.md
└── codex/.agents/skills/my-skill/SKILL.md
```

## Verify

Check that each output has the correct format:

- **OpenClaw**: Single SKILL.md with `metadata.openclaw` in frontmatter
- **Claude Code**: SKILL.md with flat frontmatter (name, description, allowed-tools, etc.)
- **Codex**: SKILL.md with minimal frontmatter plus `agents/openai.yaml`

Template blocks like `{{#provider "openclaw"}}` should only appear in the matching provider's output. Variable interpolations like `{{name}}` should be replaced with their values.

## Next Steps

- See the [Unified Skill Specification](unified-skill-spec.md) for the full reference
- See [`examples/hello-world/`](../examples/hello-world/) for a complete working example
- See the [Provider Comparison](spec.md#provider-comparison) for feature differences across platforms
