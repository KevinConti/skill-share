import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import skill_universe/compiler
import skill_universe/error.{type SkillError, RegistryError, map_file_error}
import skill_universe/parser
import skill_universe/path
import skill_universe/platform
import skill_universe/semver
import skill_universe/shell
import skill_universe/types
import skill_universe/version_constraint

// ============================================================================
// Publish
// ============================================================================

pub fn publish(skill_dir: String, repo: String) -> Result(String, SkillError) {
  // 1. Validate skill
  use skill_content <- result.try(
    simplifile.read(skill_dir <> "/skill.yaml")
    |> map_file_error(skill_dir <> "/skill.yaml"),
  )
  use skill <- result.try(parser.parse_skill_yaml(skill_content))

  let version_str = semver.to_string(skill.version)
  let tag = skill.name <> "-v" <> version_str
  let tarball_name = skill.name <> "-" <> version_str <> ".tar.gz"
  let tarball_path = platform.tmpdir() <> "/" <> tarball_name

  // 2. Create tarball of skill source directory
  let parent = path.parent_dir(skill_dir)
  let dirname = path.basename(skill_dir)
  use _ <- result.try(
    shell.exec(
      "tar czf "
      <> tarball_path
      <> " -C "
      <> shell_quote(parent)
      <> " "
      <> shell_quote(dirname),
    )
    |> result.map_error(fn(e) {
      RegistryError("Failed to create tarball: " <> e)
    }),
  )

  // 3. Check gh is available
  use _ <- result.try(
    shell.exec("gh --version")
    |> result.map_error(fn(_) {
      RegistryError(
        "GitHub CLI (gh) is not installed. Install it from https://cli.github.com",
      )
    }),
  )

  // 4. Create GitHub Release
  use output <- result.try(
    shell.exec(
      "gh release create "
      <> shell_quote(tag)
      <> " "
      <> shell_quote(tarball_path)
      <> " --repo "
      <> shell_quote(repo)
      <> " --title "
      <> shell_quote(skill.name <> " " <> tag)
      <> " --notes "
      <> shell_quote("Published by skill-universe"),
    )
    |> result.map_error(fn(e) {
      RegistryError("Failed to create release: " <> e)
    }),
  )

  // 5. Clean up tarball
  let _ = simplifile.delete(tarball_path)

  Ok(
    "Published " <> skill.name <> " " <> tag <> " to " <> repo <> "\n" <> output,
  )
}

pub fn infer_repo(skill_dir: String) -> Result(String, SkillError) {
  use url <- result.try(
    shell.exec("git -C " <> shell_quote(skill_dir) <> " remote get-url origin")
    |> result.map_error(fn(_) {
      RegistryError(
        "Could not infer repository. Use --repo owner/repo or ensure a git remote is configured.",
      )
    }),
  )
  Ok(parse_repo_url(url))
}

