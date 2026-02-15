import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile
import skillc/error.{type SkillError, FileError, ProviderError}
import skillc/parser
import skillc/provider
import skillc/template
import skillc/types.{
  type CompiledSkill, type CompileWarning, type FileCopy, CompiledSkill,
  FileCopy, FrontmatterInInstructions,
}
import yay

pub fn compile(
  skill_dir: String,
  target: String,
) -> Result(CompiledSkill, SkillError) {
  // 1. Parse skill.yaml
  use skill_content <- result.try(
    simplifile.read(skill_dir <> "/skill.yaml")
    |> result.map_error(fn(e) { FileError(skill_dir <> "/skill.yaml", e) }),
  )
  use skill <- result.try(parser.parse_skill_yaml(skill_content))

  // 2. Verify target is supported
  use _ <- result.try(provider.validate_provider(skill_dir, target))

  // 3. Parse provider metadata
  let metadata_path =
    skill_dir <> "/providers/" <> target <> "/metadata.yaml"
  use meta_content <- result.try(
    simplifile.read(metadata_path)
    |> result.map_error(fn(e) { FileError(metadata_path, e) }),
  )
  use provider_meta <- result.try(
    parser.parse_metadata_yaml(meta_content, target),
  )

  // 4. Read INSTRUCTIONS.md
  use instructions_content <- result.try(
    simplifile.read(skill_dir <> "/INSTRUCTIONS.md")
    |> result.map_error(fn(e) {
      FileError(skill_dir <> "/INSTRUCTIONS.md", e)
    }),
  )

  // 4b. Check for frontmatter in INSTRUCTIONS.md (generates warning)
  let warnings: List(CompileWarning) = case
    parser.has_frontmatter(instructions_content)
  {
    True -> [FrontmatterInInstructions(skill_dir <> "/INSTRUCTIONS.md")]
    False -> []
  }

  // 5-6. Render INSTRUCTIONS.md through template engine
  use rendered_instructions <- result.try(template.render_template(
    instructions_content,
    target,
    skill,
    provider_meta,
  ))

  // 7. If provider-specific instructions.md exists, render and append
  let provider_instructions_path =
    skill_dir <> "/providers/" <> target <> "/instructions.md"
  use rendered_instructions <- result.try(
    case simplifile.read(provider_instructions_path) {
      Ok(provider_content) -> {
        use rendered_provider <- result.try(template.render_template(
          provider_content,
          target,
          skill,
          provider_meta,
        ))
        Ok(rendered_instructions <> "\n\n" <> rendered_provider)
      }
      Error(_) -> Ok(rendered_instructions)
    },
  )

  // 8-9. Format output for target provider
  let skill_md =
    format_skill_md(skill, target, provider_meta, rendered_instructions)

  // 10. Collect scripts
  let scripts = collect_files(skill_dir, target, "scripts")
  let assets = collect_files(skill_dir, target, "assets")

  Ok(CompiledSkill(
    provider: target,
    skill_md: skill_md,
    scripts: scripts,
    assets: assets,
    warnings: warnings,
  ))
}

pub fn compile_all(
  skill_dir: String,
) -> Result(List(CompiledSkill), SkillError) {
  use discovery <- result.try(provider.discover_providers(skill_dir))
  case discovery.providers {
    [] ->
      Error(ProviderError(
        "none",
        "No supported providers found in " <> skill_dir,
      ))
    providers ->
      list.try_map(providers, fn(p) { compile(skill_dir, p) })
  }
}

