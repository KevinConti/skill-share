import gleam/option.{type Option}
import skill_universe/semver.{type SemVer}
import skill_universe/version_constraint.{type VersionConstraint}

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
    name: String,
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
