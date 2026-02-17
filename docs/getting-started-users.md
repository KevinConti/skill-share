# Getting Started: Skill Users

Find, install, and use skills with your AI agent.

This guide covers how to discover skills built with `skill-universe`, install them for your preferred AI agent platform, and configure them.

## Prerequisites

- [Node.js](https://nodejs.org) (for `npx`)
- An AI agent that supports skills: [Claude Code](https://code.claude.com), [OpenClaw](https://docs.openclaw.ai), or [OpenAI Codex](https://developers.openai.com/codex/skills)

## What Are Skills?

Skills are packages that extend what your AI agent can do. A skill might teach your agent to read email, interact with a specific API, run a code formatter, or follow a particular workflow. Each skill contains instructions, metadata, and optionally scripts that the agent loads and follows.

## Finding Skills

Search for skills published to GitHub:

```bash
npx skill-universe search email
npx skill-universe search "code review"
```

This searches GitHub repositories tagged with `skill-universe` and returns matching skills with their descriptions and versions.

## Installing a Skill

Install a skill from GitHub:

```bash
npx skill-universe install owner/repo
```

This downloads the skill, compiles it for your detected agent platforms, and places the output in the correct directory.

### Install a Specific Version

```bash
npx skill-universe install owner/repo@v1.2.0
```

### Install for a Specific Provider

If you only use one agent, target it directly:

```bash
npx skill-universe install owner/repo --target claude-code
npx skill-universe install owner/repo --target openclaw
npx skill-universe install owner/repo --target codex
```

### Install from a Local Directory

If you have a skill source directory (e.g., you cloned a repo or are testing a skill someone shared with you), compile and install it manually:

```bash
# Compile for all supported providers
npx skill-universe compile /path/to/skill-dir --output dist

# Or compile for just your agent
npx skill-universe compile /path/to/skill-dir --target claude-code --output dist
```

Then copy the compiled output from `dist/` to your agent's skills directory (see [Where Skills Live](#where-skills-live) below). If you omit `--output`, the CLI writes to `~/.skill-universe` (or `%USERPROFILE%\.skill-universe` on Windows).

## Where Skills Live

Each agent looks for skills in a specific location:

| Agent | Skills Directory |
|-------|-----------------|
| **Claude Code** | `~/.claude/skills/skill-name/` (global) or `.claude/skills/skill-name/` (project) |
| **OpenClaw** | `~/development/openclaw/skills/` |
| **Codex** | `.agents/skills/` in your repo or home directory |

When you use `npx skill-universe install`, default compiled output is managed under `~/.skill-universe` (or `%USERPROFILE%\.skill-universe` on Windows) unless you pass `--output`. For manual installation, copy the contents of `dist/<provider>/` (if you compiled with `--output dist`) to the appropriate location.

## Using Installed Skills

How you invoke a skill depends on your agent:

### Claude Code

- **Manual**: Type `/skill-name` to invoke a skill directly
- **Automatic**: If the skill's description matches your request, the agent activates it on its own

Skills with `user-invocable: true` appear in the `/` autocomplete menu. Some skills run in a forked subagent (`context: fork`), which means they execute in isolation without affecting your main session.

### OpenClaw

- **Automatic only**: OpenClaw matches skills to your requests based on their descriptions. There is no manual invocation command.

OpenClaw will also check that required binaries are installed and offer installation instructions if they're missing.

### OpenAI Codex

- **Explicit**: Type `$skill-name` to invoke a skill
- **Implicit**: If the skill has `allow_implicit_invocation: true`, the agent can activate it automatically based on context

## Configuring Skills

Some skills require configuration, like API keys or preferences. Check the skill's documentation or its compiled SKILL.md for a `config` section listing what's needed.

### Environment Variables

Skills access configuration via environment variables with the `SKILL_CONFIG_` prefix. For a config field named `api_key`, set:

```bash
export SKILL_CONFIG_API_KEY=your-key-here
```

### Config File

Alternatively, create a config file at `~/.config/skill-name/config.json`:

```json
{
  "api_key": "your-key-here",
  "output_format": "markdown"
}
```

Fields marked `required: true` must be provided for the skill to function. Fields with a `default` value work without explicit configuration.

## Managing Installed Skills

### List Installed Skills

```bash
npx skill-universe list --installed
```

### List Available Versions

Check what versions are available for a published skill:

```bash
npx skill-universe list owner/repo
```

### Update a Skill

Install the latest version over the existing one:

```bash
npx skill-universe install owner/repo
```

Or install a specific newer version:

```bash
npx skill-universe install owner/repo@v2.0.0
```

## Troubleshooting

**Skill not loading**: Verify the compiled SKILL.md is in the correct directory for your agent. Run `npx skill-universe list --installed` to check.

**Missing configuration**: If a skill requires config fields you haven't set, it may fail silently or produce errors. Check the skill's SKILL.md for required config fields and set them via environment variables or config file.

**Binary not found (OpenClaw)**: OpenClaw skills may require specific binaries (like `python3` or `curl`). The agent will detect missing binaries and suggest install commands. Follow the suggested instructions.

**Skill not appearing in autocomplete (Claude Code)**: The skill needs `user-invocable: true` in its Claude Code metadata. If you installed it manually, verify the SKILL.md frontmatter includes this field.

## Next Steps

- Browse skills with `npx skill-universe search`
- Read the [Provider Comparison](spec.md#provider-comparison) to understand feature differences across platforms
- Interested in building your own? See the [Getting Started: Skill Creators](getting-started-creators.md) guide
