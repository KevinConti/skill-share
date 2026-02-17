import argv
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile
import skill_universe/compiler
import skill_universe/config
import skill_universe/error
import skill_universe/importer
import skill_universe/parser
import skill_universe/provider
import skill_universe/registry
import skill_universe/scaffold
import skill_universe/semver
import skill_universe/types
import skill_universe/version_constraint

pub fn version() -> String {
  "1.1.0"
}

pub fn main() {
  case run(argv.load().arguments) {
    Ok(output) -> io.println(output)
    Error(output) -> {
      io.println_error(output)
      halt(1)
    }
  }
}

pub fn run(args: List(String)) -> Result(String, String) {
  case args {
    ["compile", ..rest] -> run_compile(rest)
    ["check", skill_dir] -> do_check(skill_dir)
    ["init", ..rest] -> run_init(rest)
    ["publish", ..rest] -> run_publish(rest)
    ["search", query] -> do_search(query)
    ["install", ..rest] -> run_install(rest)
    ["list", ..rest] -> run_list(rest)
    ["import", ..rest] -> run_import(rest)
    ["config", "init", skill_dir] -> do_config_init(skill_dir)
    ["config", "check", skill_dir] -> do_config_check(skill_dir)
    ["version"] -> Ok("skill-universe " <> version())
    ["help"] -> Ok(usage_text())
    ["--help"] -> Ok(usage_text())
    _ -> Error(usage_text())
  }
}

fn run_compile(args: List(String)) -> Result(String, String) {
  case args {
    [skill_dir, "--target", target] ->
      do_compile(skill_dir, target, skill_dir <> "/dist")
    [skill_dir, "--target", target, "--output", output] ->
      do_compile(skill_dir, target, output)
    [skill_dir, "--providers", providers_str] ->
      do_compile_providers(skill_dir, providers_str, skill_dir <> "/dist")
    [skill_dir, "--providers", providers_str, "--output", output] ->
      do_compile_providers(skill_dir, providers_str, output)
    [skill_dir, "--output", output, "--providers", providers_str] ->
      do_compile_providers(skill_dir, providers_str, output)
    [skill_dir] -> do_compile_all(skill_dir, skill_dir <> "/dist")
    [skill_dir, "--output", output] -> do_compile_all(skill_dir, output)
    _ -> Error(usage_text())
  }
}

fn run_init(args: List(String)) -> Result(String, String) {
  case args {
    [skill_dir, "--name", name] -> do_init(skill_dir, name)
    [skill_dir] -> do_init(skill_dir, name_from_path(skill_dir))
    _ -> Error(usage_text())
  }
}

fn run_publish(args: List(String)) -> Result(String, String) {
  case args {
    [skill_dir, "--repo", repo] -> do_publish(skill_dir, repo)
    [skill_dir] -> do_publish_infer(skill_dir)
    _ -> Error(usage_text())
  }
}

fn run_install(args: List(String)) -> Result(String, String) {
  case args {
    [spec, "--target", target, "--output", dir] ->
      do_install(spec, Some(target), dir)
    [spec, "--output", dir, "--target", target] ->
      do_install(spec, Some(target), dir)
    [spec, "--target", target] -> do_install(spec, Some(target), "./skills")
    [spec, "--output", dir] -> do_install(spec, None, dir)
    [spec] -> do_install(spec, None, "./skills")
    _ -> Error(usage_text())
  }
}

fn run_list(args: List(String)) -> Result(String, String) {
  case args {
    ["--installed", "--output", dir] -> do_list_installed(dir)
    ["--installed"] -> do_list_installed("./skills")
    [spec] -> {
      // Parse spec to extract optional skill name: "owner/repo" or "owner/repo/skill-name"
      let segments = string.split(spec, "/")
      case segments {
        [owner, repo, skill_name] ->
          do_list_versions(owner <> "/" <> repo, Some(skill_name))
        _ -> do_list_versions(spec, None)
      }
    }
    _ -> Error(usage_text())
  }
}

