import gleam/option.{type Option}

pub type Skill {
  Skill(
    name: String,
    description: String,
    version: String,
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
  Dependency(name: String, version: String, optional: Bool)
}

pub type ConfigField {
  ConfigField(
    name: String,
    description: String,
    required: Bool,
    secret: Bool,
    default: Option(String),
  )
}

pub type ProviderMeta {
  ProviderMeta(provider_name: String, raw: String)
}

pub type CompiledSkill {
  CompiledSkill(
    provider: String,
    skill_md: String,
    scripts: List(FileCopy),
    assets: List(FileCopy),
  )
}

pub type FileCopy {
  FileCopy(src: String, relative_path: String)
}
