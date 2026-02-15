import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile
import skillc/compiler
import skillc/error
import skillc/importer.{FrontmatterPair, SourceDirectory}
import skillc/semver
import skillc/types

// ============================================================================
// §1 Frontmatter Parsing
// ============================================================================

pub fn parse_frontmatter_openclaw_test() {
  let content =
    "---\nname: test\ndescription: \"A test\"\nversion: 1.0.0\nmetadata.openclaw:\n  emoji: rocket\n---\n\nBody here."
  let assert Ok(frontmatter) = importer.parse_frontmatter(content)
  let keys = list.map(frontmatter.pairs, fn(p) { p.key })
  should.be_true(list.contains(keys, "name"))
  should.be_true(list.contains(keys, "metadata.openclaw"))
  should.be_true(string.contains(frontmatter.body, "Body here."))
}

pub fn parse_frontmatter_claude_code_test() {
  let content =
    "---\nname: test\ndescription: \"A test\"\nversion: 1.0.0\nuser-invocable: true\n---\n\nBody."
  let assert Ok(frontmatter) = importer.parse_frontmatter(content)
  let keys = list.map(frontmatter.pairs, fn(p) { p.key })
  should.be_true(list.contains(keys, "user-invocable"))
  should.be_true(string.contains(frontmatter.body, "Body."))
}

pub fn parse_frontmatter_codex_test() {
  let content = "---\nname: test\nversion: 1.0.0\n---\n\nCodex body."
  let assert Ok(frontmatter) = importer.parse_frontmatter(content)
  should.equal(list.length(frontmatter.pairs), 2)
  should.be_true(string.contains(frontmatter.body, "Codex body."))
}

pub fn parse_frontmatter_missing_error_test() {
  let content = "# No frontmatter\n\nJust body."
  let result = importer.parse_frontmatter(content)
  should.be_error(result)
  let assert Error(error.ImportError(_, msg)) = result
  should.be_true(string.contains(msg, "No YAML frontmatter"))
}

pub fn parse_frontmatter_unclosed_error_test() {
  let content = "---\nname: test\nversion: 1.0.0\n\nNo closing fence."
  let result = importer.parse_frontmatter(content)
  should.be_error(result)
  let assert Error(error.ImportError(_, msg)) = result
  should.be_true(string.contains(msg, "Unclosed"))
}

// ============================================================================
// §2 Provider Auto-Detection
// ============================================================================

pub fn detect_provider_openclaw_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "metadata.openclaw", value: "  emoji: rocket"),
  ]
  let assert Ok(provider) = importer.detect_provider(pairs, "/tmp/nonexistent")
  should.equal(provider, types.OpenClaw)
}

pub fn detect_provider_claude_code_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "user-invocable", value: "true"),
    FrontmatterPair(key: "allowed-tools", value: "[Read, Grep]"),
  ]
  let assert Ok(provider) = importer.detect_provider(pairs, "/tmp/nonexistent")
  should.equal(provider, types.ClaudeCode)
}

pub fn detect_provider_codex_from_directory_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "version", value: "1.0.0"),
  ]
  let assert Ok(provider) =
    importer.detect_provider(pairs, "test/fixtures/import-codex")
  should.equal(provider, types.Codex)
}

pub fn detect_provider_ambiguous_error_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "version", value: "1.0.0"),
  ]
  let result = importer.detect_provider(pairs, "/tmp/nonexistent")
  should.be_error(result)
  let assert Error(error.ImportError(_, msg)) = result
  should.be_true(string.contains(msg, "Cannot auto-detect"))
}

// ============================================================================
// §3 Field Separation
// ============================================================================