fn run_import(args: List(String)) -> Result(String, String) {
  case args {
    [source] -> do_import(source, None, "./")
    [source, "--provider", p] -> do_import(source, Some(p), "./")
    [source, "--output", dir] -> do_import(source, None, dir)
    [source, "--provider", p, "--output", dir] ->
      do_import(source, Some(p), dir)
    [source, "--output", dir, "--provider", p] ->
      do_import(source, Some(p), dir)
    _ -> Error(usage_text())
  }
}

fn do_compile(
  skill_dir: String,
  target: String,
  output_dir: String,
) -> Result(String, String) {
  case compiler.compile(skill_dir, target) {
    Ok(compiled) -> {
      let warning_lines = format_warnings(types.compiled_warnings(compiled))
      case compiler.emit(compiled, output_dir, types.compiled_name(compiled)) {
        Ok(_) ->
          Ok(warning_lines <> "Compiled " <> target <> " -> " <> output_dir)
        Error(err) -> Error("Error: " <> error.to_string(err))
      }
    }
    Error(err) -> Error("Error: " <> error.to_string(err))
  }
}

fn do_compile_all(
  skill_dir: String,
  output_dir: String,
) -> Result(String, String) {
  case compiler.compile_all(skill_dir) {
    Ok(compiled_list) -> {
      use result <- result.try(emit_compiled_list(compiled_list, output_dir))
      Ok(result <> check_deps_after_compile(skill_dir, output_dir))
    }
    Error(err) -> Error("Error: " <> error.to_string(err))
  }
}

fn do_compile_providers(
  skill_dir: String,
  providers_str: String,
  output_dir: String,
) -> Result(String, String) {
  let providers =
    string.split(providers_str, ",")
    |> list.map(string.trim)
    |> list.filter(fn(s) { !string.is_empty(s) })
  case compiler.compile_providers(skill_dir, providers) {
    Ok(compiled_list) -> {
      use result <- result.try(emit_compiled_list(compiled_list, output_dir))
      Ok(result <> check_deps_after_compile(skill_dir, output_dir))
    }
    Error(err) -> Error("Error: " <> error.to_string(err))
  }
}

fn emit_compiled_list(
  compiled_list: List(types.CompiledSkill),
  output_dir: String,
) -> Result(String, String) {
  use lines <- result.try(
    list.try_map(compiled_list, fn(compiled) {
      let warning_lines = format_warnings(types.compiled_warnings(compiled))
      case compiler.emit(compiled, output_dir, types.compiled_name(compiled)) {
        Ok(_) ->
          Ok(
            warning_lines
            <> "Compiled "
            <> types.provider_to_string(types.compiled_provider(compiled))
            <> " -> "
            <> output_dir,
          )
        Error(err) -> Error("Error: " <> error.to_string(err))
      }
    }),
  )
  Ok(string.join(lines, "\n"))
}

fn check_deps_after_compile(skill_dir: String, output_dir: String) -> String {
  case simplifile.read(skill_dir <> "/skill.yaml") {
    Ok(content) ->
      case parser.parse_skill_yaml(content) {
        Ok(skill) ->
          format_warnings(compiler.check_dependencies(skill, output_dir))
        Error(_) -> ""
      }
    Error(_) -> ""
  }
}

fn do_init(skill_dir: String, name: String) -> Result(String, String) {
  case scaffold.init_skill(skill_dir, name) {
    Ok(_) -> Ok("Created skill '" <> name <> "' in " <> skill_dir)
    Error(err) -> Error("Error: " <> error.to_string(err))
  }
}

fn do_publish(skill_dir: String, repo: String) -> Result(String, String) {
  registry.publish(skill_dir, repo)
  |> result.map_error(fn(err) { "Error: " <> error.to_string(err) })
}

fn do_publish_infer(skill_dir: String) -> Result(String, String) {
  case registry.infer_repo(skill_dir) {
    Ok(repo) -> do_publish(skill_dir, repo)
    Error(err) -> Error("Error: " <> error.to_string(err))
  }
}

fn do_search(query: String) -> Result(String, String) {
  registry.search(query)
  |> result.map_error(fn(err) { "Error: " <> error.to_string(err) })
}

fn do_install(
  spec: String,
  target: option.Option(String),
  output_dir: String,
) -> Result(String, String) {
  registry.install(spec, target, output_dir)
  |> result.map_error(fn(err) { "Error: " <> error.to_string(err) })
}

