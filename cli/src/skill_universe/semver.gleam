import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}
import gleam/result
import gleam/string
import skill_universe/error.{type SkillError, ValidationError}

pub opaque type SemVer {
  SemVer(
    major: Int,
    minor: Int,
    patch: Int,
    prerelease: Option(String),
    build: Option(String),
  )
}

pub fn new(major: Int, minor: Int, patch: Int) -> Result(SemVer, SkillError) {
  case major >= 0, minor >= 0, patch >= 0 {
    True, True, True ->
      Ok(SemVer(
        major: major,
        minor: minor,
        patch: patch,
        prerelease: None,
        build: None,
      ))
    _, _, _ ->
      Error(ValidationError("version", "SemVer components must be non-negative"))
  }
}

pub fn prerelease(ver: SemVer) -> Option(String) {
  ver.prerelease
}

pub fn parse(version: String) -> Result(SemVer, SkillError) {
  // Strip build metadata first (after +), then pre-release (after -)
  // Must handle + before - because build metadata can contain dashes
  let #(without_build, build) = case string.split_once(version, "+") {
    Ok(#(before, after)) ->
      case after {
        "" -> #(Error(Nil), None)
        _ -> #(Ok(before), Some(after))
      }
    Error(_) -> #(Ok(version), None)
  }
  use without_build <- result.try(
    without_build
    |> result.map_error(fn(_) {
      ValidationError("version", "Invalid semver format: " <> version)
    }),
  )
  let #(base, prerelease) = case string.split_once(without_build, "-") {
    Ok(#(before, after)) ->
      case after {
        "" -> #(Error(Nil), None)
        _ -> #(Ok(before), Some(after))
      }
    Error(_) -> #(Ok(without_build), None)
  }
  use base <- result.try(
    base
    |> result.map_error(fn(_) {
      ValidationError("version", "Invalid semver format: " <> version)
    }),
  )
  let parts = string.split(base, ".")
  case parts {
    [major_s, minor_s, patch_s] -> {
      case
        is_valid_semver_number(major_s),
        is_valid_semver_number(minor_s),
        is_valid_semver_number(patch_s)
      {
        True, True, True -> {
          let assert Ok(major) = int.parse(major_s)
          let assert Ok(minor) = int.parse(minor_s)
          let assert Ok(patch) = int.parse(patch_s)
          Ok(SemVer(
            major: major,
            minor: minor,
            patch: patch,
            prerelease: prerelease,
            build: build,
          ))
        }
        _, _, _ -> return_semver_error(version)
      }
    }
    _ -> return_semver_error(version)
  }
}

pub fn to_string(ver: SemVer) -> String {
  let base =
    int.to_string(ver.major)
    <> "."
    <> int.to_string(ver.minor)
    <> "."
    <> int.to_string(ver.patch)
  let with_pre = case ver.prerelease {
    Some(pre) -> base <> "-" <> pre
    None -> base
  }
  case ver.build {
    Some(b) -> with_pre <> "+" <> b
    None -> with_pre
  }
}

pub fn major(ver: SemVer) -> Int {
  ver.major
}

pub fn minor(ver: SemVer) -> Int {
  ver.minor
}

pub fn patch(ver: SemVer) -> Int {
  ver.patch
}

pub fn compare(a: SemVer, b: SemVer) -> Order {
  case int.compare(a.major, b.major) {
    order.Eq ->
      case int.compare(a.minor, b.minor) {
        order.Eq ->
          case int.compare(a.patch, b.patch) {
            order.Eq -> compare_prerelease(a.prerelease, b.prerelease)
            other -> other
          }
        other -> other
      }
    other -> other
  }
}

fn compare_prerelease(a: Option(String), b: Option(String)) -> Order {
  case a, b {
    // No prerelease on either — equal
    None, None -> order.Eq
    // Prerelease has lower precedence than release
    Some(_), None -> order.Lt
    None, Some(_) -> order.Gt
    // Both have prerelease — compare lexicographically
    Some(pa), Some(pb) -> string.compare(pa, pb)
  }
}

fn return_semver_error(version: String) -> Result(a, SkillError) {
  Error(ValidationError("version", "Invalid semver format: " <> version))
}

fn is_valid_semver_number(s: String) -> Bool {
  case s {
    "" -> False
    "0" -> True
    _ ->
      !string.starts_with(s, "0")
      && !string.starts_with(s, "-")
      && result.is_ok(int.parse(s))
  }
}