pub fn parse_repo_url(url: String) -> String {
  let url = string.trim(url)
  // Handle git@github.com:owner/repo.git
  let url = case string.contains(url, "@") {
    True ->
      case string.split_once(url, ":") {
        Ok(#(_, path)) -> path
        _ -> url
      }
    False -> url
  }
  // Handle https://github.com/owner/repo.git
  let url = case string.split(url, "github.com/") {
    [_, path] -> path
    _ -> url
  }
  // Strip .git suffix
  let url = case string.ends_with(url, ".git") {
    True -> string.drop_end(url, 4)
    False -> url
  }
  // Strip trailing slash
  case string.ends_with(url, "/") {
    True -> string.drop_end(url, 1)
    False -> url
  }
}

// ============================================================================
// Search
// ============================================================================

pub fn search(query: String) -> Result(String, SkillError) {
  use _ <- result.try(require_gh())
  use output <- result.try(
    shell.exec(
      "gh search repos --topic skill-universe "
      <> shell_quote(query)
      <> " --json name,owner,description --jq "
      <> shell_quote(".[] | \"\\(.owner.login)/\\(.name) - \\(.description)\"")
      <> " --limit 20",
    )
    |> result.map_error(fn(e) { RegistryError("Search failed: " <> e) }),
  )
  case string.is_empty(string.trim(output)) {
    True -> Ok("No skills found matching '" <> query <> "'")
    False -> Ok(output)
  }
}

// ============================================================================
// Install
// ============================================================================

pub fn install(
  spec: String,
  target: Option(String),
  output_dir: String,
) -> Result(String, SkillError) {
  use _ <- result.try(require_gh())

  // 1. Parse spec: "owner/repo", "owner/repo@v1.0", "owner/repo/skill", "owner/repo/skill@v1.0"
  let #(repo, skill_name, version) = parse_install_spec(spec)

  // 2. Create temp directory
  let tmp_dir =
    platform.tmpdir()
    <> "/skill-universe-install-"
    <> string.replace(repo, "/", "-")
  let _ = simplifile.delete(tmp_dir)
  use _ <- result.try(
    simplifile.create_directory_all(tmp_dir)
    |> map_file_error(tmp_dir),
  )

  // 3. Resolve the tag to download
  use tag_flag <- result.try(resolve_install_tag(repo, skill_name, version))

  // 4. Download release tarball
  use _ <- result.try(
    shell.exec(
      "gh release download"
      <> tag_flag
      <> " --repo "
      <> shell_quote(repo)
      <> " --pattern '*.tar.gz'"
      <> " --dir "
      <> shell_quote(tmp_dir),
    )
    |> result.map_error(fn(e) {
      RegistryError("Failed to download release: " <> e)
    }),
  )

  // 5. Find the downloaded tarball
  use tarball <- result.try(case simplifile.get_files(tmp_dir) {
    Ok(files) ->
      case list.find(files, fn(f) { string.ends_with(f, ".tar.gz") }) {
        Ok(f) -> Ok(f)
        Error(_) ->
          Error(RegistryError("No tarball found in downloaded release"))
      }
    Error(_) -> Error(RegistryError("Failed to read temp directory"))
  })

  // 6. Extract tarball
  let extract_dir = tmp_dir <> "/extracted"
  use _ <- result.try(
    simplifile.create_directory_all(extract_dir)
    |> map_file_error(extract_dir),
  )
  use _ <- result.try(
    shell.exec(
      "tar xzf " <> shell_quote(tarball) <> " -C " <> shell_quote(extract_dir),
    )
    |> result.map_error(fn(e) {
      RegistryError("Failed to extract tarball: " <> e)
    }),
  )

  // 7. Find the skill directory (directory containing skill.yaml)
  use skill_dir <- result.try(find_skill_dir(extract_dir))

  // 8. Compile and emit
  use result_msg <- result.try(case target {
    Some(t) -> {
      use compiled <- result.try(compiler.compile(skill_dir, t))
      let name = compiled.name
      use _ <- result.try(compiler.emit(compiled, output_dir, name))
      Ok("Installed " <> name <> " (" <> t <> ") to " <> output_dir)
    }
    None -> {
      use compiled_list <- result.try(compiler.compile_all(skill_dir))
      use _ <- result.try(
        list.try_each(compiled_list, fn(compiled) {
          let name = compiled.name
          compiler.emit(compiled, output_dir, name)
        }),
      )
      let provider_names =
        list.map(compiled_list, fn(c) { types.provider_to_string(c.provider) })
      let name = case compiled_list {
        [first, ..] -> first.name
        [] -> "skill"
      }
      Ok(
        "Installed "
        <> name
        <> " ("
        <> string.join(provider_names, ", ")
        <> ") to "
        <> output_dir,
      )
    }
  })

  // 9. Check dependencies
  let dep_warnings = check_install_dependencies(skill_dir, output_dir)

  // 10. Clean up
  let _ = simplifile.delete(tmp_dir)

  Ok(result_msg <> dep_warnings)
}

pub fn parse_install_spec(
  spec: String,
) -> #(String, Option(String), Option(String)) {
  // Split off @version first if present
  let #(path, version) = case string.split_once(spec, "@") {
    Ok(#(p, v)) -> #(p, Some(v))
    Error(_) -> #(spec, None)
  }
  // Split path into segments: owner/repo or owner/repo/skill-name
  let segments = string.split(path, "/")
  case segments {
    [owner, repo, skill_name] ->
      #(owner <> "/" <> repo, Some(skill_name), version)
    _ -> #(path, None, version)
  }
}

fn resolve_install_tag(
  repo: String,
  skill_name: Option(String),
  version: Option(String),
) -> Result(String, SkillError) {
  case skill_name, version {
    // owner/repo@v1.0.0 — backward compat, download exact tag
    None, Some(v) -> Ok(" " <> shell_quote(v))
    // owner/repo — backward compat, latest release
    None, None -> Ok(" --latest")
    // owner/repo/skill@v1.0.0 — download tag {skill}-{version}
    Some(name), Some(v) -> Ok(" " <> shell_quote(name <> "-" <> v))
    // owner/repo/skill — find latest tag matching {skill}-v*
    Some(name), None -> {
      use output <- result.try(
        shell.exec(
          "gh release list --repo "
          <> shell_quote(repo)
          <> " --json tagName --jq "
          <> shell_quote(
            ".[] | select(.tagName | startswith(\""
            <> name
            <> "-v\")) | .tagName",
          ),
        )
        |> result.map_error(fn(e) {
          RegistryError("Failed to list releases: " <> e)
        }),
      )
      let tags =
        string.split(string.trim(output), "\n")
        |> list.filter(fn(t) { !string.is_empty(t) })
      case tags {
        [latest, ..] -> Ok(" " <> shell_quote(latest))
        [] ->
          Error(RegistryError(
            "No releases found for skill '" <> name <> "' in " <> repo,
          ))
      }
    }
  }
}

