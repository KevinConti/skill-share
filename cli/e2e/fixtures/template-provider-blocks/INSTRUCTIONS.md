# Provider Block Test

{{#provider "openclaw"}}
OPENCLAW_ONLY_CONTENT
{{/provider}}

{{#provider "claude-code"}}
CLAUDE_CODE_ONLY_CONTENT
{{/provider}}

{{#provider "codex"}}
CODEX_ONLY_CONTENT
{{/provider}}

{{#provider "openclaw" "codex"}}
SHARED_OPENCLAW_CODEX
{{/provider}}

Common content for all providers.
