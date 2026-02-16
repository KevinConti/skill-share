import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import skill_universe/error.{type SkillError, ImportError, map_file_error}
import skill_universe/fs
import skill_universe/path
import skill_universe/platform
import skill_universe/semver.{type SemVer}
import skill_universe/shell
import skill_universe/types.{
  type FileCopy, type Provider, ClaudeCode, Codex, FileCopy, OpenClaw,
}
import skill_universe/yaml

// ============================================================================
// Types
// ============================================================================

/// A single key-value pair from YAML frontmatter.
pub type FrontmatterPair {
  FrontmatterPair(key: String, value: String)
}

/// Parsed YAML frontmatter and the markdown body that follows it.
pub type Frontmatter {
  Frontmatter(pairs: List(FrontmatterPair), body: String)
}

/// Universal skill fields extracted from frontmatter.
pub type UniversalFields {
  UniversalFields(
    name: String,
    description: String,
    version: SemVer,
    license: Option(String),
  )
}

/// Result of separating frontmatter into universal and provider-specific parts.
pub type SeparatedFields {
  SeparatedFields(universal: UniversalFields, provider: List(FrontmatterPair))
}

/// A resolved import source — either a directory or a single file.
pub type ResolvedSource {
  SourceDirectory(path: String)
  SourceFile(path: String, directory: String)
}

/// The result of a successful import operation.
pub type ImportResult {
  ImportResult(
    provider: Provider,
    skill_yaml: String,
    instructions_md: String,
    metadata_yaml: String,
    scripts: List(FileCopy),
    assets: List(FileCopy),
  )
}

// ============================================================================
// Main orchestrator
// ============================================================================

/// Import a provider-specific skill into unified format.
pub fn import_skill(
  source: String,
  provider_hint: Option(Provider),
  output_dir: String,
) -> Result(ImportResult, SkillError) {
  // Resolve source (local path or URL)
  use resolved <- result.try(fetch_source(source))

  // Read SKILL.md
  let skill_md_path = case resolved {
    SourceFile(path:, ..) -> path
    SourceDirectory(path:) -> path <> "/SKILL.md"
  }
  use content <- result.try(
    simplifile.read(skill_md_path)
    |> map_file_error(skill_md_path),
  )

  // Parse frontmatter
  use frontmatter <- result.try(parse_frontmatter(content))

  // Detect provider
  let source_dir = resolved_directory(resolved)
  use provider <- result.try(case provider_hint {
    Some(p) -> Ok(p)
    None -> detect_provider(frontmatter.pairs, source_dir)
  })

  // Read codex yaml before separation (keeps generate_metadata_yaml pure)
  let codex_yaml = case provider {
    Codex ->
      case simplifile.read(source_dir <> "/agents/openai.yaml") {
        Ok(content) -> Some(content)
        Error(_) -> None
      }
    _ -> None
  }

  // Separate fields (validates name, description, version)
  use separated <- result.try(separate_fields(frontmatter.pairs, provider))

  // Generate files
  let skill_yaml = generate_skill_yaml(separated.universal)
  let metadata_yaml = generate_metadata_yaml(separated.provider, codex_yaml)
  let instructions_md = string.trim(frontmatter.body) <> "\n"

  // Collect scripts and assets from source dir
  let scripts = collect_source_files(source_dir, "scripts")
  let assets = collect_source_files(source_dir, "assets")

  let import_result =
    ImportResult(
      provider: provider,
      skill_yaml: skill_yaml,
      instructions_md: instructions_md,
      metadata_yaml: metadata_yaml,
      scripts: scripts,
      assets: assets,
    )

  // Emit to disk
  use _ <- result.try(emit_imported(import_result, output_dir))

  Ok(import_result)
}

// ============================================================================
// Frontmatter parsing
// ============================================================================

