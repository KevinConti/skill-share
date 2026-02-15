import gleam/string
import skillc/error.{type SkillError, ValidationError}
import skillc/semver

/// An opaque type representing a dependency version constraint (e.g. "^1.0.0",
/// "~2.0.0", "*"). The opaque wrapper ensures version constraints can only be
/// created through `parse` or `wildcard`, distinguishing them from arbitrary
/// strings at the type level.
pub opaque type VersionConstraint {
  VersionConstraint(String)
}

/// Parse a version constraint string. Empty/whitespace-only strings are
/// normalized to the wildcard constraint "*". Returns an error if the
/// constraint uses an unrecognized operator.
pub fn parse(input: String) -> Result(VersionConstraint, SkillError) {
  let trimmed = string.trim(input)
  case string.is_empty(trimmed) {
    True -> Ok(VersionConstraint("*"))
    False -> validate(trimmed)
  }
}

/// The wildcard constraint, matching any version.
pub fn wildcard() -> VersionConstraint {
  VersionConstraint("*")
}

/// Convert back to the underlying string representation.
pub fn to_string(vc: VersionConstraint) -> String {
  let VersionConstraint(s) = vc
  s
}

fn validate(input: String) -> Result(VersionConstraint, SkillError) {
  case input {
    "*" -> Ok(VersionConstraint(input))
    "^" <> rest -> validate_has_version(rest, input)
    "~" <> rest -> validate_has_version(rest, input)
    ">=" <> rest -> validate_has_version(rest, input)
    "<=" <> rest -> validate_has_version(rest, input)
    ">" <> rest -> validate_has_version(rest, input)
    "<" <> rest -> validate_has_version(rest, input)
    "=" <> rest -> validate_has_version(rest, input)
    _ -> validate_bare_version(input)
  }
}

fn validate_has_version(
  rest: String,
  original: String,
) -> Result(VersionConstraint, SkillError) {
  let version_part = string.trim(rest)
  case string.is_empty(version_part) {
    True ->
      Error(ValidationError(
        "version",
        "Invalid version constraint: operator without version in '"
          <> original
          <> "'",
      ))
    False ->
      case semver.parse(version_part) {
        Ok(_) -> Ok(VersionConstraint(original))
        Error(_) ->
          Error(ValidationError(
            "version",
            "Invalid version in constraint: '" <> original <> "'",
          ))
      }
  }
}

fn validate_bare_version(input: String) -> Result(VersionConstraint, SkillError) {
  case semver.parse(input) {
    Ok(_) -> Ok(VersionConstraint(input))
    Error(_) ->
      Error(ValidationError(
        "version",
        "Invalid version constraint: '"
          <> input
          <> "' (expected valid semver like 1.0.0)",
      ))
  }
}
