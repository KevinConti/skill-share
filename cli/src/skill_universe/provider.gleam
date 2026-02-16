import gleam/list
import gleam/result
import gleam/string
import simplifile
import skill_universe/error.{type SkillError, FileError, ProviderError}
import skill_universe/types.{type Provider}

pub fn discover_providers(
  skill_dir: String,
) -> Result(List(Provider), SkillError) {
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
        |> list.filter_map(types.provider_from_string)
      Ok(providers)
    }
    Ok(False) -> Ok([])
    Error(_) -> Ok([])
  }
}

pub fn is_supported(skill_dir: String, provider: Provider) -> Bool {
  let provider_name = types.provider_to_string(provider)
  let metadata_path =
    skill_dir <> "/providers/" <> provider_name <> "/metadata.yaml"
  case simplifile.is_file(metadata_path) {
    Ok(True) -> True
    _ -> False
  }
}

pub fn validate_provider(
  skill_dir: String,
  provider: Provider,
) -> Result(Nil, SkillError) {
  let provider_name = types.provider_to_string(provider)
  case is_supported(skill_dir, provider) {
    True -> Ok(Nil)
    False ->
      Error(ProviderError(
        provider_name,
        "Provider '" <> provider_name <> "' is not supported by this skill",
      ))
  }
}
