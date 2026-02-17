import gleam/list
import gleam/string
import skill_universe/types.{
  type ConfigField, type ConfigFieldName, type Skill, type SkillName, Optional,
  OptionalWithDefault, Required, config_field_description_value,
  config_field_name_value, skill_name_value,
}

pub type ConfigStatus {
  Provided(field: ConfigField, value: String)
  MissingRequired(field: ConfigField)
  DefaultUsed(field: ConfigField, default: String)
  Skipped(field: ConfigField)
}

/// Generate a .env-format template for a skill's configuration fields.
pub fn generate_template(skill: Skill) -> String {
  case skill.config {
    [] ->
      "# No configuration fields defined for "
      <> skill_name_value(skill.name)
      <> "\n"
    fields -> {
      let header =
        "# Configuration for "
        <> skill_name_value(skill.name)
        <> "\n"
        <> "# Set these environment variables before using the skill.\n\n"
      let lines =
        list.map(fields, fn(field) {
          let comment =
            "# " <> config_field_description_value(field.description) <> "\n"
          let req_comment = case field.requirement {
            Required -> "# Required\n"
            Optional -> "# Optional\n"
            OptionalWithDefault(d) -> "# Optional (default: " <> d <> ")\n"
          }
          let secret_comment = case field.secret {
            True -> "# Secret: yes\n"
            False -> ""
          }
          let env_name = config_env_name(skill.name, field.name)
          let default_value = case field.requirement {
            OptionalWithDefault(d) -> d
            _ -> ""
          }
          comment
          <> req_comment
          <> secret_comment
          <> env_name
          <> "="
          <> default_value
          <> "\n"
        })
      header <> string.join(lines, "\n")
    }
  }
}

/// Check configuration status using real environment variables.
pub fn check(skill: Skill) -> List(ConfigStatus) {
  check_with_lookup(skill, get_env)
}

/// Check configuration status using an injectable lookup function.
pub fn check_with_lookup(
  skill: Skill,
  lookup: fn(String) -> Result(String, Nil),
) -> List(ConfigStatus) {
  list.map(skill.config, fn(field) {
    let env_name = config_env_name(skill.name, field.name)
    case lookup(env_name) {
      Ok(value) if value != "" -> Provided(field: field, value: value)
      _ ->
        case field.requirement {
          Required -> MissingRequired(field: field)
          Optional -> Skipped(field: field)
          OptionalWithDefault(d) -> DefaultUsed(field: field, default: d)
        }
    }
  })
}

fn config_env_name(skill_name: SkillName, field_name: ConfigFieldName) -> String {
  "SKILL_CONFIG_"
  <> to_upper_snake(skill_name_value(skill_name))
  <> "_"
  <> to_upper_snake(config_field_name_value(field_name))
}

fn to_upper_snake(s: String) -> String {
  s
  |> string.replace("-", "_")
  |> string.replace(".", "_")
  |> string.uppercase()
}

@external(javascript, "../skill_universe_ffi.mjs", "get_env")
fn get_env(name: String) -> Result(String, Nil)
