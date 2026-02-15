import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import simplifile
import skillc/error.{type SkillError, ProviderError, map_file_error}
import skillc/fs
import skillc/parser
import skillc/provider
import skillc/semver
import skillc/template
import skillc/types.{
  type CompileWarning, type CompiledSkill, type FileCopy, type Provider,
  ClaudeCode, Codex, CompiledSkill, FileCopy, FrontmatterInInstructions,
  MissingDependency, OpenClaw,
}
import skillc/yaml
import yay

type FrontmatterData {
  FrontmatterData(lines: List(String), extra_pairs: List(#(yay.Node, yay.Node)))
}

type FileCategory {
  Scripts
  Assets
}

fn file_category_to_string(category: FileCategory) -> String {
  case category {
    Scripts -> "scripts"
    Assets -> "assets"
  }
}

pub fn compile(
  skill_dir: String,
  provider_name: String,
) -> Result(CompiledSkill, SkillError) {
  use provider <- result.try(case types.provider_from_string(provider_name) {
    Ok(p) -> Ok(p)
    Error(_) ->
      Error(ProviderError(
        provider_name,
        "Unknown provider '" <> provider_name <> "'",
      ))
  })
  compile_single(skill_dir, provider)
}

fn compile_single(
  skill_dir: String,
  provider: Provider,
) -> Result(CompiledSkill, SkillError) {
  // 1. Parse skill.yaml
  use skill_content <- result.try(
    simplifile.read(skill_dir <> "/skill.yaml")
    |> map_file_error(skill_dir <> "/skill.yaml"),
  )
  use skill <- result.try(parser.parse_skill_yaml(skill_content))

  // 2. Read INSTRUCTIONS.md
  use instructions_content <- result.try(
    simplifile.read(skill_dir <> "/INSTRUCTIONS.md")
    |> map_file_error(skill_dir <> "/INSTRUCTIONS.md"),
  )

  compile_for_provider(skill_dir, provider, skill, instructions_content)
}

fn compile_for_provider(
  skill_dir: String,
  provider: Provider,
  skill: types.Skill,
  instructions_content: String,
) -> Result(CompiledSkill, SkillError) {
  let provider_str = types.provider_to_string(provider)

  // 1. Verify provider is supported
  use _ <- result.try(provider.validate_provider(skill_dir, provider))

  // 2. Parse provider metadata
  let metadata_path =
    skill_dir <> "/providers/" <> provider_str <> "/metadata.yaml"
  use meta_content <- result.try(
    simplifile.read(metadata_path)
    |> map_file_error(metadata_path),
  )
  use provider_meta <- result.try(parser.parse_metadata_yaml(
    meta_content,
    provider,
  ))

  // 3. Check for frontmatter in INSTRUCTIONS.md (generates warning)
  let warnings: List(CompileWarning) = case
    parser.has_frontmatter(instructions_content)
  {
    True -> [FrontmatterInInstructions(skill_dir <> "/INSTRUCTIONS.md")]
    False -> []
  }

  // 4. Render INSTRUCTIONS.md through template engine
  use rendered_instructions <- result.try(template.render_template(
    instructions_content,
    provider,
    skill,
    provider_meta,
  ))

  // 5. If provider-specific instructions.md exists, render and append
  let provider_instructions_path =
    skill_dir <> "/providers/" <> provider_str <> "/instructions.md"
  use rendered_instructions <- result.try(
    case simplifile.read(provider_instructions_path) {
      Ok(provider_content) -> {
        use rendered_provider <- result.try(template.render_template(
          provider_content,
          provider,
          skill,
          provider_meta,
        ))
        Ok(rendered_instructions <> "\n\n" <> rendered_provider)
      }
      Error(_) -> Ok(rendered_instructions)
    },
  )

  // 6. Format output for provider
  let skill_md =
    format_skill_md(skill, provider, provider_meta, rendered_instructions)

  // 7. Collect scripts and assets
  let scripts = collect_files(skill_dir, provider_str, Scripts)
  let assets = collect_files(skill_dir, provider_str, Assets)

  // 8. Generate agents/openai.yaml for Codex
  let codex_yaml = case provider {
    Codex -> Some(generate_codex_yaml(provider_meta))
    _ -> None
  }

  Ok(CompiledSkill(
    provider: provider,
    skill_md: skill_md,
    scripts: scripts,
    assets: assets,
    warnings: warnings,
    codex_yaml: codex_yaml,
  ))
}

pub fn compile_all(skill_dir: String) -> Result(List(CompiledSkill), SkillError) {
  use providers <- result.try(provider.discover_providers(skill_dir))
  case providers {
    [] ->
      Error(ProviderError(
        "none",
        "No supported providers found in " <> skill_dir,
      ))
    _ -> {
      use #(skill, instructions_content) <- result.try(
        read_shared_inputs(skill_dir),
      )
      list.try_map(providers, fn(p) {
        compile_for_provider(skill_dir, p, skill, instructions_content)
      })
    }
  }
}

pub fn compile_providers(
  skill_dir: String,
  providers: List(String),
) -> Result(List(CompiledSkill), SkillError) {
  use parsed_providers <- result.try(
    list.try_map(providers, fn(p) {
      case types.provider_from_string(p) {
        Ok(provider) -> Ok(provider)
        Error(_) -> Error(ProviderError(p, "Unknown provider '" <> p <> "'"))
      }
    }),
  )
  case parsed_providers {
    [] -> Error(ProviderError("none", "No providers specified"))
    _ -> {
      use #(skill, instructions_content) <- result.try(
        read_shared_inputs(skill_dir),
      )
      list.try_map(parsed_providers, fn(p) {
        compile_for_provider(skill_dir, p, skill, instructions_content)
      })
    }
  }
}