fn do_list_versions(
  repo: String,
  skill_name: option.Option(String),
) -> Result(String, String) {
  registry.list_versions(repo, skill_name)
  |> result.map_error(fn(err) { "Error: " <> error.to_string(err) })
}

fn do_list_installed(output_dir: String) -> Result(String, String) {
  registry.list_installed(output_dir)
  |> result.map_error(fn(err) { "Error: " <> error.to_string(err) })
}

fn do_import(
  source: String,
  provider_str: option.Option(String),
  output_dir: String,
) -> Result(String, String) {
  use provider_hint <- result.try(case provider_str {
    Some(p) ->
      case types.provider_from_string(p) {
        Ok(provider) -> Ok(Some(provider))
        Error(err) ->
          Error(
            "Error: Unknown provider '"
            <> types.provider_parse_error_input(err)
            <> "'. Use "
            <> types.all_provider_names(),
          )
      }
    None -> Ok(None)
  })
  case importer.import_skill(source, provider_hint, output_dir) {
    Ok(result) -> {
      let provider_name = types.provider_to_string(result.provider)
      Ok(
        "Imported "
        <> provider_name
        <> " skill -> "
        <> output_dir
        <> "\nNote: Import is lossy. Templates are already resolved, and dependencies/config/metadata sections from the original skill.yaml cannot be recovered.",
      )
    }
    Error(err) -> Error("Error: " <> error.to_string(err))
  }
}

fn do_config_init(skill_dir: String) -> Result(String, String) {
  case simplifile.read(skill_dir <> "/skill.yaml") {
    Error(_) -> Error("Error: skill.yaml not found in " <> skill_dir)
    Ok(content) ->
      case parser.parse_skill_yaml(content) {
        Error(err) -> Error("Error: " <> error.to_string(err))
        Ok(skill) -> Ok(config.generate_template(skill))
      }
  }
}

fn do_config_check(skill_dir: String) -> Result(String, String) {
  case simplifile.read(skill_dir <> "/skill.yaml") {
    Error(_) -> Error("Error: skill.yaml not found in " <> skill_dir)
    Ok(content) ->
      case parser.parse_skill_yaml(content) {
        Error(err) -> Error("Error: " <> error.to_string(err))
        Ok(skill) -> {
          let statuses = config.check(skill)
          let missing =
            list.filter_map(statuses, fn(s) {
              case s {
                config.MissingRequired(field:) ->
                  Ok(
                    "  MISSING: "
                    <> types.config_field_name_value(field.name)
                    <> " - "
                    <> types.config_field_description_value(field.description),
                  )
                _ -> Error(Nil)
              }
            })
          let satisfied =
            list.filter_map(statuses, fn(s) {
              case s {
                config.Provided(field:, ..) ->
                  Ok("  OK: " <> types.config_field_name_value(field.name))
                config.DefaultUsed(field:, default:) ->
                  Ok(
                    "  OK: "
                    <> types.config_field_name_value(field.name)
                    <> " (default: "
                    <> default
                    <> ")",
                  )
                config.Skipped(field:) ->
                  Ok(
                    "  OK: "
                    <> types.config_field_name_value(field.name)
                    <> " (not set)",
                  )
                config.MissingRequired(..) -> Error(Nil)
              }
            })
          case missing {
            [] ->
              Ok(
                "All configuration satisfied for "
                <> types.skill_name_value(skill.name)
                <> "\n"
                <> string.join(satisfied, "\n"),
              )
            _ ->
              Error(
                "Missing configuration for "
                <> types.skill_name_value(skill.name)
                <> ":\n"
                <> string.join(missing, "\n")
                <> case satisfied {
                  [] -> ""
                  _ -> "\n\nSatisfied:\n" <> string.join(satisfied, "\n")
                },
              )
          }
        }
      }
  }
}

