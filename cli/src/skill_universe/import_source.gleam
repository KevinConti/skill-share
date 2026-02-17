import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import skill_universe/error.{type SkillError, ImportError}
import skill_universe/path

pub type RemoteHost {
  GitHub
  GitLab
}

pub type RepoId {
  RepoId(value: String)
}

pub type GitRef {
  GitRef(value: String)
}

pub type RepoSubpath {
  RepoSubpath(value: String)
}

pub type RemoteLocator {
  RepoRoot(repo: RepoId, ref: Option(GitRef))
  TreePath(repo: RepoId, ref: GitRef, path: RepoSubpath)
  BlobPath(repo: RepoId, ref: GitRef, file_path: RepoSubpath)
  RawPath(repo: RepoId, ref: GitRef, file_path: RepoSubpath)
}

pub type ImportSource {
  LocalDirectory(path: String)
  LocalFile(path: String)
  RemoteRepo(host: RemoteHost, locator: RemoteLocator)
  RemoteFileFallback(url: String)
}

pub fn resolve(source: String) -> Result(ImportSource, SkillError) {
  let source = string.trim(source)
  case source {
    "" -> Error(ImportError("source", "Import source cannot be empty"))
    _ -> resolve_non_empty(source)
  }
}

fn resolve_non_empty(source: String) -> Result(ImportSource, SkillError) {
  case is_http_url(source) {
    True -> parse_remote_url(source)
    False -> {
      case string.starts_with(source, "gitlab:") {
        True -> parse_gitlab_shorthand(source)
        False -> resolve_local_or_github_shorthand(source)
      }
    }
  }
}

fn resolve_local_or_github_shorthand(
  source: String,
) -> Result(ImportSource, SkillError) {
  case simplifile.is_file(source) {
    Ok(True) -> Ok(LocalFile(path: source))
    _ -> {
      case simplifile.is_directory(source) {
        Ok(True) -> Ok(LocalDirectory(path: source))
        _ -> {
          case parse_github_shorthand(source) {
            Ok(Some(locator)) -> Ok(RemoteRepo(host: GitHub, locator: locator))
            Ok(None) -> Ok(LocalDirectory(path: source))
            Error(err) -> Error(err)
          }
        }
      }
    }
  }
}

fn parse_remote_url(url: String) -> Result(ImportSource, SkillError) {
  case is_host_url(url, "github.com") {
    True -> {
      use locator <- result.try(parse_github_url(url))
      Ok(RemoteRepo(host: GitHub, locator: locator))
    }
    False -> {
      case is_host_url(url, "raw.githubusercontent.com") {
        True -> {
          use locator <- result.try(parse_github_raw_url(url))
          Ok(RemoteRepo(host: GitHub, locator: locator))
        }
        False -> {
          case is_host_url(url, "gitlab.com") {
            True -> {
              use locator <- result.try(parse_gitlab_url(url))
              Ok(RemoteRepo(host: GitLab, locator: locator))
            }
            False -> Ok(RemoteFileFallback(url: url))
          }
        }
      }
    }
  }
}

fn parse_github_shorthand(
  source: String,
) -> Result(Option(RemoteLocator), SkillError) {
  case is_github_shorthand_candidate(source) {
    False -> Ok(None)
    True -> {
      use #(repo_part, maybe_ref) <- result.try(split_ref(source, source))
      let segments = split_segments(repo_part)
      case segments {
        [owner, repo, ..rest] -> {
          use repo_id <- result.try(make_repo_id(GitHub, [owner, repo], source))
          case rest {
            [] -> Ok(Some(RepoRoot(repo: repo_id, ref: maybe_ref)))
            _ -> {
              use skill_path <- result.try(make_repo_subpath(
                string.join(rest, "/"),
                source,
              ))
              let ref = case maybe_ref {
                Some(r) -> r
                None -> head_ref()
              }
              Ok(Some(TreePath(repo: repo_id, ref: ref, path: skill_path)))
            }
          }
        }
        _ -> Ok(None)
      }
    }
  }
}

