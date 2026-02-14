import gleam/list
import gleam/result
import gleam/string
import simplifile
import skillc/error.{type SkillError, FileError, ProviderError}

const known_providers = ["openclaw", "claude-code", "codex"]

pub type ProviderWarning {
  UnknownProvider(name: String)
}

pub type DiscoveryResult {
  DiscoveryResult(providers: List(String), warnings: List(ProviderWarning))
}

pub fn discover_providers(
  skill_dir: String,
) -> Result(DiscoveryResult, SkillError) {
  let providers_dir = skill_dir <> "/providers"
  case simplifile.is_directory(providers_dir) {
    Ok(True) -> {
      use entries <- result.try(
        simplifile.read_directory(providers_dir)
        |> result.map_error(fn(e) { FileError(providers_dir, e) }),
      )
      let providers =
        list.filter(entries, fn(entry) {
          let metadata_path = providers_dir <> "/" <> entry <> "/metadata.yaml"
          case simplifile.is_file(metadata_path) {
            Ok(True) -> True
            _ -> False
          }
        })
        |> list.sort(string.compare)
      let warnings =
        list.filter_map(providers, fn(p) {
          case list.contains(known_providers, p) {
            True -> Error(Nil)
            False -> Ok(UnknownProvider(p))
          }
        })
      Ok(DiscoveryResult(providers: providers, warnings: warnings))
    }
    Ok(False) -> Ok(DiscoveryResult(providers: [], warnings: []))
    Error(_) -> Ok(DiscoveryResult(providers: [], warnings: []))
  }
}

pub fn is_supported(skill_dir: String, provider: String) -> Bool {
  let metadata_path =
    skill_dir <> "/providers/" <> provider <> "/metadata.yaml"
  case simplifile.is_file(metadata_path) {
    Ok(True) -> True
    _ -> False
  }
}

pub fn validate_provider(
  skill_dir: String,
  provider: String,
) -> Result(Nil, SkillError) {
  case is_supported(skill_dir, provider) {
    True -> Ok(Nil)
    False ->
      Error(ProviderError(
        provider,
        "Provider '" <> provider <> "' is not supported by this skill",
      ))
  }
}