/// Split a SKILL.md into YAML frontmatter key-value pairs and the body markdown.
pub fn parse_frontmatter(content: String) -> Result(Frontmatter, SkillError) {
  let trimmed = string.trim_start(content)
  case string.starts_with(trimmed, "---") {
    False ->
      Error(ImportError(
        "SKILL.md",
        "No YAML frontmatter found (expected opening ---)",
      ))
    True -> {
      let after_open = string.drop_start(trimmed, 3)
      let after_open = case string.starts_with(after_open, "\n") {
        True -> string.drop_start(after_open, 1)
        False -> after_open
      }
      case find_closing_fence(after_open) {
        Error(Nil) ->
          Error(ImportError(
            "SKILL.md",
            "Unclosed YAML frontmatter (missing closing ---)",
          ))
        Ok(#(yaml_block, body)) -> {
          let pairs = parse_yaml_pairs(yaml_block)
          Ok(Frontmatter(pairs: pairs, body: body))
        }
      }
    }
  }
}

/// Find closing --- fence. Returns (yaml_content, body_after_fence).
fn find_closing_fence(content: String) -> Result(#(String, String), Nil) {
  let lines = string.split(content, "\n")
  find_closing_fence_loop(lines, [])
}

fn find_closing_fence_loop(
  lines: List(String),
  acc: List(String),
) -> Result(#(String, String), Nil) {
  case lines {
    [] -> Error(Nil)
    [line, ..rest] -> {
      case string.trim(line) == "---" {
        True -> {
          let yaml = string.join(list.reverse(acc), "\n")
          let body = case rest {
            [] -> ""
            _ -> string.join(rest, "\n")
          }
          let body = case string.starts_with(body, "\n") {
            True -> string.drop_start(body, 1)
            False -> body
          }
          Ok(#(yaml, body))
        }
        False -> find_closing_fence_loop(rest, [line, ..acc])
      }
    }
  }
}

/// Parse a YAML frontmatter block into key-value pairs.
fn parse_yaml_pairs(yaml: String) -> List(FrontmatterPair) {
  let lines = string.split(yaml, "\n")
  parse_yaml_lines(lines, [])
}

fn parse_yaml_lines(
  lines: List(String),
  acc: List(FrontmatterPair),
) -> List(FrontmatterPair) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] -> {
      case string.trim(line) {
        "" -> parse_yaml_lines(rest, acc)
        _ -> {
          case string.contains(line, ":") && !string.starts_with(line, " ") {
            True -> {
              let #(key, value) = split_key_value(line)
              let trimmed_value = string.trim(value)
              case trimmed_value {
                "" -> {
                  let #(block_lines, remaining) = collect_indented(rest, [])
                  let block_value = string.join(list.reverse(block_lines), "\n")
                  parse_yaml_lines(remaining, [
                    FrontmatterPair(key:, value: block_value),
                    ..acc
                  ])
                }
                _ ->
                  parse_yaml_lines(rest, [
                    FrontmatterPair(key:, value: trimmed_value),
                    ..acc
                  ])
              }
            }
            False -> parse_yaml_lines(rest, acc)
          }
        }
      }
    }
  }
}

fn split_key_value(line: String) -> #(String, String) {
  case string.split_once(line, ":") {
    Ok(#(key, value)) -> #(string.trim(key), value)
    Error(Nil) -> #(line, "")
  }
}

fn collect_indented(
  lines: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(acc, [])
    [line, ..rest] -> {
      case string.starts_with(line, " ") || string.starts_with(line, "\t") {
        True -> collect_indented(rest, [line, ..acc])
        False -> {
          case string.trim(line) {
            "" -> collect_indented(rest, acc)
            _ -> #(acc, [line, ..rest])
          }
        }
      }
    }
  }
}

// ============================================================================
// Provider detection
// ============================================================================