pub fn emit(
  compiled: CompiledSkill,
  output_dir: String,
  skill_name: String,
) -> Result(Nil, SkillError) {
  let provider_dir = case compiled.provider {
    "codex" ->
      output_dir <> "/codex/.agents/skills/" <> skill_name
    provider ->
      output_dir <> "/" <> provider <> "/" <> skill_name
  }

  use _ <- result.try(
    simplifile.create_directory_all(provider_dir)
    |> result.map_error(fn(e) { FileError(provider_dir, e) }),
  )

  // Write SKILL.md
  use _ <- result.try(
    simplifile.write(provider_dir <> "/SKILL.md", compiled.skill_md)
    |> result.map_error(fn(e) { FileError(provider_dir <> "/SKILL.md", e) }),
  )

  // Copy scripts
  use _ <- result.try(
    copy_file_list(compiled.scripts, provider_dir <> "/scripts"),
  )

  // Copy assets
  use _ <- result.try(
    copy_file_list(compiled.assets, provider_dir <> "/assets"),
  )

  // For codex: generate agents/openai.yaml
  case compiled.provider {
    "codex" -> {
      let agents_dir = provider_dir <> "/agents"
      use _ <- result.try(
        simplifile.create_directory_all(agents_dir)
        |> result.map_error(fn(e) { FileError(agents_dir, e) }),
      )
      // openai.yaml is generated from provider metadata - for now emit a placeholder
      Ok(Nil)
    }
    _ -> Ok(Nil)
  }
}

// ============================================================================
// Format output per provider
// ============================================================================

fn format_skill_md(
  skill: types.Skill,
  target: String,
  provider_meta: yay.Node,
  body: String,
) -> String {
  case target {
    "openclaw" -> format_openclaw(skill, provider_meta, body)
    "claude-code" -> format_claude_code(skill, provider_meta, body)
    "codex" -> format_codex(skill, body)
    _ -> format_generic(skill, body)
  }
}

fn format_openclaw(
  skill: types.Skill,
  provider_meta: yay.Node,
  body: String,
) -> String {
  // Provider values override universal values for top-level fields
  let name = meta_string_or(provider_meta, "name", skill.name)
  let description =
    meta_string_or(provider_meta, "description", skill.description)
  let version = meta_string_or(provider_meta, "version", skill.version)

  let frontmatter_lines = [
    "---",
    "name: " <> name,
    "description: " <> quote_yaml_string(description),
    "version: " <> version,
  ]

  let frontmatter_lines = case skill.license {
    Some(l) -> list.append(frontmatter_lines, ["license: " <> l])
    None -> frontmatter_lines
  }

  // Add openclaw-specific metadata under metadata.openclaw
  // (exclude fields already used at top level)
  let universal_keys = ["name", "description", "version"]
  let meta_lines = case provider_meta {
    yay.NodeMap(pairs) -> {
      let openclaw_lines =
        list.filter_map(pairs, fn(pair) {
          case pair {
            #(yay.NodeStr(key), value) ->
              case list.contains(universal_keys, key) {
                True -> Error(Nil)
                False ->
                  Ok("  " <> key <> ": " <> node_to_yaml_value(value))
              }
            _ -> Error(Nil)
          }
        })
      case openclaw_lines {
        [] -> []
        lines -> list.append(["metadata.openclaw:"], lines)
      }
    }
    _ -> []
  }

  let all_lines =
    list.append(frontmatter_lines, meta_lines)
    |> list.append(["---"])

  string.join(all_lines, "\n") <> "\n\n" <> body
}

fn format_claude_code(
  skill: types.Skill,
  provider_meta: yay.Node,
  body: String,
) -> String {
  // Provider values override universal values for top-level fields
  let name = meta_string_or(provider_meta, "name", skill.name)
  let description =
    meta_string_or(provider_meta, "description", skill.description)
  let version = meta_string_or(provider_meta, "version", skill.version)

  let frontmatter_lines = [
    "---",
    "name: " <> name,
    "description: " <> quote_yaml_string(description),
    "version: " <> version,
  ]

  // Flat frontmatter: merge provider metadata at top level
  // (exclude fields already used above)
  let universal_keys = ["name", "description", "version"]
  let meta_lines = case provider_meta {
    yay.NodeMap(pairs) ->
      list.filter_map(pairs, fn(pair) {
        case pair {
          #(yay.NodeStr(key), value) ->
            case list.contains(universal_keys, key) {
              True -> Error(Nil)
              False -> Ok(key <> ": " <> node_to_yaml_value(value))
            }
          _ -> Error(Nil)
        }
      })
    _ -> []
  }

  let all_lines =
    list.append(frontmatter_lines, meta_lines)
    |> list.append(["---"])

  string.join(all_lines, "\n") <> "\n\n" <> body
}