fn do_check(skill_dir: String) -> Result(String, String) {
  case simplifile.read(skill_dir <> "/skill.yaml") {
    Error(_) -> Error("Error: skill.yaml not found in " <> skill_dir)
    Ok(content) -> {
      case parser.parse_skill_yaml(content) {
        Error(err) -> Error("Error: " <> error.to_string(err))
        Ok(skill) -> {
          let header =
            types.skill_name_value(skill.name)
            <> " v"
            <> semver.to_string(skill.version)
          let instructions_warning = case
            simplifile.is_file(skill_dir <> "/INSTRUCTIONS.md")
          {
            Ok(True) -> ""
            _ -> "\nWarning: INSTRUCTIONS.md not found"
          }
          let providers_section = case provider.discover_providers(skill_dir) {
            Ok([]) -> "\nNo supported providers found"
            Ok(providers) -> {
              let provider_lines =
                list.map(providers, fn(p) {
                  "  - " <> types.provider_to_string(p)
                })
              "\nSupported providers:\n" <> string.join(provider_lines, "\n")
            }
            Error(err) -> "\nError: " <> error.to_string(err)
          }
          Ok(header <> instructions_warning <> providers_section)
        }
      }
    }
  }
}

pub fn name_from_path(path: String) -> String {
  let trimmed =
    path
    |> string.trim_end()
  let trimmed = case string.ends_with(trimmed, "/") {
    True -> string.drop_end(trimmed, 1)
    False -> trimmed
  }
  case string.split(trimmed, "/") |> list.last() {
    Ok(name) -> name
    Error(_) -> trimmed
  }
}

fn format_warnings(warnings: List(types.CompileWarning)) -> String {
  case warnings {
    [] -> ""
    _ ->
      list.map(warnings, fn(w) {
        case w {
          types.FrontmatterInInstructions(file) ->
            "Warning: "
            <> file
            <> " contains YAML frontmatter which will be included as-is in the output"
          types.MissingDependency(dep) ->
            "Warning: missing dependency '"
            <> types.dependency_name_value(dep.name)
            <> "' ("
            <> version_constraint.to_string(dep.version)
            <> ")"
        }
      })
      |> string.join("\n")
      |> fn(s) { s <> "\n" }
  }
}

fn usage_text() -> String {
  "skill-universe " <> version() <> " - Cross-platform skill compiler

Usage:
  skill-universe compile <skill-dir>                          Compile all providers
  skill-universe compile <skill-dir> --target <provider>      Compile single provider
  skill-universe compile <skill-dir> --providers <list>       Compile selected providers
  skill-universe compile <skill-dir> --output <dir>           Compile with custom output
  skill-universe check <skill-dir>                            Check supported providers
  skill-universe init <skill-dir>                             Create a new skill
  skill-universe import <source>                              Import a provider-specific skill
  skill-universe import <source> --provider <provider>        Import with explicit provider
  skill-universe import <source> --output <dir>               Import to custom output dir
  skill-universe import owner/repo[/path][@ref]               Import from GitHub shorthand
  skill-universe import gitlab:group/project[@ref]            Import from GitLab shorthand
  skill-universe import <github|gitlab-url>                   Import from GitHub/GitLab URL
  skill-universe config init <skill-dir>                      Generate .env template
  skill-universe config check <skill-dir>                     Check config env vars
  skill-universe publish <skill-dir>                          Publish to GitHub Releases
  skill-universe publish <skill-dir> --repo <owner/repo>      Publish to specific repo
  skill-universe search <query>                               Search for skills
  skill-universe install <owner/repo>                         Install a skill
  skill-universe install <owner/repo/skill-name>              Install from multi-skill repo
  skill-universe install <spec> --target <provider>           Install for specific provider
  skill-universe list <owner/repo>                            List available versions
  skill-universe list <owner/repo/skill-name>                 List versions for a skill
  skill-universe list --installed                             List installed skills
  skill-universe version                                      Show version
  skill-universe help                                         Show this help

Install spec formats:
  owner/repo                    Latest release from repo
  owner/repo@v1.0.0            Specific version from repo
  owner/repo/skill-name         Latest release of skill from multi-skill repo
  owner/repo/skill-name@v1.0.0  Specific version of skill from multi-skill repo

Providers: openclaw, claude-code, codex"
}

@external(erlang, "erlang", "halt")
@external(javascript, "./skill_universe_ffi.mjs", "halt")
fn halt(code: Int) -> Nil
