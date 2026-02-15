import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import skillc/compiler
import skillc/error.{type SkillError, RegistryError, map_file_error}
import skillc/parser
import skillc/path
import skillc/semver
import skillc/shell
import skillc/types

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
  let tag = "v" <> version_str
  let tarball_name = skill.name <> "-" <> version_str <> ".tar.gz"
  let tarball_path = "/tmp/" <> tarball_name

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
      <> shell_quote("Published by skillc"),
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
      "gh search repos --topic skillc-skill "
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

  // 1. Parse spec: "owner/repo" or "owner/repo@v1.0.0"
  let #(repo, version) = parse_install_spec(spec)

  // 2. Create temp directory
  let tmp_dir = "/tmp/skillc-install-" <> string.replace(repo, "/", "-")
  let _ = simplifile.delete(tmp_dir)
  use _ <- result.try(
    simplifile.create_directory_all(tmp_dir)
    |> map_file_error(tmp_dir),
  )

  // 3. Download release tarball
  let version_flag = case version {
    Some(v) -> " " <> shell_quote(v)
    None -> " --latest"
  }
  use _ <- result.try(
    shell.exec(
      "gh release download"
      <> version_flag
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

  // 4. Find the downloaded tarball
  use tarball <- result.try(case simplifile.get_files(tmp_dir) {
    Ok(files) ->
      case list.find(files, fn(f) { string.ends_with(f, ".tar.gz") }) {
        Ok(f) -> Ok(f)
        Error(_) ->
          Error(RegistryError("No tarball found in downloaded release"))
      }
    Error(_) -> Error(RegistryError("Failed to read temp directory"))
  })

  // 5. Extract tarball
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

  // 6. Find the skill directory (directory containing skill.yaml)
  use skill_dir <- result.try(find_skill_dir(extract_dir))

  // 7. Compile and emit
  use result_msg <- result.try(case target {
    Some(t) -> {
      use compiled <- result.try(compiler.compile(skill_dir, t))
      let name = types.extract_name(compiled)
      use _ <- result.try(compiler.emit(compiled, output_dir, name))
      Ok("Installed " <> name <> " (" <> t <> ") to " <> output_dir)
    }
    None -> {
      use compiled_list <- result.try(compiler.compile_all(skill_dir))
      use _ <- result.try(
        list.try_each(compiled_list, fn(compiled) {
          let name = types.extract_name(compiled)
          compiler.emit(compiled, output_dir, name)
        }),
      )
      let provider_names =
        list.map(compiled_list, fn(c) { types.provider_to_string(c.provider) })
      let name = case compiled_list {
        [first, ..] -> types.extract_name(first)
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

  // 8. Clean up
  let _ = simplifile.delete(tmp_dir)

  Ok(result_msg)
}

pub fn parse_install_spec(spec: String) -> #(String, Option(String)) {
  case string.split_once(spec, "@") {
    Ok(#(repo, version)) -> #(repo, Some(version))
    Error(_) -> #(spec, None)
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

pub fn list_versions(repo: String) -> Result(String, SkillError) {
  use _ <- result.try(require_gh())
  use output <- result.try(
    shell.exec(
      "gh release list --repo "
      <> shell_quote(repo)
      <> " --json tagName,publishedAt,isLatest --jq "
      <> shell_quote(
        ".[] | \"\\(.tagName)\\t\\(.publishedAt)\\(if .isLatest then \" (latest)\" else \"\" end)\"",
      ),
    )
    |> result.map_error(fn(e) {
      RegistryError("Failed to list versions: " <> e)
    }),
  )
  case string.is_empty(string.trim(output)) {
    True -> Ok("No releases found for " <> repo)
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
