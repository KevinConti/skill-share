import gleam/int
import simplifile

pub type SkillError {
  ParseError(file: String, message: String)
  ValidationError(field: String, message: String)
  TemplateError(line: Int, message: String)
  ProviderError(provider: String, message: String)
  FileError(path: String, error: simplifile.FileError)
}

pub fn to_string(error: SkillError) -> String {
  case error {
    ParseError(file, message) -> "Parse error in " <> file <> ": " <> message
    ValidationError(field, message) ->
      "Validation error for field '" <> field <> "': " <> message
    TemplateError(line, message) ->
      "Template error at line "
      <> int.to_string(line)
      <> ": "
      <> message
    ProviderError(provider, message) ->
      "Provider error (" <> provider <> "): " <> message
    FileError(path, error) ->
      "File error at " <> path <> ": " <> simplifile.describe_error(error)
  }
}
