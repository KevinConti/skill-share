import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import skillc/error.{type SkillError, ParseError, ValidationError}
import skillc/semver
import skillc/types.{
  type ConfigField, type Dependency, type Provider, type Skill,
  type SkillMetadata, ConfigField, Dependency, Optional, OptionalWithDefault,
  Required, Skill, SkillMetadata,
}
import skillc/version_constraint
import yay

pub fn parse_skill_yaml(content: String) -> Result(Skill, SkillError) {
  use docs <- result.try(
    yay.parse_string(content)
    |> result.map_error(fn(e) { yaml_error_to_skill_error("skill.yaml", e) }),
  )
  use doc <- result.try(case docs {
    [first, ..] -> Ok(first)
    [] -> Error(ParseError("skill.yaml", "Empty YAML document"))
  })
  let root = yay.document_root(doc)
  case root {
    yay.NodeNil -> Error(ParseError("skill.yaml", "Empty YAML document"))
    _ -> parse_skill_from_node(root)
  }
}

fn parse_skill_from_node(node: yay.Node) -> Result(Skill, SkillError) {
  use name <- result.try(
    yay.extract_string(node, "name")
    |> result.map_error(fn(_) {
      ValidationError("name", "Required field 'name' is missing")
    }),
  )
  use _ <- result.try(case string.is_empty(string.trim(name)) {
    True -> Error(ValidationError("name", "Field 'name' must not be empty"))
    False -> Ok(Nil)
  })
  use description <- result.try(
    yay.extract_string(node, "description")
    |> result.map_error(fn(_) {
      ValidationError("description", "Required field 'description' is missing")
    }),
  )
  use _ <- result.try(case string.is_empty(string.trim(description)) {
    True ->
      Error(ValidationError(
        "description",
        "Field 'description' must not be empty",
      ))
    False -> Ok(Nil)
  })
  use version_str <- result.try(
    yay.extract_string(node, "version")
    |> result.map_error(fn(_) {
      ValidationError("version", "Required field 'version' is missing")
    }),
  )
  use version <- result.try(semver.parse(version_str))

  let license =
    yay.extract_optional_string(node, "license")
    |> result.unwrap(None)
    |> normalize_optional
  let homepage =
    yay.extract_optional_string(node, "homepage")
    |> result.unwrap(None)
    |> normalize_optional
  let repository =
    yay.extract_optional_string(node, "repository")
    |> result.unwrap(None)
    |> normalize_optional

  let metadata = parse_metadata(node)
  let dependencies = parse_dependencies(node)
  // Check for self-dependency (circular reference to self)
  use _ <- result.try(case list.find(dependencies, fn(d) { d.name == name }) {
    Ok(_) ->
      Error(ValidationError(
        "dependencies",
        "Skill cannot depend on itself: " <> name,
      ))
    Error(_) -> Ok(Nil)
  })
  use dependencies <- result.try(check_unique_names(
    dependencies,
    fn(d: Dependency) { d.name },
    "dependencies",
    "dependency",
  ))
  let config = parse_config(node)
  use config <- result.try(check_unique_names(
    config,
    fn(c: ConfigField) { c.name },
    "config",
    "config field",
  ))

  Ok(Skill(
    name: name,
    description: description,
    version: version,
    license: license,
    homepage: homepage,
    repository: repository,
    metadata: metadata,
    dependencies: dependencies,
    config: config,
  ))
}

fn normalize_optional(opt: Option(String)) -> Option(String) {
  case opt {
    Some("") -> None
    other -> other
  }
}

fn parse_metadata(node: yay.Node) -> option.Option(SkillMetadata) {
  case yay.select_sugar(from: node, selector: "metadata") {
    Ok(_meta_node) -> {
      let author =
        yay.extract_optional_string(node, "metadata.author")
        |> result.unwrap(None)
      let author_email =
        yay.extract_optional_string(node, "metadata.author_email")
        |> result.unwrap(None)
      let tags =
        yay.extract_string_list(node, "metadata.tags")
        |> result.unwrap([])
      Some(SkillMetadata(author: author, author_email: author_email, tags: tags))
    }
    Error(_) -> None
  }
}