pub fn separate_fields_openclaw_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "description", value: "\"A test\""),
    FrontmatterPair(key: "version", value: "1.0.0"),
    FrontmatterPair(key: "license", value: "MIT"),
    FrontmatterPair(
      key: "metadata.openclaw",
      value: "  emoji: rocket\n  category: devtools",
    ),
  ]
  let assert Ok(separated) =
    importer.separate_fields(pairs, types.OpenClaw)
  should.equal(separated.universal.name, "test")
  should.equal(separated.universal.description, "A test")
  should.equal(semver.to_string(separated.universal.version), "1.0.0")
  should.equal(separated.universal.license, Some("MIT"))
  let provider_keys = list.map(separated.provider, fn(p) { p.key })
  should.be_true(list.contains(provider_keys, "emoji"))
  should.be_true(list.contains(provider_keys, "category"))
}

pub fn separate_fields_claude_code_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "description", value: "\"A test\""),
    FrontmatterPair(key: "version", value: "1.0.0"),
    FrontmatterPair(key: "user-invocable", value: "true"),
    FrontmatterPair(key: "allowed-tools", value: "[Read, Grep]"),
  ]
  let assert Ok(separated) =
    importer.separate_fields(pairs, types.ClaudeCode)
  should.equal(separated.universal.name, "test")
  should.equal(separated.universal.license, None)
  let provider_keys = list.map(separated.provider, fn(p) { p.key })
  should.be_true(list.contains(provider_keys, "user-invocable"))
  should.be_true(list.contains(provider_keys, "allowed-tools"))
  should.be_false(list.contains(provider_keys, "name"))
}

pub fn separate_fields_universal_extracted_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "my-skill"),
    FrontmatterPair(key: "description", value: "Desc"),
    FrontmatterPair(key: "version", value: "3.0.0"),
  ]
  let assert Ok(separated) =
    importer.separate_fields(pairs, types.Codex)
  should.equal(separated.universal.name, "my-skill")
  should.equal(separated.universal.description, "Desc")
  should.equal(semver.to_string(separated.universal.version), "3.0.0")
  should.equal(separated.provider, [])
}

pub fn separate_fields_missing_name_error_test() {
  let pairs = [
    FrontmatterPair(key: "description", value: "Desc"),
    FrontmatterPair(key: "version", value: "1.0.0"),
  ]
  let result = importer.separate_fields(pairs, types.Codex)
  should.be_error(result)
  let assert Error(error.ImportError("name", msg)) = result
  should.be_true(string.contains(msg, "missing"))
}

pub fn separate_fields_missing_description_error_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "version", value: "1.0.0"),
  ]
  let result = importer.separate_fields(pairs, types.Codex)
  should.be_error(result)
  let assert Error(error.ImportError("description", msg)) = result
  should.be_true(string.contains(msg, "missing"))
}

pub fn separate_fields_missing_version_error_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "description", value: "Desc"),
  ]
  let result = importer.separate_fields(pairs, types.Codex)
  should.be_error(result)
  let assert Error(error.ImportError("version", msg)) = result
  should.be_true(string.contains(msg, "missing"))
}

pub fn separate_fields_invalid_version_error_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "description", value: "Desc"),
    FrontmatterPair(key: "version", value: "banana"),
  ]
  let result = importer.separate_fields(pairs, types.Codex)
  should.be_error(result)
  let assert Error(error.ImportError("version", msg)) = result
  should.be_true(string.contains(msg, "Invalid version"))
}

// ============================================================================
// §4 YAML Generation
// ============================================================================

pub fn generate_skill_yaml_format_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test-skill"),
    FrontmatterPair(key: "description", value: "\"A test skill\""),
    FrontmatterPair(key: "version", value: "1.0.0"),
    FrontmatterPair(key: "license", value: "MIT"),
  ]
  let assert Ok(separated) =
    importer.separate_fields(pairs, types.OpenClaw)
  let yaml = importer.generate_skill_yaml(separated.universal)
  should.be_true(string.contains(yaml, "name: test-skill"))
  should.be_true(string.contains(yaml, "description: \"A test skill\""))
  should.be_true(string.contains(yaml, "version: 1.0.0"))
  should.be_true(string.contains(yaml, "license: MIT"))
}

