import gleam/order
import gleam/result
import gleam/string
import skill_universe/error.{type SkillError, ValidationError}
import skill_universe/semver.{type SemVer}

type ConstraintOp {
  Caret(SemVer)
  Tilde(SemVer)
  Gte(SemVer)
  Lte(SemVer)
  Gt(SemVer)
  Lt(SemVer)
  Exact(SemVer)
  Wildcard
}

/// An opaque type representing a dependency version constraint (e.g. "^1.0.0",
/// "~2.0.0", "*"). The opaque wrapper ensures version constraints can only be
/// created through `parse` or `wildcard`, distinguishing them from arbitrary
/// strings at the type level.
pub opaque type VersionConstraint {
  VersionConstraint(op: ConstraintOp)
}

/// Parse a version constraint string. Empty/whitespace-only strings are
/// normalized to the wildcard constraint "*". Returns an error if the
/// constraint uses an unrecognized operator.
pub fn parse(input: String) -> Result(VersionConstraint, SkillError) {
  let trimmed = string.trim(input)
  case string.is_empty(trimmed) {
    True -> Ok(VersionConstraint(Wildcard))
    False -> validate(trimmed)
  }
}

/// The wildcard constraint, matching any version.
pub fn wildcard() -> VersionConstraint {
  VersionConstraint(Wildcard)
}

/// Convert back to the underlying string representation.
pub fn to_string(vc: VersionConstraint) -> String {
  case vc.op {
    Caret(v) -> "^" <> semver.to_string(v)
    Tilde(v) -> "~" <> semver.to_string(v)
    Gte(v) -> ">=" <> semver.to_string(v)
    Lte(v) -> "<=" <> semver.to_string(v)
    Gt(v) -> ">" <> semver.to_string(v)
    Lt(v) -> "<" <> semver.to_string(v)
    Exact(v) -> semver.to_string(v)
    Wildcard -> "*"
  }
}

/// Check if a version satisfies a constraint.
pub fn satisfies(version: SemVer, constraint: VersionConstraint) -> Bool {
  case constraint.op {
    Wildcard -> True
    Exact(v) -> semver.compare(version, v) == order.Eq
    Gte(v) -> semver.compare(version, v) != order.Lt
    Lte(v) -> semver.compare(version, v) != order.Gt
    Gt(v) -> semver.compare(version, v) == order.Gt
    Lt(v) -> semver.compare(version, v) == order.Lt
    Caret(v) -> satisfies_caret(version, v)
    Tilde(v) -> satisfies_tilde(version, v)
  }
}

fn satisfies_caret(version: SemVer, constraint: SemVer) -> Bool {
  // ^X.Y.Z: >=X.Y.Z and <next_major (when X>0)
  // ^0.Y.Z: >=0.Y.Z and <0.(Y+1).0 (when X==0, Y>0)
  // ^0.0.Z: >=0.0.Z and <0.0.(Z+1) (when X==0, Y==0)
  case semver.compare(version, constraint) {
    order.Lt -> False
    _ -> {
      let upper = case semver.major(constraint) {
        0 ->
          case semver.minor(constraint) {
            0 -> semver.new(0, 0, semver.patch(constraint) + 1)
            minor -> semver.new(0, minor + 1, 0)
          }
        major -> semver.new(major + 1, 0, 0)
      }
      case upper {
        Ok(upper_ver) -> semver.compare(version, upper_ver) == order.Lt
        Error(_) -> False
      }
    }
  }
}

fn satisfies_tilde(version: SemVer, constraint: SemVer) -> Bool {
  // ~X.Y.Z: >=X.Y.Z and <X.(Y+1).0
  case semver.compare(version, constraint) {
    order.Lt -> False
    _ -> {
      case
        semver.new(semver.major(constraint), semver.minor(constraint) + 1, 0)
      {
        Ok(upper) -> semver.compare(version, upper) == order.Lt
        Error(_) -> False
      }
    }
  }
}

fn validate(input: String) -> Result(VersionConstraint, SkillError) {
  case input {
    "*" -> Ok(VersionConstraint(Wildcard))
    "^" <> rest -> validate_has_version(rest, input, Caret)
    "~" <> rest -> validate_has_version(rest, input, Tilde)
    ">=" <> rest -> validate_has_version(rest, input, Gte)
    "<=" <> rest -> validate_has_version(rest, input, Lte)
    ">" <> rest -> validate_has_version(rest, input, Gt)
    "<" <> rest -> validate_has_version(rest, input, Lt)
    "=" <> rest -> validate_has_version(rest, input, Exact)
    _ -> validate_bare_version(input)
  }
}

fn validate_has_version(
  rest: String,
  original: String,
  make_op: fn(SemVer) -> ConstraintOp,
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
    False -> {
      use ver <- result.try(
        semver.parse(version_part)
        |> result.map_error(fn(_) {
          ValidationError(
            "version",
            "Invalid version in constraint: '" <> original <> "'",
          )
        }),
      )
      Ok(VersionConstraint(make_op(ver)))
    }
  }
}

fn validate_bare_version(input: String) -> Result(VersionConstraint, SkillError) {
  case semver.parse(input) {
    Ok(ver) -> Ok(VersionConstraint(Exact(ver)))
    Error(_) ->
      Error(ValidationError(
        "version",
        "Invalid version constraint: '"
          <> input
          <> "' (expected valid semver like 1.0.0)",
      ))
  }
}
