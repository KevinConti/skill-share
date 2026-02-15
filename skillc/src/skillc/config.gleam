import gleam/list
import gleam/string
import skillc/types.{
  type ConfigField, type Skill, Optional, OptionalWithDefault, Required,
}

pub type ConfigStatus {
  Satisfied(field: ConfigField, value: String)
  Missing(field: ConfigField)
}

/// Generate a .env-format template for a skill's configuration fields.
pub fn generate_template(skill: Skill) -> String {
  case skill.config {
    [] -> "# No configuration fields defined for " <> skill.name <> "\n"
    fields -> {
      let header =
        "# Configuration for " <> skill.name <> "\n"
        <> "# Set these environment variables before using the skill.\n\n"
      let lines =
        list.map(fields, fn(field) {
          let comment = "# " <> field.description <> "\n"
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
      Ok(value) if value != "" -> Satisfied(field: field, value: value)
      _ ->
        case field.requirement {
          Required -> Missing(field: field)
          Optional -> Satisfied(field: field, value: "")
          OptionalWithDefault(d) -> Satisfied(field: field, value: d)
        }
    }
  })
}

fn config_env_name(skill_name: String, field_name: String) -> String {
  "SKILL_CONFIG_"
  <> to_upper_snake(skill_name)
  <> "_"
  <> to_upper_snake(field_name)
}

fn to_upper_snake(s: String) -> String {
  s
  |> string.replace("-", "_")
  |> string.replace(".", "_")
  |> string.uppercase()
}

@external(javascript, "../skillc_ffi.mjs", "get_env")
fn get_env(name: String) -> Result(String, Nil)