fn parse_gitlab_shorthand(source: String) -> Result(ImportSource, SkillError) {
  let raw_spec = string.drop_start(source, 7)
  use #(repo_part, maybe_ref) <- result.try(split_ref(raw_spec, source))
  let segments = split_segments(repo_part)
  use repo_id <- result.try(make_repo_id(GitLab, segments, source))
  Ok(RemoteRepo(host: GitLab, locator: RepoRoot(repo: repo_id, ref: maybe_ref)))
}

fn parse_github_url(source: String) -> Result(RemoteLocator, SkillError) {
  use raw_path <- result.try(path_after_host(source, "github.com"))
  let segments = split_and_clean_url_path(raw_path)
  case segments {
    [owner, repo, ..rest] -> {
      use repo_id <- result.try(make_repo_id(GitHub, [owner, repo], source))
      case rest {
        [] -> Ok(RepoRoot(repo: repo_id, ref: None))
        ["tree", ref_raw, ..path_parts] -> {
          use ref <- result.try(make_git_ref(ref_raw, source))
          case path_parts {
            [] -> Ok(RepoRoot(repo: repo_id, ref: Some(ref)))
            _ -> {
              use skill_path <- result.try(make_repo_subpath(
                string.join(path_parts, "/"),
                source,
              ))
              Ok(TreePath(repo: repo_id, ref: ref, path: skill_path))
            }
          }
        }
        ["blob", ref_raw, first_path, ..more] -> {
          use ref <- result.try(make_git_ref(ref_raw, source))
          use file_path <- result.try(make_repo_subpath(
            string.join([first_path, ..more], "/"),
            source,
          ))
          Ok(BlobPath(repo: repo_id, ref: ref, file_path: file_path))
        }
        _ ->
          Error(ImportError(
            source,
            "Unsupported GitHub URL format. Use repo root, /tree/<ref>/<path>, or /blob/<ref>/<path>.",
          ))
      }
    }
    _ -> Error(ImportError(source, "GitHub URL must include owner/repo."))
  }
}

fn parse_github_raw_url(source: String) -> Result(RemoteLocator, SkillError) {
  use raw_path <- result.try(path_after_host(
    source,
    "raw.githubusercontent.com",
  ))
  let segments = split_and_clean_url_path(raw_path)
  case segments {
    [owner, repo, ref_raw, first_path, ..more] -> {
      use repo_id <- result.try(make_repo_id(GitHub, [owner, repo], source))
      use ref <- result.try(make_git_ref(ref_raw, source))
      use file_path <- result.try(make_repo_subpath(
        string.join([first_path, ..more], "/"),
        source,
      ))
      Ok(RawPath(repo: repo_id, ref: ref, file_path: file_path))
    }
    _ ->
      Error(ImportError(
        source,
        "Raw GitHub URL must include owner/repo/ref/path.",
      ))
  }
}

fn parse_gitlab_url(source: String) -> Result(RemoteLocator, SkillError) {
  use raw_path <- result.try(path_after_host(source, "gitlab.com"))
  let segments = split_and_clean_url_path(raw_path)

  case split_gitlab_operation(segments, []) {
    None -> {
      use repo_id <- result.try(make_repo_id(GitLab, segments, source))
      Ok(RepoRoot(repo: repo_id, ref: None))
    }
    Some(#(repo_parts, operation)) -> {
      use repo_id <- result.try(make_repo_id(GitLab, repo_parts, source))
      case operation {
        ["tree", ref_raw, ..path_parts] -> {
          use ref <- result.try(make_git_ref(ref_raw, source))
          case path_parts {
            [] -> Ok(RepoRoot(repo: repo_id, ref: Some(ref)))
            _ -> {
              use skill_path <- result.try(make_repo_subpath(
                string.join(path_parts, "/"),
                source,
              ))
              Ok(TreePath(repo: repo_id, ref: ref, path: skill_path))
            }
          }
        }
        ["blob", ref_raw, first_path, ..more] -> {
          use ref <- result.try(make_git_ref(ref_raw, source))
          use file_path <- result.try(make_repo_subpath(
            string.join([first_path, ..more], "/"),
            source,
          ))
          Ok(BlobPath(repo: repo_id, ref: ref, file_path: file_path))
        }
        ["raw", ref_raw, first_path, ..more] -> {
          use ref <- result.try(make_git_ref(ref_raw, source))
          use file_path <- result.try(make_repo_subpath(
            string.join([first_path, ..more], "/"),
            source,
          ))
          Ok(RawPath(repo: repo_id, ref: ref, file_path: file_path))
        }
        _ ->
          Error(ImportError(
            source,
            "Unsupported GitLab URL format. Use repo root, /-/tree/<ref>/<path>, /-/blob/<ref>/<path>, or /-/raw/<ref>/<path>.",
          ))
      }
    }
  }
}

