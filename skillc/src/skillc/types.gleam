import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import skillc/semver.{type SemVer}
import skillc/version_constraint.{type VersionConstraint}

pub type Provider {
  OpenClaw
  ClaudeCode
  Codex
}

pub fn provider_from_string(s: String) -> Result(Provider, Nil) {
  case s {
    "openclaw" -> Ok(OpenClaw)
    "claude-code" -> Ok(ClaudeCode)
    "codex" -> Ok(Codex)
    _ -> Error(Nil)
  }
}

pub fn all_provider_names() -> String {
  "openclaw, claude-code, codex"
}

pub fn provider_to_string(provider: Provider) -> String {
  case provider {
    OpenClaw -> "openclaw"
    ClaudeCode -> "claude-code"
    Codex -> "codex"
  }
}

pub type ConfigRequirement {
  Required
  Optional
  OptionalWithDefault(String)
}

pub type Skill {
  Skill(
    name: String,
    description: String,
    version: SemVer,
    license: Option(String),
    homepage: Option(String),
    repository: Option(String),
    metadata: Option(SkillMetadata),
    dependencies: List(Dependency),
    config: List(ConfigField),
  )
}

pub type SkillMetadata {
  SkillMetadata(
    author: Option(String),
    author_email: Option(String),
    tags: List(String),
  )
}

pub type Dependency {
  Dependency(name: String, version: VersionConstraint, optional: Bool)
}

pub type ConfigField {
  ConfigField(
    name: String,
    description: String,
    requirement: ConfigRequirement,
    secret: Bool,
  )
}

pub type CompileWarning {
  FrontmatterInInstructions(file: String)
  MissingDependency(dependency: Dependency)
}

pub type CompiledSkill {
  CompiledSkill(
    provider: Provider,
    skill_md: String,
    scripts: List(FileCopy),
    assets: List(FileCopy),
    warnings: List(CompileWarning),
    codex_yaml: Option(String),
  )
}

pub type FileCopy {
  FileCopy(src: String, relative_path: String)
}

pub fn extract_name(compiled: CompiledSkill) -> String {
  let lines = string.split(compiled.skill_md, "\n")
  list.find_map(lines, fn(line) {
    case string.starts_with(line, "name: ") {
      True -> {
        let name = string.drop_start(line, 6)
        let name = case
          string.starts_with(name, "\""),
          string.ends_with(name, "\"")
        {
          True, True -> name |> string.drop_start(1) |> string.drop_end(1)
          _, _ -> name
        }
        Ok(name)
      }
      False -> Error(Nil)
    }
  })
  |> result.unwrap("skill")
}