fn find_skill_dir(base_dir: String) -> Result(String, SkillError) {
  // Check if skill.yaml is directly in base_dir
  case simplifile.is_file(base_dir <> "/skill.yaml") {
    Ok(True) -> Ok(base_dir)
    _ -> {
      // Check one level of subdirectories
      case simplifile.read_directory(base_dir) {
        Ok(entries) -> {
          let found =
            list.find(entries, fn(entry) {
              case
                simplifile.is_file(base_dir <> "/" <> entry <> "/skill.yaml")
              {
                Ok(True) -> True
                _ -> False
              }
            })
          case found {
            Ok(entry) -> Ok(base_dir <> "/" <> entry)
            Error(_) ->
              Error(RegistryError("No skill.yaml found in extracted archive"))
          }
        }
        Error(_) -> Error(RegistryError("Failed to read extracted directory"))
      }
    }
  }
}

// ============================================================================
// List
// ============================================================================

pub fn list_versions(
  repo: String,
  skill_name: Option(String),
) -> Result(String, SkillError) {
  use _ <- result.try(require_gh())
  let jq_expr = case skill_name {
    Some(name) ->
      ".[] | select(.tagName | startswith(\""
      <> name
      <> "-v\")) | \"\\(.tagName)\\t\\(.publishedAt)\\(if .isLatest then \" (latest)\" else \"\" end)\""
    None ->
      ".[] | \"\\(.tagName)\\t\\(.publishedAt)\\(if .isLatest then \" (latest)\" else \"\" end)\""
  }
  use output <- result.try(
    shell.exec(
      "gh release list --repo "
      <> shell_quote(repo)
      <> " --json tagName,publishedAt,isLatest --jq "
      <> shell_quote(jq_expr),
    )
    |> result.map_error(fn(e) {
      RegistryError("Failed to list versions: " <> e)
    }),
  )
  let label = case skill_name {
    Some(name) -> name <> " in " <> repo
    None -> repo
  }
  case string.is_empty(string.trim(output)) {
    True -> Ok("No releases found for " <> label)
    False -> Ok(output)
  }
}

pub fn list_installed(output_dir: String) -> Result(String, SkillError) {
  case simplifile.read_directory(output_dir) {
    Error(_) -> Ok("No skills installed in " <> output_dir)
    Ok(entries) -> {
      let skills =
        list.flat_map(entries, fn(provider_dir) {
          let provider_path = output_dir <> "/" <> provider_dir
          case simplifile.read_directory(provider_path) {
            Ok(skill_entries) ->
              list.filter_map(skill_entries, fn(skill_name) {
                let skill_md_path =
                  provider_path <> "/" <> skill_name <> "/SKILL.md"
                case simplifile.is_file(skill_md_path) {
                  Ok(True) ->
                    Ok("  " <> skill_name <> " (" <> provider_dir <> ")")
                  _ -> Error(Nil)
                }
              })
            Error(_) -> []
          }
        })
      case skills {
        [] -> Ok("No skills installed in " <> output_dir)
        _ -> Ok("Installed skills:\n" <> string.join(skills, "\n"))
      }
    }
  }
}

fn check_install_dependencies(
  skill_dir: String,
  output_dir: String,
) -> String {
  case simplifile.read(skill_dir <> "/skill.yaml") {
    Ok(content) ->
      case parser.parse_skill_yaml(content) {
        Ok(skill) -> {
          let warnings = compiler.check_dependencies(skill, output_dir)
          case warnings {
            [] -> ""
            _ -> {
              let lines =
                list.filter_map(warnings, fn(w) {
                  case w {
                    types.MissingDependency(dep) ->
                      Ok(
                        "\nWarning: missing dependency '"
                        <> dep.name
                        <> "' ("
                        <> version_constraint.to_string(dep.version)
                        <> ")",
                      )
                    _ -> Error(Nil)
                  }
                })
              string.join(lines, "")
            }
          }
        }
        Error(_) -> ""
      }
    Error(_) -> ""
  }
}

// ============================================================================
// Helpers
// ============================================================================

fn require_gh() -> Result(Nil, SkillError) {
  shell.exec("gh --version")
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) {
    RegistryError(
      "GitHub CLI (gh) is not installed. Install it from https://cli.github.com",
    )
  })
}

fn shell_quote(s: String) -> String {
  shell.quote(s)
}
