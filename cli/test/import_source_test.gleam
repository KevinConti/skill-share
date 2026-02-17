import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import skill_universe/error
import skill_universe/import_source.{
  BlobPath, GitHub, GitLab, LocalDirectory, LocalFile, RawPath,
  RemoteFileFallback, RemoteRepo, RepoRoot, TreePath, git_ref_value,
  locator_target_subpath, repo_id_value, repo_subpath_value, resolve,
}

pub fn resolve_github_shorthand_repo_test() {
  let assert Ok(source) = resolve("octocat/hello-world")
  case source {
    RemoteRepo(host:, locator:) -> {
      should.equal(host, GitHub)
      case locator {
        RepoRoot(repo:, ref:) -> {
          should.equal(repo_id_value(repo), "octocat/hello-world")
          should.equal(ref, None)
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn resolve_github_shorthand_path_defaults_head_ref_test() {
  let assert Ok(source) = resolve("octocat/hello-world/skills/demo")
  case source {
    RemoteRepo(host:, locator:) -> {
      should.equal(host, GitHub)
      case locator {
        TreePath(repo:, ref:, path:) -> {
          should.equal(repo_id_value(repo), "octocat/hello-world")
          should.equal(git_ref_value(ref), "HEAD")
          should.equal(repo_subpath_value(path), "skills/demo")
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn resolve_github_shorthand_path_with_ref_test() {
  let assert Ok(source) = resolve("octocat/hello-world/skills/demo@v1.2.3")
  case source {
    RemoteRepo(host:, locator:) -> {
      should.equal(host, GitHub)
      case locator {
        TreePath(ref:, path:, ..) -> {
          should.equal(git_ref_value(ref), "v1.2.3")
          should.equal(repo_subpath_value(path), "skills/demo")
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn resolve_gitlab_shorthand_test() {
  let assert Ok(source) = resolve("gitlab:group/project@v2")
  case source {
    RemoteRepo(host:, locator:) -> {
      should.equal(host, GitLab)
      case locator {
        RepoRoot(repo:, ref:) -> {
          should.equal(repo_id_value(repo), "group/project")
          case ref {
            Some(value) -> should.equal(git_ref_value(value), "v2")
            None -> should.fail()
          }
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn resolve_github_tree_url_test() {
  let assert Ok(source) =
    resolve("https://github.com/octocat/hello-world/tree/main/skills/demo")
  case source {
    RemoteRepo(host:, locator:) -> {
      should.equal(host, GitHub)
      case locator {
        TreePath(ref:, path:, ..) -> {
          should.equal(git_ref_value(ref), "main")
          should.equal(repo_subpath_value(path), "skills/demo")
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn resolve_github_blob_url_maps_to_parent_path_test() {
  let assert Ok(source) =
    resolve(
      "https://github.com/octocat/hello-world/blob/main/skills/demo/SKILL.md",
    )
  case source {
    RemoteRepo(locator:, ..) -> {
      case locator {
        BlobPath(file_path:, ..) -> {
          should.equal(repo_subpath_value(file_path), "skills/demo/SKILL.md")
          let assert Some(parent) = locator_target_subpath(locator)
          should.equal(repo_subpath_value(parent), "skills/demo")
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn resolve_github_raw_url_maps_to_parent_path_test() {
  let assert Ok(source) =
    resolve(
      "https://raw.githubusercontent.com/octocat/hello-world/main/skills/demo/SKILL.md",
    )
  case source {
    RemoteRepo(locator:, ..) -> {
      case locator {
        RawPath(file_path:, ..) -> {
          should.equal(repo_subpath_value(file_path), "skills/demo/SKILL.md")
          let assert Some(parent) = locator_target_subpath(locator)
          should.equal(repo_subpath_value(parent), "skills/demo")
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn resolve_gitlab_tree_url_test() {
  let assert Ok(source) =
    resolve("https://gitlab.com/group/project/-/tree/main/skills/demo")
  case source {
    RemoteRepo(host:, locator:) -> {
      should.equal(host, GitLab)
      case locator {
        TreePath(repo:, ref:, path:) -> {
          should.equal(repo_id_value(repo), "group/project")
          should.equal(git_ref_value(ref), "main")
          should.equal(repo_subpath_value(path), "skills/demo")
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn resolve_rejects_invalid_repo_subpath_test() {
  let result =
    resolve("https://github.com/octocat/hello-world/tree/main/../secrets")
  should.be_error(result)
  let assert Error(error.ImportError(_, msg)) = result
  should.be_true(string.contains(msg, "Invalid repository path segment"))
}

pub fn resolve_rejects_empty_ref_test() {
  let result = resolve("octocat/hello-world@")
  should.be_error(result)
  let assert Error(error.ImportError(_, msg)) = result
  should.be_true(string.contains(msg, "Git ref cannot be empty"))
}

pub fn resolve_local_directory_has_priority_over_shorthand_test() {
  let assert Ok(source) = resolve("test/fixtures/import-openclaw")
  case source {
    LocalDirectory(path:) -> should.equal(path, "test/fixtures/import-openclaw")
    _ -> should.fail()
  }
}

pub fn resolve_local_file_test() {
  let assert Ok(source) = resolve("test/fixtures/import-openclaw/SKILL.md")
  case source {
    LocalFile(path:) ->
      should.equal(path, "test/fixtures/import-openclaw/SKILL.md")
    _ -> should.fail()
  }
}

pub fn resolve_falls_back_to_generic_remote_file_test() {
  let assert Ok(source) = resolve("https://example.com/SKILL.md")
  case source {
    RemoteFileFallback(url:) ->
      should.equal(url, "https://example.com/SKILL.md")
    _ -> should.fail()
  }
}

pub fn resolve_gitlab_shorthand_requires_group_project_test() {
  let result = resolve("gitlab:group")
  should.be_error(result)
  let assert Error(error.ImportError(_, msg)) = result
  should.be_true(string.contains(msg, "group/project"))
}