/// Heuristic provider auto-detection from frontmatter keys and directory.
pub fn detect_provider(
  pairs: List(FrontmatterPair),
  source_dir: String,
) -> Result(Provider, SkillError) {
  let keys = list.map(pairs, fn(pair) { pair.key })

  // 1. Key starting with metadata.openclaw → OpenClaw
  let has_openclaw =
    list.any(keys, fn(k) { string.starts_with(k, "metadata.openclaw") })
  case has_openclaw {
    True -> Ok(OpenClaw)
    False -> {
      // 2. Claude Code specific keys
      let claude_code_keys = [
        "user-invocable", "allowed-tools", "disable-model-invocation",
      ]
      let has_claude_code =
        list.any(keys, fn(k) { list.contains(claude_code_keys, k) })
      case has_claude_code {
        True -> Ok(ClaudeCode)
        False -> {
          // 3. Codex: agents/openai.yaml exists in source dir
          case simplifile.is_file(source_dir <> "/agents/openai.yaml") {
            Ok(True) -> Ok(Codex)
            _ ->
              Error(ImportError(
                "detect",
                "Cannot auto-detect provider. Pass --provider openclaw|claude-code|codex",
              ))
          }
        }
      }
    }
  }
}

// ============================================================================
// Field separation
// ============================================================================

/// Classify each frontmatter key as universal or provider-specific.
/// Returns an error if required fields (name, description, version) are missing.
pub fn separate_fields(
  pairs: List(FrontmatterPair),
  provider: Provider,
) -> Result(SeparatedFields, SkillError) {
  let universal_keys = ["name", "description", "version", "license"]

  // Extract and validate required fields
  use name <- result.try(
    find_pair_value(pairs, "name")
    |> option.map(unquote_yaml_string)
    |> require_non_empty("name"),
  )
  use description <- result.try(
    find_pair_value(pairs, "description")
    |> option.map(unquote_yaml_string)
    |> require_non_empty("description"),
  )
  use version <- result.try(
    find_pair_value(pairs, "version")
    |> option.map(unquote_yaml_string)
    |> require_non_empty("version"),
  )
  use version <- result.try(
    semver.parse(version)
    |> result.map_error(fn(_) {
      ImportError("version", "Invalid version format: " <> version)
    }),
  )

  let license =
    find_pair_value(pairs, "license")
    |> option.map(unquote_yaml_string)

  let universal =
    UniversalFields(
      name: name,
      description: description,
      version: version,
      license: license,
    )

  let provider_pairs = case provider {
    OpenClaw -> {
      case find_pair_value(pairs, "metadata.openclaw") {
        Some(block) -> parse_openclaw_block(block)
        None ->
          list.filter(pairs, fn(pair) {
            !list.contains(universal_keys, pair.key)
            && !string.starts_with(pair.key, "metadata.openclaw")
          })
      }
    }
    _ ->
      list.filter(pairs, fn(pair) { !list.contains(universal_keys, pair.key) })
  }

  Ok(SeparatedFields(universal: universal, provider: provider_pairs))
}

fn find_pair_value(pairs: List(FrontmatterPair), key: String) -> Option(String) {
  case list.find(pairs, fn(pair) { pair.key == key }) {
    Ok(FrontmatterPair(value:, ..)) -> Some(value)
    Error(Nil) -> None
  }
}

/// Require that an optional value is present and non-empty.
fn require_non_empty(
  value: Option(String),
  field: String,
) -> Result(String, SkillError) {
  case value {
    None ->
      Error(ImportError(
        field,
        "Required field '" <> field <> "' is missing from frontmatter",
      ))
    Some(s) ->
      case string.trim(s) {
        "" ->
          Error(ImportError(
            field,
            "Required field '" <> field <> "' must not be empty",
          ))
        _ -> Ok(s)
      }
  }
}

/// Remove surrounding quotes from a YAML string value.
fn unquote_yaml_string(s: String) -> String {
  let trimmed = string.trim(s)
  case string.starts_with(trimmed, "\"") && string.ends_with(trimmed, "\"") {
    True -> {
      let inner = trimmed |> string.drop_start(1) |> string.drop_end(1)
      let inner = string.replace(inner, "\\n", "\n")
      let inner = string.replace(inner, "\\\"", "\"")
      string.replace(inner, "\\\\", "\\")
    }
    False ->
      case string.starts_with(trimmed, "'") && string.ends_with(trimmed, "'") {
        True -> trimmed |> string.drop_start(1) |> string.drop_end(1)
        False -> trimmed
      }
  }
}

