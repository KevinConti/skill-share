import gleam/string
import gleeunit/should
import skill_universe/default_output
import skill_universe/platform

pub fn resolve_root_uses_home_on_unix_test() {
  let assert Ok(root) =
    default_output.resolve_root_with(platform.MacOS, fn(var_name) {
      should.equal(var_name, "HOME")
      Ok("/Users/alex")
    })

  should.equal(
    default_output.output_root_value(root),
    "/Users/alex/.skill-universe",
  )
}

pub fn resolve_root_uses_userprofile_on_windows_test() {
  let assert Ok(root) =
    default_output.resolve_root_with(platform.Windows, fn(var_name) {
      should.equal(var_name, "USERPROFILE")
      Ok("C:\\Users\\alex\\")
    })

  should.equal(
    default_output.output_root_value(root),
    "C:/Users/alex/.skill-universe",
  )
}

pub fn resolve_root_returns_missing_env_error_test() {
  let result =
    default_output.resolve_root_with(platform.Linux, fn(_) { Error(Nil) })
  let assert Error(default_output.MissingHomeEnv(var_name: var_name)) = result
  should.equal(var_name, "HOME")
}

pub fn resolve_root_returns_empty_env_error_test() {
  let result =
    default_output.resolve_root_with(platform.Linux, fn(_) { Ok("   ") })
  let assert Error(default_output.EmptyHomeEnv(var_name: var_name)) = result
  should.equal(var_name, "HOME")
}

pub fn import_output_dir_derives_name_from_path_test() {
  let assert Ok(root) =
    default_output.resolve_root_with(platform.Linux, fn(_) { Ok("/tmp/home") })

  let assert Ok(target_dir) =
    default_output.import_output_dir_with_root(
      "owner/repo/path/to/My Skill@v1.2.3",
      root,
    )

  should.equal(
    default_output.import_target_dir_value(target_dir),
    "/tmp/home/.skill-universe/imports/my-skill",
  )
}

pub fn import_output_dir_uses_parent_for_skill_md_source_test() {
  let assert Ok(root) =
    default_output.resolve_root_with(platform.Linux, fn(_) { Ok("/tmp/home") })

  let assert Ok(target_dir) =
    default_output.import_output_dir_with_root(
      "https://github.com/acme/repo/blob/main/skills/demo/SKILL.md",
      root,
    )

  should.equal(
    default_output.import_target_dir_value(target_dir),
    "/tmp/home/.skill-universe/imports/demo",
  )
}

pub fn import_output_dir_falls_back_when_name_is_empty_test() {
  let assert Ok(root) =
    default_output.resolve_root_with(platform.Linux, fn(_) { Ok("/tmp/home") })

  let assert Ok(target_dir) =
    default_output.import_output_dir_with_root("%%%@@@", root)

  should.equal(
    default_output.import_target_dir_value(target_dir),
    "/tmp/home/.skill-universe/imports/imported-skill",
  )
}

pub fn default_output_error_messages_include_hint_test() {
  let msg =
    default_output.error_to_message(default_output.MissingHomeEnv(
      var_name: "HOME",
    ))
  should.be_true(string.contains(msg, "--output"))
}