fn read_shared_inputs(
  skill_dir: String,
) -> Result(#(types.Skill, String), SkillError) {
  use skill_content <- result.try(
    simplifile.read(skill_dir <> "/skill.yaml")
    |> map_file_error(skill_dir <> "/skill.yaml"),
  )
  use skill <- result.try(parser.parse_skill_yaml(skill_content))
  use instructions_content <- result.try(
    simplifile.read(skill_dir <> "/INSTRUCTIONS.md")
    |> map_file_error(skill_dir <> "/INSTRUCTIONS.md"),
  )
  Ok(#(skill, instructions_content))
}

pub fn emit(
  compiled: CompiledSkill,
  output_dir: String,
  skill_name: String,
) -> Result(Nil, SkillError) {
  let provider_str = types.provider_to_string(compiled.provider)
  let provider_dir = case compiled.provider {
    Codex -> output_dir <> "/codex/.agents/skills/" <> skill_name
    OpenClaw -> output_dir <> "/" <> provider_str <> "/" <> skill_name
    ClaudeCode -> output_dir <> "/" <> provider_str <> "/" <> skill_name
  }

  use _ <- result.try(
    simplifile.create_directory_all(provider_dir)
    |> map_file_error(provider_dir),
  )

  // Write SKILL.md
  use _ <- result.try(
    simplifile.write(provider_dir <> "/SKILL.md", compiled.skill_md)
    |> map_file_error(provider_dir <> "/SKILL.md"),
  )

  // Write agents/openai.yaml if present (Codex only)
  use _ <- result.try(case compiled.codex_yaml {
    Some(yaml_content) -> {
      let agents_dir = provider_dir <> "/agents"
      use _ <- result.try(
        simplifile.create_directory_all(agents_dir)
        |> map_file_error(agents_dir),
      )
      simplifile.write(agents_dir <> "/openai.yaml", yaml_content)
      |> map_file_error(agents_dir <> "/openai.yaml")
    }
    None -> Ok(Nil)
  })

  // Copy scripts
  use _ <- result.try(fs.copy_file_list(
    compiled.scripts,
    provider_dir <> "/scripts",
  ))

  // Copy assets
  use _ <- result.try(fs.copy_file_list(compiled.assets, provider_dir <> "/assets"))

  Ok(Nil)
}

// ============================================================================
// Format output per provider
// ============================================================================

fn format_skill_md(
  skill: types.Skill,
  provider: Provider,
  provider_meta: yay.Node,
  body: String,
) -> String {
  case provider {
    OpenClaw -> format_openclaw(skill, provider_meta, body)
    ClaudeCode -> format_claude_code(skill, provider_meta, body)
    Codex -> format_codex(skill, body)
  }
}

/// Build common frontmatter lines and extract remaining provider metadata pairs.
/// Returns the base frontmatter lines and the non-universal metadata key-value pairs.
fn build_base_frontmatter(
  skill: types.Skill,
  provider_meta: yay.Node,
) -> FrontmatterData {
  let universal_keys = ["name", "description", "version"]

  let version_str = semver.to_string(skill.version)
  let name = meta_string_or(provider_meta, "name", skill.name)
  let description =
    meta_string_or(provider_meta, "description", skill.description)
  let version = meta_string_or(provider_meta, "version", version_str)

  let lines = [
    "---",
    "name: " <> yaml.quote_string(name),
    "description: " <> yaml.quote_string(description),
    "version: " <> version,
  ]

  let extra_pairs = case provider_meta {
    yay.NodeMap(pairs) ->
      list.filter(pairs, fn(pair) {
        case pair {
          #(yay.NodeStr(key), _) -> !list.contains(universal_keys, key)
          _ -> False
        }
      })
    _ -> []
  }

  FrontmatterData(lines: lines, extra_pairs: extra_pairs)
}

fn format_openclaw(
  skill: types.Skill,
  provider_meta: yay.Node,
  body: String,
) -> String {
  let FrontmatterData(lines: base_lines, extra_pairs: extra_pairs) =
    build_base_frontmatter(skill, provider_meta)

  let frontmatter_lines = case skill.license {
    Some(l) -> list.append(base_lines, ["license: " <> l])
    None -> base_lines
  }

  let meta_lines = case extra_pairs {
    [] -> []
    pairs -> {
      let openclaw_lines =
        list.filter_map(pairs, fn(pair) {
          case pair {
            #(yay.NodeStr(key), value) -> {
              let val = node_to_yaml_value(value, 4)
              case string.starts_with(val, "\n") {
                True -> Ok("  " <> key <> ":" <> val)
                False -> Ok("  " <> key <> ": " <> val)
              }
            }
            _ -> Error(Nil)
          }
        })
      ["metadata.openclaw:", ..openclaw_lines]
    }
  }

  let all_lines = list.flatten([frontmatter_lines, meta_lines, ["---"]])

  string.join(all_lines, "\n") <> "\n\n" <> body
}

