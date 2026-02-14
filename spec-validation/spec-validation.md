# Spec Validation Test Plan

This document outlines test scenarios for validating that the CLI meets the unified skill specification.

---

## 1. Input Format Validation

### 1.1 skill.yaml Parsing

- Valid skill.yaml with all required fields (name, description, version) parses successfully
- skill.yaml missing required fields fails with clear error
- skill.yaml with invalid YAML syntax fails with parse error
- Empty skill.yaml file fails with appropriate error
- skill.yaml with only required fields succeeds

### 1.2 skill.yaml Field Validation

- Valid version string follows semver format
- Invalid version string (non-semver) fails validation
- Missing version field fails validation

### 1.3 INSTRUCTIONS.md Parsing

- Valid INSTRUCTIONS.md with markdown content parses successfully
- Missing INSTRUCTIONS.md fails with clear error
- Empty INSTRUCTIONS.md file succeeds (metadata-only skill)
- INSTRUCTIONS.md with YAML frontmatter generates a warning (frontmatter belongs in skill.yaml)

### 1.4 Provider Discovery

- Subdirectory with metadata.yaml is recognized as a supported provider
- Subdirectory without metadata.yaml is ignored
- Empty providers/ directory means no providers supported
- Missing providers/ directory means no providers supported
- Valid provider names (openclaw, claude-code, codex) are accepted
- Unknown provider directory names generate a warning

### 1.5 Provider-Specific Metadata

- Valid providers/openclaw/metadata.yaml parses correctly
- Valid providers/claude-code/metadata.yaml parses correctly
- Valid providers/codex/metadata.yaml parses correctly
- Provider metadata.yaml with unknown fields generates a warning
- Provider metadata.yaml with invalid YAML syntax fails with clear error referencing the file

### 1.6 Dependencies

- Valid dependency with name and version parses correctly
- Dependency without name fails validation
- Dependency with optional: true is marked as optional
- Circular dependencies are detected and rejected

### 1.7 Configuration Schema

- Config field with all required properties (name, description) parses correctly
- Config field missing required properties fails validation
- Config field with secret: true is marked as sensitive
- Config field with default value is captured correctly

---

## 2. Templating

### 2.1 Provider Block Helper

- `{{#provider "openclaw"}}` content included in openclaw output
- `{{#provider "openclaw"}}` content excluded from claude-code output
- `{{#provider "openclaw" "codex"}}` content included in both named provider outputs
- `{{#provider "openclaw" "codex"}}` content excluded from claude-code output
- Nested provider blocks render correctly
- Empty provider block produces no output

### 2.2 Variable Interpolation

- `{{name}}` replaced with skill name from skill.yaml
- `{{version}}` replaced with version from skill.yaml
- `{{description}}` replaced with description from skill.yaml
- `{{meta.emoji}}` replaced with provider-specific metadata field
- Undefined variable renders as empty string
- Nested metadata access (`{{meta.requires.bins}}`) works correctly

### 2.3 Standard Conditionals

- `{{#if meta.requires.bins}}` renders content when field exists and is truthy
- `{{#if meta.requires.bins}}` skips content when field is missing or empty
- `{{#unless}}` inverts the condition correctly
- `{{#each}}` iterates over arrays correctly
- `{{@last}}` works correctly inside `{{#each}}` blocks

### 2.4 Escaping

- `\{{not processed}}` outputs literal `{{not processed}}`
- Raw blocks (`{{{{raw}}}}...{{{{/raw}}}}`) pass content through unprocessed
- Template syntax inside code fences is still processed (authors must escape if needed)

### 2.5 Template Context

- Context includes all top-level fields from skill.yaml
- Context includes `provider` string set to current target
- Context includes `meta` object with fields from providers/X/metadata.yaml
- Context includes `config` array from skill.yaml

### 2.6 Error Handling

- Unclosed `{{#provider}}` block fails with clear error and line number
- Unclosed `{{#if}}` block fails with clear error
- Unknown helper fails with clear error
- Invalid Handlebars syntax fails with parse error

---

## 3. Compilation

### 3.1 Full Compilation

- Compiles for all supported providers successfully
- Output directory structure matches spec (dist/openclaw/, dist/claude-code/, dist/codex/)
- Each provider output contains valid SKILL.md
- Scripts directory is included when present in source
- Assets directory is included when present in source

### 3.2 Single Provider Compilation

- `--provider openclaw` only creates openclaw output
- `--provider claude-code` only creates claude-code output
- `--provider codex` only creates codex output

### 3.3 Selective Provider Compilation

- `--providers openclaw,claude-code` creates only those two outputs
- Invalid provider in list fails with error
- Empty provider list fails with error

### 3.4 Metadata Merging

- Universal fields from skill.yaml (name, description) appear in all provider outputs
- OpenClaw output merges skill.yaml + providers/openclaw/metadata.yaml into metadata.openclaw frontmatter
- Claude Code output merges skill.yaml + providers/claude-code/metadata.yaml into flat frontmatter
- Codex output merges skill.yaml into minimal frontmatter and generates agents/openai.yaml from providers/codex/metadata.yaml
- Conflicting field names between skill.yaml and metadata.yaml resolved with provider winning
- Nested objects in metadata.yaml replace (not deep-merge) matching objects in skill.yaml

### 3.5 Instruction Merging

