# {{name}} v{{version}}

{{description}}

## Usage

Use this skill to perform test operations.

{{#provider "openclaw"}}
## OpenClaw Notes

Icon: {{meta.emoji}}
{{/provider}}

{{#provider "claude-code"}}
## Claude Code Notes

This skill runs in a forked subagent.
{{/provider}}

{{#provider "openclaw" "codex"}}
## Shared Notes

This section appears in both OpenClaw and Codex outputs.
{{/provider}}

## Configuration

{{#each config}}
- **{{this.name}}**: {{this.description}}
{{/each}}
