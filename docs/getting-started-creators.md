# Getting Started: Skill Creators

Build a skill once, run it on every AI agent platform.

This guide walks you through creating your first cross-platform skill with `skill-universe`. By the end, you'll have a working skill that compiles to native packages for OpenClaw, Claude Code, and OpenAI Codex.

## Prerequisites

- [Node.js](https://nodejs.org) (for `npx`)
- Familiarity with YAML and Markdown

## What You're Building

A skill is a package of instructions, metadata, and optional scripts that teaches an AI agent how to perform a specific task. With `skill-universe`, you write the instructions once and compile them into the native format each platform expects.

The key insight: separate **content** (what the skill does) from **packaging** (how each platform wants it delivered).

## Step 1: Scaffold Your Skill

```bash
npx skill-universe init my-skill
```

This creates:

```
my-skill/
├── skill.yaml           # Universal metadata
├── INSTRUCTIONS.md      # Shared instructions
└── providers/           # Provider-specific overrides
    ├── openclaw/
    │   └── metadata.yaml
    ├── claude-code/
    │   └── metadata.yaml
    └── codex/
        └── metadata.yaml
```

You don't have to support every provider. Only providers with a `metadata.yaml` file in their subdirectory will be compiled. Remove any `providers/X/` directory you don't need.

## Step 2: Define Universal Metadata

Edit `skill.yaml` with your skill's identity. This file contains only fields shared across all providers.

```yaml
# my-skill/skill.yaml
name: my-skill
description: What the skill does and when the agent should use it
version: 1.0.0

metadata:
  author: Your Name
  tags: [example]
```

**Required fields**: `name`, `description`, `version`. Everything else is optional.

If your skill needs user configuration (API keys, preferences, etc.), add a `config` section:

```yaml
config:
  - name: api_key
    description: API key for the service
    required: true
    secret: true
  - name: output_format
    description: Output format (json, text, markdown)
    required: false
    default: markdown
```

Users provide config values via environment variables (`SKILL_CONFIG_API_KEY`, `SKILL_CONFIG_OUTPUT_FORMAT`).

## Step 3: Write Instructions

Edit `INSTRUCTIONS.md` with the instructions all providers share. This is the core of your skill — it tells the AI agent what to do.

```markdown
# My Skill

Describe what this skill does and when to use it.

## Steps

1. First, do this
2. Then, do that
3. Finally, return the result

## Error Handling

If something goes wrong, try this instead.
```

### Using Templates

INSTRUCTIONS.md supports [Handlebars](https://handlebarsjs.com) syntax for dynamic content.

**Variable interpolation** — insert values from `skill.yaml`:

```markdown
# {{name}} v{{version}}

{{description}}
```

**Provider blocks** — include content only for specific providers:

```markdown
{{#provider "openclaw"}}
## OpenClaw Notes

OpenClaw-specific instructions here.
{{/provider}}

{{#provider "claude-code"}}
## Claude Code Notes

Claude Code-specific instructions here.
{{/provider}}
```

Provider blocks are stripped from non-matching providers during compilation, so the OpenClaw output never sees the Claude Code section and vice versa.

**Conditionals** — render content based on metadata:

```markdown
{{#if meta.requires.bins}}
## System Requirements

This skill requires: {{#each meta.requires.bins}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}
{{/if}}
```

For longer provider-specific content, create `providers/X/instructions.md` instead of using inline blocks. It gets appended to the rendered INSTRUCTIONS.md during compilation.

## Step 4: Add Provider Metadata

Each provider has its own capabilities. The `metadata.yaml` files let you take advantage of platform-specific features.

### OpenClaw

OpenClaw skills run automatically (no manual invocation). Declare binary requirements and install instructions.

```yaml
# providers/openclaw/metadata.yaml
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

### Claude Code

Claude Code skills can be invoked manually (`/skill-name`) or automatically. Configure tool permissions and execution model.

```yaml
# providers/claude-code/metadata.yaml
user-invocable: true
allowed-tools: [Read, Grep, Bash]
context: fork
```

Setting `context: fork` runs the skill in an isolated subagent, which is useful for skills that shouldn't affect the main session.

### OpenAI Codex

Codex skills support UI metadata and invocation policies.

```yaml
# providers/codex/metadata.yaml
interface:
  display_name: "My Skill"
  short_description: "What it does"

policy:
  allow_implicit_invocation: true
```

## Step 5: Compile

```bash
# Compile for all supported providers
npx skill-universe compile my-skill
```

Output appears in `dist/`:

```
dist/
├── openclaw/my-skill/SKILL.md
├── claude-code/my-skill/SKILL.md
└── codex/.agents/skills/my-skill/SKILL.md
```

To compile for a single provider:

```bash
npx skill-universe compile my-skill --target claude-code
```

### Verify the Output

Check that each compiled SKILL.md has the correct format:

- **OpenClaw**: Single SKILL.md with `metadata.openclaw` block in frontmatter
- **Claude Code**: SKILL.md with flat frontmatter (`name`, `description`, `allowed-tools`, etc.)
- **Codex**: SKILL.md with minimal frontmatter plus `agents/openai.yaml`

Template expressions like `{{name}}` should be replaced with their values. Provider blocks should only appear in the matching provider's output.

## Step 6: Publish

Share your skill with others via GitHub Releases:

```bash
npx skill-universe publish my-skill
```

This creates a GitHub Release tagged with the version from `skill.yaml` and uploads the skill source as a tarball. Others can then install it:

```bash
npx skill-universe install your-username/my-skill
```

## Adding Scripts

If your skill includes helper scripts, place them in a shared `scripts/` directory:

```
my-skill/
├── scripts/
│   └── helper.py         # Shared across all providers
└── providers/
    └── claude-code/
        └── scripts/
            └── helper.py  # Overrides the shared version for Claude Code
```

Provider-specific scripts override shared scripts with the same filename. This lets you have a default implementation with per-provider overrides where needed.

## Tips

- **Write a good description** in `skill.yaml`. Agents use it to decide when to activate your skill automatically.
- **Start simple**. You can always add provider-specific metadata later. A minimal skill with just `skill.yaml`, `INSTRUCTIONS.md`, and one `providers/X/metadata.yaml` is perfectly valid.
- **Use `check` to verify**. Run `npx skill-universe check my-skill` to see which providers your skill supports.
- **Test with a real agent**. Copy the compiled output into the agent's skills directory and try it.

## Next Steps

- See [`examples/hello-world/`](../examples/hello-world/) for a complete working example
- Read the [Unified Skill Specification](unified-skill-spec.md) for the full reference
- See the [Provider Comparison](spec.md#provider-comparison) for feature differences across platforms
- Read the provider-specific format references: [OpenClaw](skill-specs/openclaw-skills.md), [Claude Code](skill-specs/claudecode-skills.md), [Codex](skill-specs/openai-codex-skills.md)