- INSTRUCTIONS.md content (after template rendering) appears in all provider outputs
- providers/X/instructions.md content (after template rendering) is appended after INSTRUCTIONS.md
- providers/X/instructions.md missing results in rendered INSTRUCTIONS.md content only (no error)
- Merged output maintains valid markdown formatting
- Template directives are fully resolved before merging (no raw Handlebars in output)

### 3.6 Script and Asset Merging

- Shared scripts/ copied to all provider outputs that support scripts
- Provider-specific providers/X/scripts/ files override shared scripts with same filename
- Provider-specific scripts that don't conflict with shared scripts are added
- Same merge behavior applies to assets/
- Files in subdirectories within scripts/ merge correctly (preserving directory structure)

### 3.7 Provider-Specific Output Structure

- OpenClaw output is a single SKILL.md with metadata.openclaw block
- Claude Code output includes SKILL.md with flat frontmatter plus scripts/ and assets/ directories
- Codex output uses .agents/skills/ directory convention with agents/openai.yaml

### 3.8 Error Handling

- Non-existent skill directory fails gracefully
- Invalid skill.yaml during compilation fails with clear error
- Missing required fields during compilation fails with specific error
- Provider metadata.yaml with invalid syntax fails with clear error referencing the file
- Template rendering errors fail with clear error and line number

---

## 4. Registry Operations

### 4.1 Publishing

- Valid skill publishes successfully
- Version number increments correctly (PATCH, MINOR, MAJOR)
- Publishing to unsupported provider fails with warning
- Duplicate version fails or prompts for overwrite
- Successful publish includes correct metadata

### 4.2 Searching

- Search by keyword returns matching skills
- Search returns name, description, author, version
- Search with no results returns empty list
- Search supports filtering by provider

### 4.3 Installing

- Valid skill installs to correct local directory
- Version constraint (^1.0.0) resolves to compatible version
- Dependency skills are installed recursively
- Missing dependency fails with clear error

### 4.4 Listing

- List installed skills returns all local skills
- List includes version information
- List supports filtering by provider

---

## 5. Versioning

### 5.1 Version Parsing

- Valid semver (1.0.0) parses correctly
- Pre-release version (1.0.0-alpha) parses correctly
- Build metadata (1.0.0+build) parses correctly
- Invalid version string fails gracefully

### 5.2 Version Constraints

- Caret constraint (^1.0.0) matches compatible versions
- Tilde constraint (~1.1.0) matches patch versions
- Exact constraint (1.0.0) matches only that version
- Range constraint (>=1.0.0 <2.0.0) matches correctly

### 5.3 Version Resolution

- Resolving ^1.0.0 with versions [1.0.0, 1.1.0, 2.0.0] selects 1.1.0
- Resolving ~1.1.0 with versions [1.1.0, 1.1.1, 1.2.0] selects 1.1.1
- No matching version returns error
- Multiple candidates returns latest matching

---

## 6. Dependencies

### 6.1 Skill Dependencies

- Dependency with valid name and version resolves correctly
- Optional dependency missing does not cause failure
- Required dependency missing fails with error
- Circular dependency detection works correctly

### 6.2 System Dependencies

- Binary requirements from providers/openclaw/metadata.yaml (requires.bins) captured correctly
- Install instructions from providers/openclaw/metadata.yaml parsed correctly
- Multiple install options per provider handled

---

## 7. Configuration

### 7.1 Config Schema

- Required config fields must be provided
- Optional config fields can be omitted
- Default values applied when not provided
- Secret fields marked appropriately

### 7.2 Config Generation

- Environment variables generated with correct prefix (SKILL_CONFIG_)
- Config file generated in correct format
- Template variables replaced correctly

---

## 8. CLI Interface

### 8.1 Command Structure

- `skillc init` creates new skill from template (skill.yaml + INSTRUCTIONS.md + providers/)
- `skillc check` validates provider support
- `skillc compile` builds provider outputs
- `skillc publish` uploads to registry
- `skillc search` queries registry
- `skillc install` downloads and installs
- `skillc list` shows installed skills

### 8.2 Error Handling

- Invalid command fails with usage message
- Missing required arguments fails with error
- Invalid options fail with helpful message

### 8.3 Help System

- `--help` shows command usage
- Help messages are clear and accurate

---

## 9. File System Operations

### 9.1 Directory Handling

- Creates output directories as needed
- Handles existing output directory (prompt or overwrite)
- Removes temporary files after compilation

### 9.2 Permission Handling

- Handles read permission errors gracefully
- Handles write permission errors gracefully
- Creates hidden directories correctly (for Codex .agents/)

---

## 10. Integration Tests

### 10.1 End-to-End Compilation

- Complete workflow: skill.yaml + INSTRUCTIONS.md + providers/ → compile → valid outputs for all providers
- Template directives fully resolved in outputs
- Provider-specific sections only appear in matching outputs
- Outputs are valid SKILL.md files for each provider
- Compiled skills can be installed and used

### 10.2 Registry Workflow

- Complete workflow: compile → publish → install → use
- Installed skill functions correctly
- Version resolution works across publish/install cycle

### 10.3 Provider-Specific Outputs

- OpenClaw output passes OpenClaw validation (valid metadata.openclaw block)
- Claude Code output passes Claude Code validation (valid flat frontmatter)
- Codex output passes Codex validation (valid .agents/skills/ structure with openai.yaml)

### 10.4 Template Integration

- Skill with provider blocks compiles correctly for all providers
- Variable interpolation from skill.yaml works end-to-end
- Provider metadata accessible via `meta.*` in templates
- Escaped template syntax preserved in output
