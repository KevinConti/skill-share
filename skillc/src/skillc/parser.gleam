import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import skillc/error.{type SkillError, ParseError, ValidationError}
import skillc/types.{
  type ConfigField, type Dependency, type Skill, type SkillMetadata, ConfigField,
  Dependency, Skill, SkillMetadata,
}
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
  use description <- result.try(
    yay.extract_string(node, "description")
    |> result.map_error(fn(_) {
      ValidationError("description", "Required field 'description' is missing")
    }),
  )
  use version <- result.try(
    yay.extract_string(node, "version")
    |> result.map_error(fn(_) {
      ValidationError("version", "Required field 'version' is missing")
    }),
  )
  use _ <- result.try(validate_semver(version))

  let license = yay.extract_optional_string(node, "license") |> result.unwrap(None)
  let homepage =
    yay.extract_optional_string(node, "homepage") |> result.unwrap(None)
  let repository =
    yay.extract_optional_string(node, "repository") |> result.unwrap(None)

  let metadata = parse_metadata(node)
  let dependencies = parse_dependencies(node)
  let config = parse_config(node)

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
      Some(SkillMetadata(
        author: author,
        author_email: author_email,
        tags: tags,
      ))
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
            let version =
              yay.extract_string(item, "version") |> result.unwrap("*")
            let optional =
              yay.extract_bool_or(item, "optional", False)
              |> result.unwrap(False)
            Ok(Dependency(name: name, version: version, optional: optional))
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
            Ok(ConfigField(
              name: name,
              description: description,
              required: required,
              secret: secret,
              default: default,
            ))
          }
          Error(_) -> Error(Nil)
        }
      })
    _ -> []
  }
}

pub fn parse_metadata_yaml(
  content: String,
  provider_name: String,
) -> Result(yay.Node, SkillError) {
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

pub fn validate_semver(version: String) -> Result(Nil, SkillError) {
  // Strip pre-release and build metadata before splitting
  let base = case string.split_once(version, "-") {
    Ok(#(base, _)) -> base
    Error(_) ->
      case string.split_once(version, "+") {
        Ok(#(base, _)) -> base
        Error(_) -> version
      }
  }
  let parts = string.split(base, ".")
  case parts {
    [major, minor, patch] -> {
      case is_numeric(major), is_numeric(minor), is_numeric(patch) {
        True, True, True -> Ok(Nil)
        _, _, _ ->
          Error(ValidationError(
            "version",
            "Invalid semver format: " <> version,
          ))
      }
    }
    _ ->
      Error(ValidationError("version", "Invalid semver format: " <> version))
  }
}

fn is_numeric(s: String) -> Bool {
  case s {
    "" -> False
    _ ->
      string.to_graphemes(s)
      |> list.all(fn(c) {
        c == "0"
        || c == "1"
        || c == "2"
        || c == "3"
        || c == "4"
        || c == "5"
        || c == "6"
        || c == "7"
        || c == "8"
        || c == "9"
      })
  }
}

fn yaml_error_to_skill_error(file: String, err: yay.YamlError) -> SkillError {
  case err {
    yay.ParsingError(msg, _loc) -> ParseError(file, msg)
    yay.UnexpectedParsingError -> ParseError(file, "Unexpected parsing error")
  }
}