fn parse_dependencies(node: yay.Node) -> List(Dependency) {
  case yay.select_sugar(from: node, selector: "dependencies") {
    Ok(yay.NodeSeq(items)) ->
      list.filter_map(items, fn(item) {
        case yay.extract_string(item, "name") {
          Ok(name) -> {
            case string.is_empty(string.trim(name)) {
              True -> Error(Nil)
              False -> {
                let version_str =
                  yay.extract_string(item, "version")
                  |> result.unwrap("*")
                case version_constraint.parse(version_str) {
                  Ok(version) -> {
                    let optional =
                      yay.extract_bool_or(item, "optional", False)
                      |> result.unwrap(False)
                    Ok(Dependency(
                      name: name,
                      version: version,
                      optional: optional,
                    ))
                  }
                  // Skip dependencies with invalid version constraints
                  Error(_) -> Error(Nil)
                }
              }
            }
          }
          Error(_) -> Error(Nil)
        }
      })
    _ -> []
  }
}

fn parse_config(node: yay.Node) -> List(ConfigField) {
  case yay.select_sugar(from: node, selector: "config") {
    Ok(yay.NodeSeq(items)) ->
      list.filter_map(items, fn(item) {
        case yay.extract_string(item, "name") {
          Ok(name) -> {
            case string.is_empty(string.trim(name)) {
              True -> Error(Nil)
              False -> {
                let description =
                  yay.extract_string(item, "description") |> result.unwrap("")
                let required =
                  yay.extract_bool_or(item, "required", False)
                  |> result.unwrap(False)
                let secret =
                  yay.extract_bool_or(item, "secret", False)
                  |> result.unwrap(False)
                let default =
                  yay.extract_optional_string(item, "default")
                  |> result.unwrap(None)
                let requirement = case required {
                  True -> Required
                  False ->
                    case default {
                      Some(d) -> OptionalWithDefault(d)
                      None -> Optional
                    }
                }
                Ok(ConfigField(
                  name: name,
                  description: description,
                  requirement: requirement,
                  secret: secret,
                ))
              }
            }
          }
          Error(_) -> Error(Nil)
        }
      })
    _ -> []
  }
}

fn check_unique_names(
  items: List(a),
  get_name: fn(a) -> String,
  field: String,
  label: String,
) -> Result(List(a), SkillError) {
  do_check_unique_names(items, get_name, field, label, [])
}

fn do_check_unique_names(
  items: List(a),
  get_name: fn(a) -> String,
  field: String,
  label: String,
  seen: List(String),
) -> Result(List(a), SkillError) {
  case items {
    [] -> Ok(items)
    [first, ..rest] -> {
      let name = get_name(first)
      case list.contains(seen, name) {
        True ->
          Error(ValidationError(field, "Duplicate " <> label <> ": " <> name))
        False -> {
          use _ <- result.try(
            do_check_unique_names(rest, get_name, field, label, [name, ..seen]),
          )
          Ok(items)
        }
      }
    }
  }
}

pub fn parse_metadata_yaml(
  content: String,
  provider: Provider,
) -> Result(yay.Node, SkillError) {
  let provider_name = types.provider_to_string(provider)
  let file = "providers/" <> provider_name <> "/metadata.yaml"
  use docs <- result.try(
    yay.parse_string(content)
    |> result.map_error(fn(e) { yaml_error_to_skill_error(file, e) }),
  )
  case docs {
    [first, ..] -> Ok(yay.document_root(first))
    [] -> Error(ParseError(file, "Empty YAML document"))
  }
}

pub fn has_frontmatter(content: String) -> Bool {
  string.starts_with(string.trim_start(content), "---")
}

fn yaml_error_to_skill_error(file: String, err: yay.YamlError) -> SkillError {
  case err {
    yay.ParsingError(msg, _loc) -> ParseError(file, msg)
    yay.UnexpectedParsingError -> ParseError(file, "Unexpected parsing error")
  }
}
