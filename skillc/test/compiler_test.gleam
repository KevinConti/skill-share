import gleam/list
import gleam/string
import gleeunit/should
import simplifile
import skillc/compiler
import skillc/error

// ============================================================================
// §3.1 Full Compilation
// ============================================================================

pub fn compile_all_providers_test() {
  let result = compiler.compile_all("test/fixtures/valid-skill")
  let assert Ok(compiled_list) = result
  let providers = list.map(compiled_list, fn(c) { c.provider })
  should.be_true(list.contains(providers, "claude-code"))
  should.be_true(list.contains(providers, "codex"))
  should.be_true(list.contains(providers, "openclaw"))
}

pub fn compile_openclaw_produces_skill_md_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "openclaw")
  should.be_true(string.contains(compiled.skill_md, "---"))
  should.be_true(string.contains(compiled.skill_md, "name: test-skill"))
  should.be_true(string.contains(compiled.skill_md, "metadata.openclaw:"))
}

pub fn compile_claude_code_produces_skill_md_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "claude-code")
  should.be_true(string.contains(compiled.skill_md, "---"))
  should.be_true(string.contains(compiled.skill_md, "name: test-skill"))
  should.be_true(string.contains(compiled.skill_md, "user-invocable: true"))
}

pub fn compile_codex_produces_skill_md_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "codex")
  should.be_true(string.contains(compiled.skill_md, "---"))
  should.be_true(string.contains(compiled.skill_md, "name: test-skill"))
}

// ============================================================================
// §3.2 Single Provider Compilation
// ============================================================================

pub fn compile_single_provider_openclaw_test() {
  let result = compiler.compile("test/fixtures/valid-skill", "openclaw")
  should.be_ok(result)
  let assert Ok(compiled) = result
  should.equal(compiled.provider, "openclaw")
}

pub fn compile_single_provider_claude_code_test() {
  let result = compiler.compile("test/fixtures/valid-skill", "claude-code")
  should.be_ok(result)
  let assert Ok(compiled) = result
  should.equal(compiled.provider, "claude-code")
}

pub fn compile_single_provider_codex_test() {
  let result = compiler.compile("test/fixtures/valid-skill", "codex")
  should.be_ok(result)
  let assert Ok(compiled) = result
  should.equal(compiled.provider, "codex")
}

// ============================================================================
// §3.4 Metadata Merging
// ============================================================================

pub fn openclaw_metadata_merging_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "openclaw")
  // Universal fields at top level
  should.be_true(string.contains(compiled.skill_md, "name: test-skill"))
  should.be_true(string.contains(
    compiled.skill_md,
    "description: A test skill for validation",
  ))
  // Provider-specific under metadata.openclaw
  should.be_true(string.contains(compiled.skill_md, "metadata.openclaw:"))
}

pub fn claude_code_flat_frontmatter_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "claude-code")
  // Flat frontmatter includes provider metadata
  should.be_true(string.contains(
    compiled.skill_md,
    "disable-model-invocation: false",
  ))
  should.be_true(string.contains(compiled.skill_md, "user-invocable: true"))
}

pub fn codex_minimal_frontmatter_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "codex")
  should.be_true(string.contains(compiled.skill_md, "name: test-skill"))
  should.be_true(string.contains(compiled.skill_md, "version: 1.2.3"))
}

// ============================================================================
// §3.5 Instruction Merging
// ============================================================================

pub fn instructions_rendered_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "openclaw")
  // Template directives should be resolved
  should.be_true(string.contains(compiled.skill_md, "test-skill v1.2.3"))
  should.be_false(string.contains(compiled.skill_md, "{{name}}"))
  should.be_false(string.contains(compiled.skill_md, "{{version}}"))
}

pub fn provider_specific_content_included_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "openclaw")
  should.be_true(string.contains(compiled.skill_md, "OpenClaw Notes"))
  should.be_false(string.contains(compiled.skill_md, "Claude Code Notes"))
}

pub fn provider_specific_content_excluded_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "claude-code")
  should.be_true(string.contains(compiled.skill_md, "Claude Code Notes"))
  should.be_false(string.contains(compiled.skill_md, "OpenClaw Notes"))
}