fn format_claude_code(
  skill: types.Skill,
  provider_meta: yay.Node,
  body: String,
) -> String {
  let FrontmatterData(lines: frontmatter_lines, extra_pairs: extra_pairs) =
    build_base_frontmatter(skill, provider_meta)

  let meta_lines =
    list.filter_map(extra_pairs, fn(pair) {
      case pair {
        #(yay.NodeStr(key), value) -> {
          let val = node_to_yaml_value(value, 2)
          case string.starts_with(val, "\n") {
            True -> Ok(key <> ":" <> val)
            False -> Ok(key <> ": " <> val)
          }
        }
        _ -> Error(Nil)
      }
    })

  let all_lines = list.flatten([frontmatter_lines, meta_lines, ["---"]])

  string.join(all_lines, "\n") <> "\n\n" <> body
}

fn format_codex(skill: types.Skill, body: String) -> String {
  let version_str = semver.to_string(skill.version)
  let frontmatter_lines = [
    "---",
    "name: " <> yaml.quote_string(skill.name),
    "description: " <> yaml.quote_string(skill.description),
    "version: " <> version_str,
    "---",
  ]

  string.join(frontmatter_lines, "\n") <> "\n\n" <> body
}

fn generate_codex_yaml(provider_meta: yay.Node) -> String {
  case provider_meta {
    yay.NodeMap(pairs) -> {
      let lines =
        list.filter_map(pairs, fn(pair) {
          case pair {
            #(yay.NodeStr(key), value) -> {
              let val = node_to_yaml_value(value, 2)
              case string.starts_with(val, "\n") {
                True -> Ok(key <> ":" <> val)
                False -> Ok(key <> ": " <> val)
              }
            }
            _ -> Error(Nil)
          }
        })
      string.join(lines, "\n") <> "\n"
    }
    _ -> ""
  }
}

fn meta_string_or(meta: yay.Node, key: String, default: String) -> String {
  case yay.extract_optional_string(meta, key) {
    Ok(Some(value)) -> value
    _ -> default
  }
}

