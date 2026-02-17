import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import skill_universe/semver.{type SemVer}
import skill_universe/version_constraint.{type VersionConstraint}

pub type Provider {
  OpenClaw
  ClaudeCode
  Codex
}

pub type ProviderParseError {
  UnknownProviderName(input: String)
}

pub fn provider_from_string(s: String) -> Result(Provider, ProviderParseError) {
  case s {
    "openclaw" -> Ok(OpenClaw)
    "claude-code" -> Ok(ClaudeCode)
    "codex" -> Ok(Codex)
    _ -> Error(UnknownProviderName(input: s))
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

pub fn provider_parse_error_input(error: ProviderParseError) -> String {
  case error {
    UnknownProviderName(input:) -> input
  }
}

pub type DomainStringError {
  EmptyString(field: String)
  SurroundingWhitespace(field: String, value: String)
}

pub opaque type SkillName {
  SkillName(String)
}

pub fn parse_skill_name(raw: String) -> Result(SkillName, DomainStringError) {
  use value <- result.try(validate_non_empty_trimmed("name", raw))
  Ok(SkillName(value))
}

pub fn skill_name_value(value: SkillName) -> String {
  let SkillName(raw) = value
  raw
}

pub opaque type SkillDescription {
  SkillDescription(String)
}

pub fn parse_skill_description(
  raw: String,
) -> Result(SkillDescription, DomainStringError) {
  use value <- result.try(validate_non_empty_trimmed("description", raw))
  Ok(SkillDescription(value))
}

pub fn skill_description_value(value: SkillDescription) -> String {
  let SkillDescription(raw) = value
  raw
}

pub opaque type DependencyName {
  DependencyName(String)
}

pub fn parse_dependency_name(
  raw: String,
) -> Result(DependencyName, DomainStringError) {
  use value <- result.try(validate_non_empty_trimmed("dependency", raw))
  Ok(DependencyName(value))
}

pub fn dependency_name_value(value: DependencyName) -> String {
  let DependencyName(raw) = value
  raw
}

pub opaque type ConfigFieldName {
  ConfigFieldName(String)
}

pub fn parse_config_field_name(
  raw: String,
) -> Result(ConfigFieldName, DomainStringError) {
  use value <- result.try(validate_non_empty_trimmed("config", raw))
  Ok(ConfigFieldName(value))
}

pub fn config_field_name_value(value: ConfigFieldName) -> String {
  let ConfigFieldName(raw) = value
  raw
}

pub opaque type ConfigFieldDescription {
  ConfigFieldDescription(String)
}

pub fn config_field_description(raw: String) -> ConfigFieldDescription {
  ConfigFieldDescription(raw)
}

pub fn config_field_description_value(value: ConfigFieldDescription) -> String {
  let ConfigFieldDescription(raw) = value
  raw
}

pub opaque type SourcePath {
  SourcePath(String)
}

pub fn parse_source_path(raw: String) -> Result(SourcePath, DomainStringError) {
  use value <- result.try(validate_non_empty("source path", raw))
  Ok(SourcePath(value))
}

pub fn source_path_value(value: SourcePath) -> String {
  let SourcePath(raw) = value
  raw
}

pub type RelativePathError {
  EmptyRelativePath
  AbsoluteRelativePath(value: String)
  ParentTraversalRelativePath(value: String)
  InvalidRelativePathSegment(value: String)
}

pub opaque type RelativePath {
  RelativePath(String)
}

pub fn parse_relative_path(
  raw: String,
) -> Result(RelativePath, RelativePathError) {
  let normalized =
    raw
    |> string.replace("\\", "/")
    |> string.trim
  case normalized {
    "" -> Error(EmptyRelativePath)
    _ ->
      case string.starts_with(normalized, "/") {
        True -> Error(AbsoluteRelativePath(value: normalized))
        False -> validate_relative_path_segments(normalized)
      }
  }
}

fn validate_relative_path_segments(
  normalized: String,
) -> Result(RelativePath, RelativePathError) {
  let segments = string.split(normalized, "/")
  case list.find(segments, fn(segment) { segment == ".." }) {
    Ok(_) -> Error(ParentTraversalRelativePath(value: normalized))
    Error(_) ->
      case
        list.find(segments, fn(segment) {
          segment == ""
          || segment == "."
          || string.trim(segment) != segment
          || string.contains(segment, ":")
        })
      {
        Ok(_) -> Error(InvalidRelativePathSegment(value: normalized))
        Error(_) -> Ok(RelativePath(string.join(segments, "/")))
      }
  }
}

pub fn relative_path_value(value: RelativePath) -> String {
  let RelativePath(raw) = value
  raw
}

fn validate_non_empty_trimmed(
  field: String,
  raw: String,
) -> Result(String, DomainStringError) {
  let trimmed = string.trim(raw)
  case trimmed {
    "" -> Error(EmptyString(field: field))
    _ ->
      case trimmed == raw {
        True -> Ok(raw)
        False -> Error(SurroundingWhitespace(field: field, value: raw))
      }
  }
}

fn validate_non_empty(
  field: String,
  raw: String,
) -> Result(String, DomainStringError) {
  case string.trim(raw) {
    "" -> Error(EmptyString(field: field))
    _ -> Ok(raw)
  }
}

pub type ConfigRequirement {
  Required
  Optional
  OptionalWithDefault(String)
}

pub type Skill {
  Skill(
    name: SkillName,
    description: SkillDescription,
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

pub type DependencyRequirement {
  RequiredDependency
  OptionalDependency
}

pub type Dependency {
  Dependency(
    name: DependencyName,
    version: VersionConstraint,
    requirement: DependencyRequirement,
  )
}

pub fn dependency_requirement_from_optional(
  optional: Bool,
) -> DependencyRequirement {
  case optional {
    True -> OptionalDependency
    False -> RequiredDependency
  }
}

pub fn dependency_requirement_is_optional(
  requirement: DependencyRequirement,
) -> Bool {
  case requirement {
    OptionalDependency -> True
    RequiredDependency -> False
  }
}

pub type ConfigField {
  ConfigField(
    name: ConfigFieldName,
    description: ConfigFieldDescription,
    requirement: ConfigRequirement,
    secret: Bool,
  )
}

pub type CompileWarning {
  FrontmatterInInstructions(file: String)
  MissingDependency(dependency: Dependency)
}

pub type CompiledSkill {
  OpenClawCompiled(
    name: SkillName,
    skill_md: String,
    scripts: List(FileCopy),
    assets: List(FileCopy),
    warnings: List(CompileWarning),
  )
  ClaudeCodeCompiled(
    name: SkillName,
    skill_md: String,
    scripts: List(FileCopy),
    assets: List(FileCopy),
    warnings: List(CompileWarning),
  )
  CodexCompiled(
    name: SkillName,
    skill_md: String,
    scripts: List(FileCopy),
    assets: List(FileCopy),
    warnings: List(CompileWarning),
    codex_yaml: String,
  )
}

pub fn compiled_name(compiled: CompiledSkill) -> String {
  case compiled {
    OpenClawCompiled(name:, ..) -> skill_name_value(name)
    ClaudeCodeCompiled(name:, ..) -> skill_name_value(name)
    CodexCompiled(name:, ..) -> skill_name_value(name)
  }
}

pub fn compiled_provider(compiled: CompiledSkill) -> Provider {
  case compiled {
    OpenClawCompiled(..) -> OpenClaw
    ClaudeCodeCompiled(..) -> ClaudeCode
    CodexCompiled(..) -> Codex
  }
}

pub fn compiled_skill_md(compiled: CompiledSkill) -> String {
  case compiled {
    OpenClawCompiled(skill_md:, ..) -> skill_md
    ClaudeCodeCompiled(skill_md:, ..) -> skill_md
    CodexCompiled(skill_md:, ..) -> skill_md
  }
}

pub fn compiled_scripts(compiled: CompiledSkill) -> List(FileCopy) {
  case compiled {
    OpenClawCompiled(scripts:, ..) -> scripts
    ClaudeCodeCompiled(scripts:, ..) -> scripts
    CodexCompiled(scripts:, ..) -> scripts
  }
}

pub fn compiled_assets(compiled: CompiledSkill) -> List(FileCopy) {
  case compiled {
    OpenClawCompiled(assets:, ..) -> assets
    ClaudeCodeCompiled(assets:, ..) -> assets
    CodexCompiled(assets:, ..) -> assets
  }
}

pub fn compiled_warnings(compiled: CompiledSkill) -> List(CompileWarning) {
  case compiled {
    OpenClawCompiled(warnings:, ..) -> warnings
    ClaudeCodeCompiled(warnings:, ..) -> warnings
    CodexCompiled(warnings:, ..) -> warnings
  }
}

pub fn compiled_codex_yaml(compiled: CompiledSkill) -> Option(String) {
  case compiled {
    CodexCompiled(codex_yaml:, ..) -> Some(codex_yaml)
    OpenClawCompiled(..) | ClaudeCodeCompiled(..) -> None
  }
}

pub type FileCopy {
  FileCopy(src: SourcePath, relative_path: RelativePath)
}

pub fn file_copy_src(file: FileCopy) -> String {
  source_path_value(file.src)
}

pub fn file_copy_relative_path(file: FileCopy) -> String {
  relative_path_value(file.relative_path)
}