pub fn generate_skill_yaml_no_license_test() {
  let pairs = [
    FrontmatterPair(key: "name", value: "test"),
    FrontmatterPair(key: "description", value: "Desc"),
    FrontmatterPair(key: "version", value: "1.0.0"),
  ]
  let assert Ok(separated) =
    importer.separate_fields(pairs, types.Codex)
  let yaml = importer.generate_skill_yaml(separated.universal)
  should.be_false(string.contains(yaml, "license"))
}

pub fn generate_metadata_yaml_from_pairs_test() {
  let pairs = [
    FrontmatterPair(key: "user-invocable", value: "true"),
    FrontmatterPair(key: "allowed-tools", value: "[Read, Grep]"),
  ]
  let yaml = importer.generate_metadata_yaml(pairs, None)
  should.be_true(string.contains(yaml, "user-invocable: true"))
  should.be_true(string.contains(yaml, "allowed-tools: [Read, Grep]"))
}

pub fn generate_metadata_yaml_codex_override_test() {
  let codex_content = "interface:\n  display_name: Test\n"
  let yaml =
    importer.generate_metadata_yaml([], Some(codex_content))
  should.equal(yaml, codex_content)
}

// ============================================================================
// §5 Source Resolution
// ============================================================================

pub fn fetch_source_local_directory_test() {
  let assert Ok(resolved) =
    importer.fetch_source("test/fixtures/import-openclaw")
  should.equal(resolved, SourceDirectory("test/fixtures/import-openclaw"))
}

pub fn fetch_source_local_file_test() {
  let assert Ok(resolved) =
    importer.fetch_source("test/fixtures/import-openclaw/SKILL.md")
  // Should be a SourceFile pointing to the file and its parent directory
  case resolved {
    importer.SourceFile(path:, directory:) -> {
      should.equal(path, "test/fixtures/import-openclaw/SKILL.md")
      should.equal(directory, "test/fixtures/import-openclaw")
    }
    importer.SourceDirectory(_) ->
      should.fail()
  }
}

pub fn fetch_source_invalid_url_returns_error_test() {
  let result =
    importer.fetch_source("https://invalid.example.com/nonexistent/SKILL.md")
  should.be_error(result)
  let assert Error(error.ImportError(_, msg)) = result
  should.be_true(string.contains(msg, "Failed to download"))
}

// ============================================================================
// §6 End-to-End Import from Fixtures
// ============================================================================

pub fn import_openclaw_fixture_test() {
  let output_dir = "/tmp/skillc-test-import-oc"
  let _ = simplifile.delete(output_dir)

  let assert Ok(result) =
    importer.import_skill(
      "test/fixtures/import-openclaw",
      None,
      output_dir,
    )

  should.equal(result.provider, types.OpenClaw)
  should.be_true(string.contains(result.skill_yaml, "name: my-imported-skill"))
  should.be_true(string.contains(result.skill_yaml, "version: 2.0.0"))
  should.be_true(string.contains(result.skill_yaml, "license: MIT"))
  should.be_true(string.contains(result.instructions_md, "# my-imported-skill"))
  should.be_true(string.contains(result.metadata_yaml, "emoji"))

  let assert Ok(_) = simplifile.read(output_dir <> "/skill.yaml")
  let assert Ok(_) = simplifile.read(output_dir <> "/INSTRUCTIONS.md")
  let assert Ok(_) =
    simplifile.read(output_dir <> "/providers/openclaw/metadata.yaml")

  let _ = simplifile.delete(output_dir)
  Nil
}

