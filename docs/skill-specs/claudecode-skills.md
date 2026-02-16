# Claude Code Skills Configuration

## Overview

Claude Code skills extend Claude's capabilities. They follow the [Agent Skills](https://agentskills.io) open standard.

This document describes Claude Code's native SKILL.md format — the output that `npx skill-universe compile` produces for the `claude-code` provider. For the unified input format, see the [Unified Skill Specification](../unified-skill-spec.md).

## Directory Structure

```
skill-name/
├── SKILL.md          # Required - main instructions
├── template.md       # Optional - template for Claude to fill in
├── examples/         # Optional - sample outputs
└── scripts/          # Optional - scripts Claude can execute
```

## SKILL.md Format

### Frontmatter

```yaml
---
name: skill-name
description: What the skill does and when to use it
disable-model-invocation: true    # Only trigger manually with /skill-name
user-invocable: false             # Hide from / menu (default: true)
allowed-tools: [Read, Grep]        # Tools Claude can use without asking
model: claude-sonnet-4-20250514  # Specific model to use
context: fork                     # Run in forked subagent
agent: claude-code               # Which subagent type
argument-hint: [filename]        # Hint for autocomplete
---

# Skill instructions here...
```

### Available Variables

- `$ARGUMENTS` - All arguments passed when invoking the skill
- `$ARGUMENTS[0]` - Access specific argument by index
- `$0`, `$1` - Shorthand for positional arguments
- `${CLAUDE_SESSION_ID}` - Current session ID for logging

### Types of Content

**Reference content** - Knowledge Claude applies to current work:
```yaml
---
name: api-conventions
description: API design patterns for this codebase
---

When writing API endpoints:
- Use RESTful naming conventions
- Return consistent error formats
```

**Task content** - Step-by-step actions:
```yaml
---
name: deploy
description: Deploy the application to production
disable-model-invocation: true
---

Deploy the application:
1. Run the test suite
2. Build the application
3. Push to the deployment target
```

## Installation

### Local Installation
- Personal: `~/.claude/skills/<skill-name>/SKILL.md`
- Project: `.claude/skills/<skill-name>/SKILL.md`

### NPM Distribution
```bash
npx skills add owner/repo --skill skillname
npx skills add owner/repo --list                    # List available
npx skills add owner/repo --skill frontend -a code  # Install to specific agent
```

### Nested Directory Discovery

Claude automatically discovers skills from nested `.claude/skills/` directories in monorepos. When editing files in `packages/frontend/`, it also loads skills from `packages/frontend/.claude/skills/`.

## Invocation

- **Automatic**: Claude loads relevant skills based on description
- **Manual**: Use `/skill-name` command

## Examples

See existing skills on GitHub for real-world examples.

## References

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Agent Skills Standard](https://agentskills.io)
- [Vercel Skills (npx)](https://github.com/vercel-labs/skills)
- [Provider Comparison](../spec.md#provider-comparison) — Feature comparison across all providers