fn format_codex(skill: types.Skill, body: String) -> String {
  let frontmatter_lines = [
    "---",
    "name: " <> skill.name,
    "description: " <> skill.description,
    "version: " <> skill.version,
    "---",
  ]

  string.join(frontmatter_lines, "\n") <> "\n\n" <> body
}

fn format_generic(skill: types.Skill, body: String) -> String {
  let frontmatter_lines = [
    "---",
    "name: " <> skill.name,
    "description: " <> skill.description,
    "version: " <> skill.version,
    "---",
  ]

  string.join(frontmatter_lines, "\n") <> "\n\n" <> body
}

fn meta_string_or(meta: yay.Node, key: String, default: String) -> String {
  case yay.extract_optional_string(meta, key) {
    Ok(Some(value)) -> value
    _ -> default
  }
}

fn node_to_yaml_value(node: yay.Node) -> String {
  case node {
    yay.NodeStr(s) -> quote_yaml_string(s)
    yay.NodeInt(i) -> int.to_string(i)
    yay.NodeFloat(f) -> float.to_string(f)
    yay.NodeBool(True) -> "true"
    yay.NodeBool(False) -> "false"
    yay.NodeNil -> "null"
    yay.NodeSeq(items) ->
      "[" <> string.join(list.map(items, node_to_yaml_value), ", ") <> "]"
    yay.NodeMap(_) -> "{...}"
  }
}

fn quote_yaml_string(s: String) -> String {
  case
    string.contains(s, ":"),
    string.contains(s, "#"),
    string.contains(s, " ")
  {
    True, _, _ -> "\"" <> s <> "\""
    _, True, _ -> "\"" <> s <> "\""
    _, _, True -> "\"" <> s <> "\""
    _, _, _ -> s
  }
}


// ============================================================================
// File merging
// ============================================================================

fn collect_files(
  skill_dir: String,
  target: String,
  dir_type: String,
) -> List(FileCopy) {
  let shared_dir = skill_dir <> "/" <> dir_type
  let provider_dir =
    skill_dir <> "/providers/" <> target <> "/" <> dir_type

  let shared_files = case simplifile.get_files(shared_dir) {
    Ok(files) ->
      list.map(files, fn(f) {
        let relative = string.replace(f, shared_dir <> "/", "")
        FileCopy(src: f, relative_path: relative)
      })
    Error(_) -> []
  }

  let provider_files = case simplifile.get_files(provider_dir) {
    Ok(files) ->
      list.map(files, fn(f) {
        let relative = string.replace(f, provider_dir <> "/", "")
        FileCopy(src: f, relative_path: relative)
      })
    Error(_) -> []
  }

  // Merge: provider files override shared files with same relative path
  merge_file_lists(shared_files, provider_files)
}

fn merge_file_lists(
  shared: List(FileCopy),
  provider: List(FileCopy),
) -> List(FileCopy) {
  let provider_paths = list.map(provider, fn(f) { f.relative_path })
  let filtered_shared =
    list.filter(shared, fn(f) {
      !list.contains(provider_paths, f.relative_path)
    })
  list.append(filtered_shared, provider)
}

fn copy_file_list(
  files: List(FileCopy),
  dest_dir: String,
) -> Result(Nil, SkillError) {
  case files {
    [] -> Ok(Nil)
    _ -> {
      use _ <- result.try(
        simplifile.create_directory_all(dest_dir)
        |> result.map_error(fn(e) { FileError(dest_dir, e) }),
      )
      list.try_each(files, fn(f) {
        let dest = dest_dir <> "/" <> f.relative_path
        // Ensure parent directory exists
        let parent = get_parent_dir(dest)
        use _ <- result.try(
          simplifile.create_directory_all(parent)
          |> result.map_error(fn(e) { FileError(parent, e) }),
        )
        simplifile.copy_file(f.src, dest)
        |> result.map_error(fn(e) { FileError(f.src, e) })
      })
    }
  }
}

fn get_parent_dir(path: String) -> String {
  case string.split(path, "/") |> list.reverse() {
    [_, ..rest] if rest != [] -> string.join(list.reverse(rest), "/")
    _ -> "."
  }
}