pub fn import_claude_code_fixture_test() {
  let output_dir = "/tmp/skillc-test-import-cc"
  let _ = simplifile.delete(output_dir)

  let assert Ok(result) =
    importer.import_skill(
      "test/fixtures/import-claude-code",
      None,
      output_dir,
    )

  should.equal(result.provider, types.ClaudeCode)
  should.be_true(string.contains(result.skill_yaml, "name: my-imported-skill"))
  should.be_true(string.contains(result.instructions_md, "# my-imported-skill"))
  should.be_true(string.contains(result.metadata_yaml, "user-invocable"))
  should.be_true(string.contains(result.metadata_yaml, "allowed-tools"))

  let assert Ok(_) =
    simplifile.read(output_dir <> "/providers/claude-code/metadata.yaml")

  let _ = simplifile.delete(output_dir)
  Nil
}

pub fn import_codex_fixture_test() {
  let output_dir = "/tmp/skillc-test-import-cdx"
  let _ = simplifile.delete(output_dir)

  let assert Ok(result) =
    importer.import_skill(
      "test/fixtures/import-codex",
      None,
      output_dir,
    )

  should.equal(result.provider, types.Codex)
  should.be_true(string.contains(result.skill_yaml, "name: my-imported-skill"))
  should.be_true(string.contains(result.instructions_md, "# my-imported-skill"))
  should.be_true(string.contains(result.metadata_yaml, "interface"))
  should.be_true(string.contains(result.metadata_yaml, "display_name"))

  let assert Ok(_) =
    simplifile.read(output_dir <> "/providers/codex/metadata.yaml")

  let _ = simplifile.delete(output_dir)
  Nil
}

// ============================================================================
// §7 Roundtrip Tests
// ============================================================================

pub fn roundtrip_openclaw_test() {
  let compile_dir = "/tmp/skillc-roundtrip-compile-oc"
  let import_dir = "/tmp/skillc-roundtrip-import-oc"
  let _ = simplifile.delete(compile_dir)
  let _ = simplifile.delete(import_dir)

  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "openclaw")
  let assert Ok(_) = compiler.emit(compiled, compile_dir, "test-skill")

  let compiled_skill_dir = compile_dir <> "/openclaw/test-skill"
  let assert Ok(result) =
    importer.import_skill(compiled_skill_dir, None, import_dir)

  should.equal(result.provider, types.OpenClaw)
  should.be_true(string.contains(result.skill_yaml, "name: test-skill"))
  should.be_true(string.contains(result.skill_yaml, "version: 1.2.3"))
  should.be_true(string.contains(result.metadata_yaml, "emoji"))

  let _ = simplifile.delete(compile_dir)
  let _ = simplifile.delete(import_dir)
  Nil
}

pub fn roundtrip_claude_code_test() {
  let compile_dir = "/tmp/skillc-roundtrip-compile-cc"
  let import_dir = "/tmp/skillc-roundtrip-import-cc"
  let _ = simplifile.delete(compile_dir)
  let _ = simplifile.delete(import_dir)

  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "claude-code")
  let assert Ok(_) = compiler.emit(compiled, compile_dir, "test-skill")

  let compiled_skill_dir = compile_dir <> "/claude-code/test-skill"
  let assert Ok(result) =
    importer.import_skill(compiled_skill_dir, None, import_dir)

  should.equal(result.provider, types.ClaudeCode)
  should.be_true(string.contains(result.skill_yaml, "name: test-skill"))
  should.be_true(string.contains(result.skill_yaml, "version: 1.2.3"))
  should.be_true(string.contains(result.metadata_yaml, "user-invocable"))

  let _ = simplifile.delete(compile_dir)
  let _ = simplifile.delete(import_dir)
  Nil
}

pub fn roundtrip_codex_test() {
  let compile_dir = "/tmp/skillc-roundtrip-compile-cdx"
  let import_dir = "/tmp/skillc-roundtrip-import-cdx"
  let _ = simplifile.delete(compile_dir)
  let _ = simplifile.delete(import_dir)

  let assert Ok(compiled) =
    compiler.compile("test/fixtures/valid-skill", "codex")
  let assert Ok(_) = compiler.emit(compiled, compile_dir, "test-skill")

  let compiled_skill_dir =
    compile_dir <> "/codex/.agents/skills/test-skill"
  let assert Ok(result) =
    importer.import_skill(compiled_skill_dir, Some(types.Codex), import_dir)

  should.equal(result.provider, types.Codex)
  should.be_true(string.contains(result.skill_yaml, "name: test-skill"))
  should.be_true(string.contains(result.skill_yaml, "version: 1.2.3"))

  let _ = simplifile.delete(compile_dir)
  let _ = simplifile.delete(import_dir)
  Nil
}