fn split_gitlab_operation(
  segments: List(String),
  acc: List(String),
) -> Option(#(List(String), List(String))) {
  case segments {
    [] -> None
    ["-", ..rest] -> Some(#(list.reverse(acc), rest))
    [segment, ..rest] -> split_gitlab_operation(rest, [segment, ..acc])
  }
}

fn split_ref(
  source: String,
  error_source: String,
) -> Result(#(String, Option(GitRef)), SkillError) {
  case string.split_once(source, "@") {
    Ok(#(repo_part, ref_part)) -> {
      use ref <- result.try(make_git_ref(ref_part, error_source))
      Ok(#(repo_part, Some(ref)))
    }
    Error(_) -> Ok(#(source, None))
  }
}

fn make_repo_id(
  host: RemoteHost,
  parts: List(String),
  source: String,
) -> Result(RepoId, SkillError) {
  let parts = normalize_repo_parts(parts)
  use _ <- result.try(validate_repo_parts(parts, source))
  case host {
    GitHub ->
      case list.length(parts) == 2 {
        True -> Ok(RepoId(value: string.join(parts, "/")))
        False ->
          Error(ImportError(
            source,
            "GitHub source must be in owner/repo form (optionally with a path).",
          ))
      }
    GitLab ->
      case list.length(parts) >= 2 {
        True -> Ok(RepoId(value: string.join(parts, "/")))
        False ->
          Error(ImportError(
            source,
            "GitLab source must be in group/project form.",
          ))
      }
  }
}

fn validate_repo_parts(
  parts: List(String),
  source: String,
) -> Result(Nil, SkillError) {
  list.try_each(parts, fn(part) {
    validate_non_empty_segment(part, source, "repository path")
  })
}

fn make_git_ref(raw_ref: String, source: String) -> Result(GitRef, SkillError) {
  let ref = string.trim(raw_ref)
  case ref == "" {
    True -> Error(ImportError(source, "Git ref cannot be empty"))
    False ->
      case
        string.contains(ref, "/")
        || string.contains(ref, "\\")
        || string.contains(ref, " ")
        || ref == "."
        || ref == ".."
      {
        True ->
          Error(ImportError(
            source,
            "Invalid git ref '"
              <> ref
              <> "'. Use a branch/tag/commit without path separators.",
          ))
        False -> Ok(GitRef(value: ref))
      }
  }
}

fn make_repo_subpath(
  raw_path: String,
  source: String,
) -> Result(RepoSubpath, SkillError) {
  let normalized = path.normalize_separators(string.trim(raw_path))
  case normalized == "" || string.starts_with(normalized, "/") {
    True -> Error(ImportError(source, "Repository path must be relative"))
    False -> {
      let segments = split_segments(normalized)
      use _ <- result.try(
        list.try_each(segments, fn(segment) {
          validate_non_empty_segment(segment, source, "repository path")
        }),
      )
      Ok(RepoSubpath(value: string.join(segments, "/")))
    }
  }
}

fn validate_non_empty_segment(
  segment: String,
  source: String,
  label: String,
) -> Result(Nil, SkillError) {
  let trimmed = string.trim(segment)
  case
    trimmed == ""
    || segment == "."
    || segment == ".."
    || string.contains(segment, "\\")
    || string.contains(segment, ":")
    || trimmed != segment
  {
    True ->
      Error(ImportError(
        source,
        "Invalid " <> label <> " segment '" <> segment <> "'",
      ))
    False -> Ok(Nil)
  }
}

fn normalize_repo_parts(parts: List(String)) -> List(String) {
  case list.reverse(parts) {
    [] -> []
    [last, ..rest] -> list.reverse([strip_git_suffix(last), ..rest])
  }
}

fn strip_git_suffix(value: String) -> String {
  case string.ends_with(value, ".git") {
    True -> string.drop_end(value, 4)
    False -> value
  }
}

fn path_after_host(source: String, host: String) -> Result(String, SkillError) {
  case strip_host_prefix(source, host) {
    Some(path) -> Ok(strip_query_and_fragment(path))
    None -> Error(ImportError(source, "Expected URL for host " <> host))
  }
}

fn strip_host_prefix(source: String, host: String) -> Option(String) {
  let https_prefix = "https://" <> host <> "/"
  let http_prefix = "http://" <> host <> "/"
  case string.starts_with(source, https_prefix) {
    True -> Some(string.drop_start(source, string.length(https_prefix)))
    False ->
      case string.starts_with(source, http_prefix) {
        True -> Some(string.drop_start(source, string.length(http_prefix)))
        False -> None
      }
  }
}

fn strip_query_and_fragment(raw_path: String) -> String {
  let without_query = case string.split_once(raw_path, "?") {
    Ok(#(base, _)) -> base
    Error(_) -> raw_path
  }
  case string.split_once(without_query, "#") {
    Ok(#(base, _)) -> base
    Error(_) -> without_query
  }
}

fn split_and_clean_url_path(path: String) -> List(String) {
  split_segments(path)
  |> list.filter(fn(segment) { segment != "" })
}

fn split_segments(path_value: String) -> List(String) {
  path.normalize_separators(path_value)
  |> string.split("/")
}

fn is_http_url(source: String) -> Bool {
  string.starts_with(source, "http://")
  || string.starts_with(source, "https://")
}

fn is_host_url(source: String, host: String) -> Bool {
  string.starts_with(source, "https://" <> host <> "/")
  || string.starts_with(source, "http://" <> host <> "/")
}

fn is_github_shorthand_candidate(source: String) -> Bool {
  let source = path.normalize_separators(source)
  string.contains(source, "/")
  && !string.starts_with(source, "/")
  && !string.starts_with(source, "./")
  && !string.starts_with(source, "../")
  && !string.starts_with(source, "~/")
  && !string.contains(source, " ")
  && !string.contains(source, ":")
}

fn head_ref() -> GitRef {
  GitRef(value: "HEAD")
}

fn parent_subpath(file_path: RepoSubpath) -> Option(RepoSubpath) {
  let parent = path.parent_dir(repo_subpath_value(file_path))
  case parent {
    "." -> None
    "/" -> None
    _ -> Some(RepoSubpath(value: parent))
  }
}

pub fn host_to_string(host: RemoteHost) -> String {
  case host {
    GitHub -> "github"
    GitLab -> "gitlab"
  }
}

pub fn repo_id_value(repo: RepoId) -> String {
  repo.value
}

pub fn git_ref_value(ref: GitRef) -> String {
  ref.value
}

pub fn repo_subpath_value(path: RepoSubpath) -> String {
  path.value
}

pub fn locator_repo(locator: RemoteLocator) -> RepoId {
  case locator {
    RepoRoot(repo:, ..) -> repo
    TreePath(repo:, ..) -> repo
    BlobPath(repo:, ..) -> repo
    RawPath(repo:, ..) -> repo
  }
}

pub fn locator_ref(locator: RemoteLocator) -> Option(GitRef) {
  case locator {
    RepoRoot(ref:, ..) -> ref
    TreePath(ref:, ..) -> Some(ref)
    BlobPath(ref:, ..) -> Some(ref)
    RawPath(ref:, ..) -> Some(ref)
  }
}

pub fn locator_target_subpath(locator: RemoteLocator) -> Option(RepoSubpath) {
  case locator {
    RepoRoot(..) -> None
    TreePath(path:, ..) -> Some(path)
    BlobPath(file_path:, ..) -> parent_subpath(file_path)
    RawPath(file_path:, ..) -> parent_subpath(file_path)
  }
}
