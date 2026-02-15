import gleam/string
import gleeunit/should
import simplifile
import skillc

// ============================================================================
// §8.1 Version Command
// ============================================================================

pub fn cli_version_test() {
  let assert Ok(output) = skillc.run(["version"])
  should.be_true(string.contains(output, "skill-universe"))
  should.be_true(string.contains(output, "1.1.0"))
}

// ============================================================================
// §8.2 Help Command
// ============================================================================

pub fn cli_help_test() {
  let assert Ok(output) = skillc.run(["help"])
  should.be_true(string.contains(output, "Usage:"))
  should.be_true(string.contains(output, "compile"))
  should.be_true(string.contains(output, "check"))
  should.be_true(string.contains(output, "init"))
}

pub fn cli_help_flag_test() {
  let assert Ok(output) = skillc.run(["--help"])
  should.be_true(string.contains(output, "Usage:"))
}

pub fn cli_unknown_command_test() {
  let result = skillc.run(["unknown"])
  should.be_error(result)
}

// ============================================================================
// §8.3 Compile Command
// ============================================================================

pub fn cli_compile_all_test() {
  let output_dir = "/tmp/skillc-cli-test-compile-all"
  let _ = simplifile.delete(output_dir)

  let assert Ok(output) =
    skillc.run([
      "compile",
      "test/fixtures/valid-skill",
      "--output",
      output_dir,
    ])
  should.be_true(string.contains(output, "Compiled"))
  should.be_true(string.contains(output, "openclaw"))
  should.be_true(string.contains(output, "claude-code"))
  should.be_true(string.contains(output, "codex"))

  let _ = simplifile.delete(output_dir)
  Nil
}

pub fn cli_compile_single_target_test() {
  let output_dir = "/tmp/skillc-cli-test-compile-target"
  let _ = simplifile.delete(output_dir)

  let assert Ok(output) =
    skillc.run([
      "compile",
      "test/fixtures/valid-skill",
      "--target",
      "openclaw",
      "--output",
      output_dir,
    ])
  should.be_true(string.contains(output, "Compiled"))
  should.be_true(string.contains(output, "openclaw"))

  let _ = simplifile.delete(output_dir)
  Nil
}

pub fn cli_compile_providers_flag_test() {
  let output_dir = "/tmp/skillc-cli-test-providers"
  let _ = simplifile.delete(output_dir)

  let assert Ok(output) =
    skillc.run([
      "compile",
      "test/fixtures/valid-skill",
      "--providers",
      "openclaw,codex",
      "--output",
      output_dir,
    ])
  should.be_true(string.contains(output, "openclaw"))
  should.be_true(string.contains(output, "codex"))
  should.be_false(string.contains(output, "claude-code"))

  let _ = simplifile.delete(output_dir)
  Nil
}

pub fn cli_compile_invalid_provider_test() {
  let result =
    skillc.run([
      "compile",
      "test/fixtures/valid-skill",
      "--target",
      "invalid",
    ])
  should.be_error(result)
  let assert Error(msg) = result
  should.be_true(string.contains(msg, "Unknown provider"))
}

pub fn cli_compile_nonexistent_dir_test() {
  let result = skillc.run(["compile", "/tmp/nonexistent-dir-xyz"])
  should.be_error(result)
}

// ============================================================================
// §8.4 Check Command
// ============================================================================

pub fn cli_check_test() {
  let assert Ok(output) = skillc.run(["check", "test/fixtures/valid-skill"])
  should.be_true(string.contains(output, "test-skill"))
  should.be_true(string.contains(output, "v1.2.3"))
  should.be_true(string.contains(output, "openclaw"))
  should.be_true(string.contains(output, "claude-code"))
  should.be_true(string.contains(output, "codex"))
}

pub fn cli_check_minimal_skill_test() {
  let assert Ok(output) = skillc.run(["check", "test/fixtures/minimal-skill"])
  should.be_true(string.contains(output, "minimal"))
  should.be_true(string.contains(output, "openclaw"))
}

pub fn cli_check_nonexistent_dir_test() {
  let result = skillc.run(["check", "/tmp/nonexistent-dir-xyz"])
  should.be_error(result)
  let assert Error(msg) = result
  should.be_true(string.contains(msg, "skill.yaml not found"))
}

pub fn cli_check_invalid_yaml_test() {
  let result = skillc.run(["check", "test/fixtures/invalid-yaml"])
  should.be_error(result)
}

// ============================================================================
// §8.5 Init Command
// ============================================================================

pub fn cli_init_test() {
  let dir = "/tmp/skillc-cli-test-init"
  let _ = simplifile.delete(dir)

  let assert Ok(output) = skillc.run(["init", dir])
  should.be_true(string.contains(output, "Created skill"))

  // Name should be derived from path
  should.be_true(string.contains(output, "skillc-cli-test-init"))

  let _ = simplifile.delete(dir)
  Nil
}

pub fn cli_init_with_name_test() {
  let dir = "/tmp/skillc-cli-test-init-named"
  let _ = simplifile.delete(dir)

  let assert Ok(output) = skillc.run(["init", dir, "--name", "my-cool-skill"])
  should.be_true(string.contains(output, "my-cool-skill"))

  // Verify the name is in skill.yaml
  let assert Ok(content) = simplifile.read(dir <> "/skill.yaml")
  should.be_true(string.contains(content, "name: my-cool-skill"))

  let _ = simplifile.delete(dir)
  Nil
}

pub fn cli_init_already_exists_test() {
  let dir = "/tmp/skillc-cli-test-init-exists"
  let _ = simplifile.delete(dir)

  let assert Ok(_) = skillc.run(["init", dir])
  let result = skillc.run(["init", dir])
  should.be_error(result)
  let assert Error(msg) = result
  should.be_true(string.contains(msg, "already exists"))

  let _ = simplifile.delete(dir)
  Nil
}

// ============================================================================
// §8.6 Name From Path
// ============================================================================

pub fn name_from_path_simple_test() {
  should.equal(skillc.name_from_path("my-skill"), "my-skill")
}

pub fn name_from_path_nested_test() {
  should.equal(skillc.name_from_path("/home/user/my-skill"), "my-skill")
}

pub fn name_from_path_trailing_slash_test() {
  should.equal(skillc.name_from_path("my-skill/"), "my-skill")
}