pub fn multi_provider_content_openclaw_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "openclaw")
  should.be_true(string.contains(compiled.skill_md, "Shared Notes"))
}

pub fn multi_provider_content_codex_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "codex")
  should.be_true(string.contains(compiled.skill_md, "Shared Notes"))
}

pub fn multi_provider_content_excluded_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "claude-code")
  should.be_false(string.contains(compiled.skill_md, "Shared Notes"))
}

pub fn template_directives_fully_resolved_test() {
  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "openclaw")
  // No raw handlebars should remain (except escaped ones)
  should.be_false(string.contains(compiled.skill_md, "{{#provider"))
  should.be_false(string.contains(compiled.skill_md, "{{/provider}}"))
  should.be_false(string.contains(compiled.skill_md, "{{name}}"))
}

// ============================================================================
// §3.7 Provider-Specific Output Structure
// ============================================================================

pub fn emit_creates_output_structure_test() {
  let output_dir = "/tmp/skillc-test-emit"
  // Clean up if exists
  let _ = simplifile.delete(output_dir)

  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "openclaw")
  let assert Ok(_) = compiler.emit(compiled, output_dir, "test-skill")

  // Verify output exists
  let assert Ok(content) =
    simplifile.read(output_dir <> "/openclaw/test-skill/SKILL.md")
  should.be_true(string.contains(content, "test-skill"))

  // Clean up
  let _ = simplifile.delete(output_dir)
  Nil
}

pub fn emit_codex_structure_test() {
  let output_dir = "/tmp/skillc-test-emit-codex"
  let _ = simplifile.delete(output_dir)

  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "codex")
  let assert Ok(_) = compiler.emit(compiled, output_dir, "test-skill")

  // Codex uses .agents/skills/ convention
  let assert Ok(content) =
    simplifile.read(
      output_dir <> "/codex/.agents/skills/test-skill/SKILL.md",
    )
  should.be_true(string.contains(content, "test-skill"))

  let _ = simplifile.delete(output_dir)
  Nil
}

// ============================================================================
// §3.8 Error Handling
// ============================================================================

pub fn compile_nonexistent_directory_fails_test() {
  let result = compiler.compile("/tmp/nonexistent-skill-dir-xyz", "openclaw")
  should.be_error(result)
}

pub fn compile_unsupported_provider_fails_test() {
  let result =
    compiler.compile("test/fixtures/valid-skill", "nonexistent-provider")
  should.be_error(result)
  let assert Error(error.ProviderError(_, _)) = result
}

pub fn compile_no_providers_fails_test() {
  let result = compiler.compile_all("test/fixtures/no-providers")
  should.be_error(result)
}

// ============================================================================
// §10.1 End-to-End: hello-world example
// ============================================================================

pub fn compile_hello_world_openclaw_test() {
  let assert Ok(compiled) =
    compiler.compile("../examples/hello-world", "openclaw")
  should.be_true(string.contains(compiled.skill_md, "hello-world v1.0.0"))
  should.be_true(string.contains(compiled.skill_md, "OpenClaw Notes"))
  should.be_false(string.contains(compiled.skill_md, "Claude Code Notes"))
  should.be_false(string.contains(compiled.skill_md, "{{name}}"))
}

pub fn compile_hello_world_claude_code_test() {
  let assert Ok(compiled) =
    compiler.compile("../examples/hello-world", "claude-code")
  should.be_true(string.contains(compiled.skill_md, "hello-world v1.0.0"))
  should.be_true(string.contains(compiled.skill_md, "Claude Code Notes"))
  should.be_false(string.contains(compiled.skill_md, "OpenClaw Notes"))
}

pub fn compile_hello_world_codex_test() {
  let assert Ok(compiled) =
    compiler.compile("../examples/hello-world", "codex")
  should.be_true(string.contains(compiled.skill_md, "hello-world v1.0.0"))
  should.be_false(string.contains(compiled.skill_md, "OpenClaw Notes"))
  should.be_false(string.contains(compiled.skill_md, "Claude Code Notes"))
}

pub fn compile_hello_world_all_providers_test() {
  let assert Ok(compiled_list) =
    compiler.compile_all("../examples/hello-world")
  should.equal(list.length(compiled_list), 3)
}
