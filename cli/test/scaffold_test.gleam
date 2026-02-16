import gleam/string
import gleeunit/should
import simplifile
import skill_universe/error
import skill_universe/parser
import skill_universe/scaffold

pub fn init_creates_all_files_test() {
  let dir = "/tmp/skill_universe-test-init"
  let _ = simplifile.delete(dir)

  let assert Ok(_) = scaffold.init_skill(dir, "my-skill")

  // Verify all expected files exist
  let assert Ok(True) = simplifile.is_file(dir <> "/skill.yaml")
  let assert Ok(True) = simplifile.is_file(dir <> "/INSTRUCTIONS.md")
  let assert Ok(True) =
    simplifile.is_file(dir <> "/providers/openclaw/metadata.yaml")
  let assert Ok(True) =
    simplifile.is_file(dir <> "/providers/claude-code/metadata.yaml")
  let assert Ok(True) =
    simplifile.is_file(dir <> "/providers/codex/metadata.yaml")

  let _ = simplifile.delete(dir)
  Nil
}

pub fn init_skill_yaml_content_test() {
  let dir = "/tmp/skill_universe-test-init-content"
  let _ = simplifile.delete(dir)

  let assert Ok(_) = scaffold.init_skill(dir, "test-skill")

  let assert Ok(content) = simplifile.read(dir <> "/skill.yaml")
  should.be_true(string.contains(content, "name: test-skill"))
  should.be_true(string.contains(content, "version: 0.1.0"))
  should.be_true(string.contains(content, "description:"))

  let _ = simplifile.delete(dir)
  Nil
}

pub fn init_instructions_content_test() {
  let dir = "/tmp/skill_universe-test-init-instructions"
  let _ = simplifile.delete(dir)

  let assert Ok(_) = scaffold.init_skill(dir, "test-skill")

  let assert Ok(content) = simplifile.read(dir <> "/INSTRUCTIONS.md")
  should.be_true(string.contains(content, "{{name}}"))
  should.be_true(string.contains(content, "{{version}}"))
  should.be_true(string.contains(content, "{{description}}"))

  let _ = simplifile.delete(dir)
  Nil
}

pub fn init_prevents_overwrite_test() {
  let dir = "/tmp/skill_universe-test-init-overwrite"
  let _ = simplifile.delete(dir)

  // First init succeeds
  let assert Ok(_) = scaffold.init_skill(dir, "my-skill")

  // Second init fails (skill.yaml already exists)
  let result = scaffold.init_skill(dir, "my-skill")
  should.be_error(result)
  let assert Error(error.ValidationError("init", msg)) = result
  should.be_true(string.contains(msg, "already exists"))

  let _ = simplifile.delete(dir)
  Nil
}

pub fn init_compilable_test() {
  // The scaffolded skill should pass check (valid skill.yaml + providers)
  let dir = "/tmp/skill_universe-test-init-compilable"
  let _ = simplifile.delete(dir)

  let assert Ok(_) = scaffold.init_skill(dir, "compilable-skill")

  // Verify the generated skill.yaml can be parsed
  let assert Ok(content) = simplifile.read(dir <> "/skill.yaml")
  let assert Ok(_) = parser.parse_skill_yaml(content)

  let _ = simplifile.delete(dir)
  Nil
}
