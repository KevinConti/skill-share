import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile
import skillc
import skillc/registry
import skillc/shell

// ============================================================================
// Repo URL Parsing
// ============================================================================

pub fn parse_repo_url_ssh_test() {
  let result = registry.parse_repo_url("git@github.com:owner/repo.git")
  should.equal(result, "owner/repo")
}

pub fn parse_repo_url_https_test() {
  let result = registry.parse_repo_url("https://github.com/owner/repo.git")
  should.equal(result, "owner/repo")
}

pub fn parse_repo_url_https_no_git_suffix_test() {
  let result = registry.parse_repo_url("https://github.com/owner/repo")
  should.equal(result, "owner/repo")
}

pub fn parse_repo_url_trailing_slash_test() {
  let result = registry.parse_repo_url("https://github.com/owner/repo/")
  should.equal(result, "owner/repo")
}

pub fn parse_repo_url_with_whitespace_test() {
  let result = registry.parse_repo_url("  git@github.com:owner/repo.git  ")
  should.equal(result, "owner/repo")
}

// ============================================================================
// Install Spec Parsing
// ============================================================================

pub fn parse_install_spec_no_version_test() {
  let #(repo, version) = registry.parse_install_spec("owner/repo")
  should.equal(repo, "owner/repo")
  should.equal(version, None)
}

pub fn parse_install_spec_with_version_test() {
  let #(repo, version) = registry.parse_install_spec("owner/repo@v1.0.0")
  should.equal(repo, "owner/repo")
  should.equal(version, Some("v1.0.0"))
}

pub fn parse_install_spec_with_prerelease_test() {
  let #(repo, version) = registry.parse_install_spec("owner/repo@v1.0.0-beta.1")
  should.equal(repo, "owner/repo")
  should.equal(version, Some("v1.0.0-beta.1"))
}

// ============================================================================
// Shell Exec
// ============================================================================

pub fn shell_exec_success_test() {
  let assert Ok(output) = shell.exec("echo hello")
  should.equal(output, "hello")
}

pub fn shell_exec_failure_test() {
  let result = shell.exec("false")
  should.be_error(result)
}

pub fn shell_exec_nonexistent_command_test() {
  let result = shell.exec("nonexistent_command_xyz_123")
  should.be_error(result)
}

// ============================================================================
// List Installed (Local)
// ============================================================================

pub fn list_installed_empty_dir_test() {
  let dir = "/tmp/skillc-test-list-empty"
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)

  let assert Ok(output) = registry.list_installed(dir)
  should.be_true(string.contains(output, "No skills installed"))

  let _ = simplifile.delete(dir)
  Nil
}

pub fn list_installed_nonexistent_dir_test() {
  let assert Ok(output) =
    registry.list_installed("/tmp/nonexistent-dir-xyz-123")
  should.be_true(string.contains(output, "No skills installed"))
}

pub fn list_installed_with_skills_test() {
  let dir = "/tmp/skillc-test-list-skills"
  let _ = simplifile.delete(dir)

  // Create a fake installed skill structure
  let skill_dir = dir <> "/openclaw/my-skill"
  let assert Ok(_) = simplifile.create_directory_all(skill_dir)
  let assert Ok(_) =
    simplifile.write(skill_dir <> "/SKILL.md", "---\nname: my-skill\n---\n")

  let assert Ok(output) = registry.list_installed(dir)
  should.be_true(string.contains(output, "my-skill"))
  should.be_true(string.contains(output, "openclaw"))

  let _ = simplifile.delete(dir)
  Nil
}

// ============================================================================
// CLI Routing
// ============================================================================

pub fn cli_help_includes_registry_commands_test() {
  let assert Ok(output) = skillc.run(["help"])
  should.be_true(string.contains(output, "publish"))
  should.be_true(string.contains(output, "search"))
  should.be_true(string.contains(output, "install"))
  should.be_true(string.contains(output, "list"))
}

pub fn cli_list_installed_test() {
  let dir = "/tmp/skillc-test-cli-list"
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)

  let assert Ok(output) = skillc.run(["list", "--installed", "--output", dir])
  should.be_true(string.contains(output, "No skills installed"))

  let _ = simplifile.delete(dir)
  Nil
}