/// Parse the indented block under metadata.openclaw: into key-value pairs.
fn parse_openclaw_block(block: String) -> List(FrontmatterPair) {
  let lines = string.split(block, "\n")
  parse_openclaw_lines(lines, [])
}

fn parse_openclaw_lines(
  lines: List(String),
  acc: List(FrontmatterPair),
) -> List(FrontmatterPair) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] -> {
      let stripped = string.trim_start(line)
      case string.trim(stripped) {
        "" -> parse_openclaw_lines(rest, acc)
        _ -> {
          case string.contains(stripped, ":") {
            True -> {
              let #(key, value) = split_key_value(stripped)
              let trimmed_value = string.trim(value)
              case trimmed_value {
                "" -> {
                  let base_indent =
                    string.length(line) - string.length(stripped)
                  let #(block_lines, remaining) =
                    collect_sub_indented(rest, base_indent, [])
                  let block_value = string.join(list.reverse(block_lines), "\n")
                  parse_openclaw_lines(remaining, [
                    FrontmatterPair(key:, value: block_value),
                    ..acc
                  ])
                }
                _ ->
                  parse_openclaw_lines(rest, [
                    FrontmatterPair(key:, value: trimmed_value),
                    ..acc
                  ])
              }
            }
            False -> parse_openclaw_lines(rest, acc)
          }
        }
      }
    }
  }
}

fn collect_sub_indented(
  lines: List(String),
  base_indent: Int,
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(acc, [])
    [line, ..rest] -> {
      let stripped = string.trim_start(line)
      let line_indent = string.length(line) - string.length(stripped)
      case string.trim(line) {
        "" -> collect_sub_indented(rest, base_indent, acc)
        _ -> {
          case line_indent > base_indent {
            True -> {
              let trimmed_line = string.drop_start(line, base_indent + 2)
              collect_sub_indented(rest, base_indent, [trimmed_line, ..acc])
            }
            False -> #(acc, [line, ..rest])
          }
        }
      }
    }
  }
}

// ============================================================================
// YAML generation
// ============================================================================

/// Generate skill.yaml content from universal fields.
pub fn generate_skill_yaml(fields: UniversalFields) -> String {
  let lines = [
    "name: " <> yaml.quote_string(fields.name),
    "description: " <> yaml.quote_string(fields.description),
    "version: " <> semver.to_string(fields.version),
  ]
  let lines = case fields.license {
    Some(l) -> list.append(lines, ["license: " <> yaml.quote_string(l)])
    None -> lines
  }
  string.join(lines, "\n") <> "\n"
}

/// Generate metadata.yaml content from provider-specific pairs.
/// For Codex, uses pre-read agents/openai.yaml content if available.
pub fn generate_metadata_yaml(
  provider_pairs: List(FrontmatterPair),
  codex_yaml: Option(String),
) -> String {
  case codex_yaml {
    Some(content) -> content
    None -> format_pairs_as_yaml(provider_pairs)
  }
}

fn format_pairs_as_yaml(pairs: List(FrontmatterPair)) -> String {
  case pairs {
    [] -> ""
    _ -> {
      let lines =
        list.map(pairs, fn(pair) {
          case string.contains(pair.value, "\n") {
            True -> pair.key <> ":\n" <> indent_block(pair.value, 2)
            False -> pair.key <> ": " <> pair.value
          }
        })
      string.join(lines, "\n") <> "\n"
    }
  }
}

fn indent_block(block: String, spaces: Int) -> String {
  let prefix = string.repeat(" ", spaces)
  let lines = string.split(block, "\n")
  list.map(lines, fn(line) {
    case string.trim(line) {
      "" -> ""
      _ -> prefix <> line
    }
  })
  |> string.join("\n")
}

// ============================================================================
// Source resolution
// ============================================================================