// ============================================================================
// §8 Error Cases
// ============================================================================

pub fn import_nonexistent_path_fails_test() {
  let result =
    importer.import_skill(
      "/tmp/nonexistent-import-xyz",
      None,
      "/tmp/out",
    )
  should.be_error(result)
}

pub fn import_no_skill_md_fails_test() {
  let dir = "/tmp/skillc-test-no-skill-md"
  let _ = simplifile.delete(dir)
  let _ = simplifile.create_directory_all(dir)

  let result = importer.import_skill(dir, None, "/tmp/out")
  should.be_error(result)

  let _ = simplifile.delete(dir)
  Nil
}

pub fn import_invalid_frontmatter_fails_test() {
  let dir = "/tmp/skillc-test-invalid-fm"
  let _ = simplifile.delete(dir)
  let _ = simplifile.create_directory_all(dir)
  let _ = simplifile.write(dir <> "/SKILL.md", "No frontmatter here.")

  let result = importer.import_skill(dir, None, "/tmp/out")
  should.be_error(result)

  let _ = simplifile.delete(dir)
  Nil
}

pub fn import_output_dir_already_has_skill_yaml_fails_test() {
  let output_dir = "/tmp/skillc-test-existing-skill"
  let _ = simplifile.delete(output_dir)
  let _ = simplifile.create_directory_all(output_dir)
  let _ = simplifile.write(output_dir <> "/skill.yaml", "name: existing\n")

  let result =
    importer.import_skill(
      "test/fixtures/import-openclaw",
      None,
      output_dir,
    )
  should.be_error(result)
  let assert Error(error.ImportError(_, msg)) = result
  should.be_true(string.contains(msg, "already exists"))

  let _ = simplifile.delete(output_dir)
  Nil
}

pub fn import_with_provider_hint_test() {
  let output_dir = "/tmp/skillc-test-import-hint"
  let _ = simplifile.delete(output_dir)

  let assert Ok(result) =
    importer.import_skill(
      "test/fixtures/import-codex",
      Some(types.Codex),
      output_dir,
    )
  should.equal(result.provider, types.Codex)

  let _ = simplifile.delete(output_dir)
  Nil
}

pub fn import_missing_name_field_fails_test() {
  let dir = "/tmp/skillc-test-missing-name-field"
  let _ = simplifile.delete(dir)
  let _ = simplifile.create_directory_all(dir)
  let _ =
    simplifile.write(
      dir <> "/SKILL.md",
      "---\ndescription: \"A test\"\nversion: 1.0.0\n---\n\nBody.",
    )

  let result = importer.import_skill(dir, Some(types.Codex), "/tmp/out")
  should.be_error(result)
  let assert Error(error.ImportError("name", _)) = result

  let _ = simplifile.delete(dir)
  Nil
}

pub fn import_invalid_version_fails_test() {
  let dir = "/tmp/skillc-test-invalid-version"
  let _ = simplifile.delete(dir)
  let _ = simplifile.create_directory_all(dir)
  let _ =
    simplifile.write(
      dir <> "/SKILL.md",
      "---\nname: test\ndescription: \"A test\"\nversion: not-a-version\n---\n\nBody.",
    )

  let result = importer.import_skill(dir, Some(types.Codex), "/tmp/out")
  should.be_error(result)
  let assert Error(error.ImportError("version", _)) = result

  let _ = simplifile.delete(dir)
  Nil
}
