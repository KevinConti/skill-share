import gleam/list
import gleam/result
import gleam/string
import skill_universe/path
import skill_universe/platform

pub opaque type OutputRoot {
  OutputRoot(String)
}

pub opaque type ImportTargetDir {
  ImportTargetDir(String)
}

pub type DefaultOutputError {
  MissingHomeEnv(var_name: String)
  EmptyHomeEnv(var_name: String)
  InvalidDerivedImportName(source: String)
}

pub fn resolve_root() -> Result(OutputRoot, DefaultOutputError) {
  resolve_root_with(platform.detect(), get_env)
}

pub fn resolve_root_with(
  detected_platform: platform.Platform,
  lookup_env: fn(String) -> Result(String, Nil),
) -> Result(OutputRoot, DefaultOutputError) {
  let env_name = home_env_name(detected_platform)
  use home <- result.try(case lookup_env(env_name) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(MissingHomeEnv(var_name: env_name))
  })

  let trimmed = string.trim(home)
  case trimmed {
    "" -> Error(EmptyHomeEnv(var_name: env_name))
    _ -> {
      let normalized_home =
        trimmed
        |> path.normalize_separators
        |> trim_trailing_slashes
      Ok(OutputRoot(output_root_path(normalized_home)))
    }
  }
}

pub fn output_root_value(root: OutputRoot) -> String {
  let OutputRoot(raw) = root
  raw
}

pub fn compile_output_dir() -> Result(String, DefaultOutputError) {
  resolve_root()
  |> result.map(output_root_value)
}

pub fn install_output_dir() -> Result(String, DefaultOutputError) {
  resolve_root()
  |> result.map(output_root_value)
}

pub fn list_output_dir() -> Result(String, DefaultOutputError) {
  resolve_root()
  |> result.map(output_root_value)
}

pub fn import_output_dir(source: String) -> Result(String, DefaultOutputError) {
  use root <- result.try(resolve_root())
  use target <- result.try(import_output_dir_with_root(source, root))
  Ok(import_target_dir_value(target))
}

pub fn import_output_dir_with_root(
  source: String,
  root: OutputRoot,
) -> Result(ImportTargetDir, DefaultOutputError) {
  use name <- result.try(derive_import_name(source))
  let root_path = output_root_value(root)
  Ok(ImportTargetDir(root_path <> "/imports/" <> name))
}

pub fn import_target_dir_value(target_dir: ImportTargetDir) -> String {
  let ImportTargetDir(raw) = target_dir
  raw
}

pub fn error_to_message(error: DefaultOutputError) -> String {
  case error {
    MissingHomeEnv(var_name:) ->
      "could not resolve default output directory because "
      <> var_name
      <> " is not set. Use --output <dir>."
    EmptyHomeEnv(var_name:) ->
      "could not resolve default output directory because "
      <> var_name
      <> " is empty. Use --output <dir>."
    InvalidDerivedImportName(source:) ->
      "could not derive a default import directory from '"
      <> source
      <> "'. Use --output <dir>."
  }
}

fn home_env_name(detected_platform: platform.Platform) -> String {
  case detected_platform {
    platform.Windows -> "USERPROFILE"
    _ -> "HOME"
  }
}

fn output_root_path(home: String) -> String {
  case home {
    "/" -> "/.skill-universe"
    _ -> home <> "/.skill-universe"
  }
}

fn trim_trailing_slashes(value: String) -> String {
  case value {
    "/" -> "/"
    _ ->
      case string.ends_with(value, "/") {
        True -> trim_trailing_slashes(string.drop_end(value, 1))
        False -> value
      }
  }
}

fn derive_import_name(source: String) -> Result(String, DefaultOutputError) {
  let base =
    source
    |> string.trim
    |> path.normalize_separators
    |> strip_suffix_after("#")
    |> strip_suffix_after("?")
    |> strip_suffix_after("@")
    |> trim_trailing_slashes
    |> infer_import_basename

  let sanitized = sanitize_import_name(base)
  let name = case sanitized {
    "" -> "imported-skill"
    _ -> sanitized
  }

  case is_valid_import_name(name) {
    True -> Ok(name)
    False -> Error(InvalidDerivedImportName(source: source))
  }
}

fn strip_suffix_after(value: String, delimiter: String) -> String {
  case string.split_once(value, delimiter) {
    Ok(#(left, _)) -> left
    Error(_) -> value
  }
}

fn infer_import_basename(source: String) -> String {
  case source {
    "" -> ""
    _ -> {
      let basename = path.basename(source)
      case string.lowercase(basename) == "skill.md" {
        True -> {
          let parent = path.parent_dir(source)
          case parent {
            "." | "/" -> ""
            _ -> path.basename(parent)
          }
        }
        False -> basename
      }
    }
  }
}

fn sanitize_import_name(value: String) -> String {
  value
  |> string.lowercase
  |> string.to_graphemes
  |> list.map(normalize_import_grapheme)
  |> collapse_dash_graphemes([], False)
  |> list.reverse
  |> string.join("")
  |> trim_dash_edges
}

fn normalize_import_grapheme(grapheme: String) -> String {
  case is_allowed_import_grapheme(grapheme) {
    True -> grapheme
    False -> "-"
  }
}

fn collapse_dash_graphemes(
  graphemes: List(String),
  acc: List(String),
  previous_was_dash: Bool,
) -> List(String) {
  case graphemes {
    [] -> acc
    [grapheme, ..rest] ->
      case grapheme == "-" && previous_was_dash {
        True -> collapse_dash_graphemes(rest, acc, True)
        False ->
          collapse_dash_graphemes(rest, [grapheme, ..acc], grapheme == "-")
      }
  }
}

fn trim_dash_edges(value: String) -> String {
  value
  |> trim_leading_dashes
  |> trim_trailing_dashes
}

fn trim_leading_dashes(value: String) -> String {
  case string.starts_with(value, "-") {
    True -> trim_leading_dashes(string.drop_start(value, 1))
    False -> value
  }
}

fn trim_trailing_dashes(value: String) -> String {
  case string.ends_with(value, "-") {
    True -> trim_trailing_dashes(string.drop_end(value, 1))
    False -> value
  }
}

fn is_valid_import_name(name: String) -> Bool {
  case name {
    "" -> False
    _ ->
      list.all(string.to_graphemes(name), fn(grapheme) {
        is_allowed_import_grapheme(grapheme)
      })
  }
}

fn is_allowed_import_grapheme(grapheme: String) -> Bool {
  case string.to_utf_codepoints(grapheme) {
    [cp] -> {
      let code = string.utf_codepoint_to_int(cp)
      code >= 97
      && code <= 122
      || code >= 48
      && code <= 57
      || code == 46
      || code == 95
      || code == 45
    }
    _ -> False
  }
}

@external(javascript, "../skill_universe_ffi.mjs", "get_env")
fn get_env(name: String) -> Result(String, Nil)