/// Resolve source: download URL to temp dir, or classify local path as
/// file or directory.
pub fn fetch_source(source: String) -> Result(ResolvedSource, SkillError) {
  case
    string.starts_with(source, "http://")
    || string.starts_with(source, "https://")
  {
    True -> fetch_remote(source)
    False -> resolve_local(source)
  }
}

fn fetch_remote(url: String) -> Result(ResolvedSource, SkillError) {
  let tmp_dir =
    platform.tmpdir() <> "/skill-universe-import-" <> hash_string(url)
  case simplifile.create_directory_all(tmp_dir) {
    Error(_) -> Error(ImportError(url, "Failed to create temp directory"))
    Ok(_) -> {
      let cmd =
        "curl -sSfL -o "
        <> shell.quote(tmp_dir <> "/SKILL.md")
        <> " "
        <> shell.quote(url)
      case shell.exec(cmd) {
        Ok(_) -> Ok(SourceDirectory(tmp_dir))
        Error(msg) -> Error(ImportError(url, "Failed to download: " <> msg))
      }
    }
  }
}

fn resolve_local(source: String) -> Result(ResolvedSource, SkillError) {
  case simplifile.is_file(source) {
    Ok(True) -> Ok(SourceFile(path: source, directory: path.parent_dir(source)))
    _ -> Ok(SourceDirectory(source))
  }
}

/// Extract the directory path from a resolved source.
fn resolved_directory(source: ResolvedSource) -> String {
  case source {
    SourceDirectory(path:) -> path
    SourceFile(directory:, ..) -> directory
  }
}

// ============================================================================
// Emit to disk
// ============================================================================

/// Write the unified directory structure to disk.
pub fn emit_imported(
  import_result: ImportResult,
  output_dir: String,
) -> Result(Nil, SkillError) {
  case simplifile.is_file(output_dir <> "/skill.yaml") {
    Ok(True) ->
      Error(ImportError("emit", "skill.yaml already exists in " <> output_dir))
    _ -> do_emit_imported(import_result, output_dir)
  }
}

fn do_emit_imported(
  import_result: ImportResult,
  output_dir: String,
) -> Result(Nil, SkillError) {
  let provider_str = types.provider_to_string(import_result.provider)
  let provider_dir = output_dir <> "/providers/" <> provider_str

  use _ <- result.try(
    simplifile.create_directory_all(provider_dir)
    |> map_file_error(provider_dir),
  )
  use _ <- result.try(
    simplifile.write(output_dir <> "/skill.yaml", import_result.skill_yaml)
    |> map_file_error(output_dir <> "/skill.yaml"),
  )
  use _ <- result.try(
    simplifile.write(
      output_dir <> "/INSTRUCTIONS.md",
      import_result.instructions_md,
    )
    |> map_file_error(output_dir <> "/INSTRUCTIONS.md"),
  )
  use _ <- result.try(
    simplifile.write(
      provider_dir <> "/metadata.yaml",
      import_result.metadata_yaml,
    )
    |> map_file_error(provider_dir <> "/metadata.yaml"),
  )
  use _ <- result.try(fs.copy_file_list(
    import_result.scripts,
    provider_dir <> "/scripts",
  ))
  use _ <- result.try(fs.copy_file_list(
    import_result.assets,
    provider_dir <> "/assets",
  ))

  Ok(Nil)
}

fn collect_source_files(source_dir: String, subdir: String) -> List(FileCopy) {
  let dir = source_dir <> "/" <> subdir
  case simplifile.get_files(dir) {
    Ok(files) ->
      list.map(files, fn(f) {
        let relative = string.replace(f, dir <> "/", "")
        FileCopy(src: f, relative_path: relative)
      })
    Error(_) -> []
  }
}

/// Simple string hash for temp directory naming.
fn hash_string(s: String) -> String {
  let chars = string.to_utf_codepoints(s)
  let hash =
    list.fold(chars, 0, fn(acc, cp) {
      let code = string.utf_codepoint_to_int(cp)
      { { acc * 31 } % 999_999_937 + code } % 999_999_937
    })
  case hash < 0 {
    True -> int.to_string(-hash)
    False -> int.to_string(hash)
  }
}
