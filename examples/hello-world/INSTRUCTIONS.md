# {{name}} v{{version}}

Greet the user with a friendly message.

## When to Use

Use this skill when the user asks for a greeting or says hello.

## Steps

1. Determine the user's preferred greeting style from the `SKILL_CONFIG_GREETING_STYLE` environment variable (defaults to "casual")
2. Generate an appropriate greeting:
   - **formal**: "Good day. How may I assist you?"
   - **casual**: "Hey there! What can I help you with?"
   - **enthusiastic**: "Hello! Great to see you! What are we working on today?"
3. Present the greeting to the user

{{#provider "openclaw"}}
## OpenClaw Notes

OpenClaw runs this skill inline. No additional setup is required since this skill has no binary dependencies.
{{/provider}}

{{#provider "claude-code"}}
## Claude Code Notes

This skill is available via the `/hello-world` command or triggers automatically when the user says hello.
{{/provider}}

## About

This is a demonstration skill showing the unified skill specification format. It serves as a starting point for creating your own skills.
