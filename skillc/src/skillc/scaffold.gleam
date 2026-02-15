import simplifile
import skillc/error.{type SkillError, FileError, ValidationError}

pub fn init_skill(skill_dir: String, name: String) -> Result(Nil, SkillError) {
  // Guard against overwriting existing skills
  case simplifile.is_file(skill_dir <> "/skill.yaml") {
    Ok(True) ->
      Error(ValidationError(
        "init",
        "skill.yaml already exists in " <> skill_dir,
      ))
    _ -> do_init(skill_dir, name)
  }
}

fn do_init(skill_dir: String, name: String) -> Result(Nil, SkillError) {
  use _ <- try_write_dir(skill_dir)
  use _ <- try_write_dir(skill_dir <> "/providers")
  use _ <- try_write_dir(skill_dir <> "/providers/openclaw")
  use _ <- try_write_dir(skill_dir <> "/providers/claude-code")
  use _ <- try_write_dir(skill_dir <> "/providers/codex")

  use _ <- try_write_file(skill_dir <> "/skill.yaml", skill_yaml_template(name))
  use _ <- try_write_file(
    skill_dir <> "/INSTRUCTIONS.md",
    instructions_template(),
  )
  use _ <- try_write_file(
    skill_dir <> "/providers/openclaw/metadata.yaml",
    openclaw_metadata_template(),
  )
  use _ <- try_write_file(
    skill_dir <> "/providers/claude-code/metadata.yaml",
    claude_code_metadata_template(),
  )
  use _ <- try_write_file(
    skill_dir <> "/providers/codex/metadata.yaml",
    codex_metadata_template(),
  )

  Ok(Nil)
}

fn try_write_dir(
  path: String,
  next: fn(Nil) -> Result(Nil, SkillError),
) -> Result(Nil, SkillError) {
  case simplifile.create_directory_all(path) {
    Ok(_) -> next(Nil)
    Error(e) -> Error(FileError(path, e))
  }
}

fn try_write_file(
  path: String,
  content: String,
  next: fn(Nil) -> Result(Nil, SkillError),
) -> Result(Nil, SkillError) {
  case simplifile.write(path, content) {
    Ok(_) -> next(Nil)
    Error(e) -> Error(FileError(path, e))
  }
}

fn skill_yaml_template(name: String) -> String {
  "name: " <> name <> "
description: Describe what this skill does
version: 0.1.0

metadata:
  author: Your Name
  tags: []

dependencies: []

config: []
"
}

fn instructions_template() -> String {
  "# {{name}} v{{version}}

{{description}}

## When to Use

Describe when this skill should be triggered.

## Steps

1. Step one
2. Step two
"
}

fn openclaw_metadata_template() -> String {
  "emoji: \"\"
category: general
"
}

fn claude_code_metadata_template() -> String {
  "user-invocable: true
"
}

fn codex_metadata_template() -> String {
  "interface:
  display_name: \"\"
  short_description: \"\"
"
}