fn node_to_yaml_value(node: yay.Node, indent: Int) -> String {
  case node {
    yay.NodeStr(s) -> yaml.quote_string(s)
    yay.NodeInt(i) -> int.to_string(i)
    yay.NodeFloat(f) -> float.to_string(f)
    yay.NodeBool(True) -> "true"
    yay.NodeBool(False) -> "false"
    yay.NodeNil -> "null"
    yay.NodeSeq(items) ->
      case seq_is_simple(items) {
        True ->
          "["
          <> string.join(
            list.map(items, fn(i) { node_to_yaml_value(i, indent) }),
            ", ",
          )
          <> "]"
        False -> serialize_yaml_seq(items, indent)
      }
    yay.NodeMap(pairs) -> serialize_yaml_map(pairs, indent)
  }
}

fn seq_is_simple(items: List(yay.Node)) -> Bool {
  list.all(items, fn(item) {
    case item {
      yay.NodeStr(_)
      | yay.NodeInt(_)
      | yay.NodeFloat(_)
      | yay.NodeBool(_)
      | yay.NodeNil -> True
      _ -> False
    }
  })
}

fn serialize_yaml_seq(items: List(yay.Node), indent: Int) -> String {
  let prefix = string.repeat(" ", indent)
  let lines =
    list.map(items, fn(item) {
      case item {
        yay.NodeMap(pairs) -> {
          // First key-value on same line as "- ", rest indented under it
          let pair_lines =
            list.filter_map(pairs, fn(pair) {
              case pair {
                #(yay.NodeStr(key), value) -> {
                  let val = node_to_yaml_value(value, indent + 4)
                  case string.starts_with(val, "\n") {
                    True -> Ok(key <> ":" <> val)
                    False -> Ok(key <> ": " <> val)
                  }
                }
                _ -> Error(Nil)
              }
            })
          case pair_lines {
            [first, ..rest] ->
              prefix
              <> "- "
              <> first
              <> string.join(
                list.map(rest, fn(line) { "\n" <> prefix <> "  " <> line }),
                "",
              )
            [] -> prefix <> "- {}"
          }
        }
        _ -> prefix <> "- " <> node_to_yaml_value(item, indent + 2)
      }
    })
  "\n" <> string.join(lines, "\n")
}

fn serialize_yaml_map(pairs: List(#(yay.Node, yay.Node)), indent: Int) -> String {
  let prefix = string.repeat(" ", indent)
  let lines =
    list.filter_map(pairs, fn(pair) {
      case pair {
        #(yay.NodeStr(key), value) -> {
          let val = node_to_yaml_value(value, indent + 2)
          case string.starts_with(val, "\n") {
            True -> Ok(prefix <> key <> ":" <> val)
            False -> Ok(prefix <> key <> ": " <> val)
          }
        }
        _ -> Error(Nil)
      }
    })
  "\n" <> string.join(lines, "\n")
}

// ============================================================================
// Dependency checking
// ============================================================================

pub fn check_dependencies(
  skill: types.Skill,
  output_dir: String,
) -> List(CompileWarning) {
  list.filter_map(skill.dependencies, fn(dep) {
    case dep.optional {
      True -> Error(Nil)
      False -> {
        case dependency_exists(dep.name, output_dir) {
          True -> Error(Nil)
          False -> Ok(MissingDependency(dep))
        }
      }
    }
  })
}

fn dependency_exists(dep_name: String, output_dir: String) -> Bool {
  // Check if dep_name/SKILL.md exists in any provider subdirectory
  case simplifile.read_directory(output_dir) {
    Ok(entries) ->
      list.any(entries, fn(provider_dir) {
        let skill_md_path =
          output_dir
          <> "/"
          <> provider_dir
          <> "/"
          <> dep_name
          <> "/SKILL.md"
        case simplifile.is_file(skill_md_path) {
          Ok(True) -> True
          _ -> False
        }
      })
    Error(_) -> False
  }
}

// ============================================================================
// File merging
// ============================================================================

fn collect_files(
  skill_dir: String,
  provider_str: String,
  category: FileCategory,
) -> List(FileCopy) {
  let dir_name = file_category_to_string(category)
  let shared_dir = skill_dir <> "/" <> dir_name
  let provider_dir = skill_dir <> "/providers/" <> provider_str <> "/" <> dir_name

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
  let provider_paths =
    set.from_list(list.map(provider, fn(f) { f.relative_path }))
  let filtered_shared =
    list.filter(shared, fn(f) { !set.contains(provider_paths, f.relative_path) })
  list.append(filtered_shared, provider)
}


