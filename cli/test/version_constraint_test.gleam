import gleeunit/should
import skill_universe/semver
import skill_universe/version_constraint

// ============================================================================
// Parsing
// ============================================================================

pub fn parse_caret_test() {
  should.be_ok(version_constraint.parse("^1.0.0"))
}

pub fn parse_tilde_test() {
  should.be_ok(version_constraint.parse("~2.0.0"))
}

pub fn parse_gte_test() {
  should.be_ok(version_constraint.parse(">=1.0.0"))
}

pub fn parse_bare_version_test() {
  should.be_ok(version_constraint.parse("1.0.0"))
}

pub fn parse_wildcard_test() {
  should.be_ok(version_constraint.parse("*"))
}

pub fn parse_empty_normalizes_to_wildcard_test() {
  let assert Ok(vc) = version_constraint.parse("")
  should.equal(version_constraint.to_string(vc), "*")
}

pub fn parse_caret_without_version_fails_test() {
  should.be_error(version_constraint.parse("^"))
}

pub fn parse_tilde_without_version_fails_test() {
  should.be_error(version_constraint.parse("~"))
}

pub fn parse_invalid_semver_fails_test() {
  should.be_error(version_constraint.parse("1.0"))
}

pub fn parse_not_semver_fails_test() {
  should.be_error(version_constraint.parse("1not-semver"))
}

pub fn parse_unsupported_operator_fails_test() {
  should.be_error(version_constraint.parse("!1.0.0"))
}

pub fn wildcard_to_string_test() {
  should.equal(version_constraint.to_string(version_constraint.wildcard()), "*")
}

pub fn wildcard_equality_test() {
  let assert Ok(vc) = version_constraint.parse("")
  should.equal(vc, version_constraint.wildcard())
}

pub fn to_string_caret_test() {
  let assert Ok(vc) = version_constraint.parse("^1.2.3")
  should.equal(version_constraint.to_string(vc), "^1.2.3")
}

pub fn to_string_tilde_test() {
  let assert Ok(vc) = version_constraint.parse("~1.2.3")
  should.equal(version_constraint.to_string(vc), "~1.2.3")
}

pub fn to_string_gte_test() {
  let assert Ok(vc) = version_constraint.parse(">=1.0.0")
  should.equal(version_constraint.to_string(vc), ">=1.0.0")
}

pub fn to_string_exact_bare_test() {
  let assert Ok(vc) = version_constraint.parse("1.0.0")
  should.equal(version_constraint.to_string(vc), "1.0.0")
}

// ============================================================================
// Satisfies — Wildcard
// ============================================================================

pub fn satisfies_wildcard_any_version_test() {
  let assert Ok(v) = semver.parse("99.99.99")
  let vc = version_constraint.wildcard()
  should.be_true(version_constraint.satisfies(v, vc))
}

// ============================================================================
// Satisfies — Exact
// ============================================================================

pub fn satisfies_exact_match_test() {
  let assert Ok(v) = semver.parse("1.0.0")
  let assert Ok(vc) = version_constraint.parse("1.0.0")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_exact_no_match_test() {
  let assert Ok(v) = semver.parse("1.0.1")
  let assert Ok(vc) = version_constraint.parse("1.0.0")
  should.be_false(version_constraint.satisfies(v, vc))
}

// ============================================================================
// Satisfies — Comparison operators
// ============================================================================

pub fn satisfies_gte_equal_test() {
  let assert Ok(v) = semver.parse("1.0.0")
  let assert Ok(vc) = version_constraint.parse(">=1.0.0")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_gte_greater_test() {
  let assert Ok(v) = semver.parse("2.0.0")
  let assert Ok(vc) = version_constraint.parse(">=1.0.0")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_gte_less_test() {
  let assert Ok(v) = semver.parse("0.9.9")
  let assert Ok(vc) = version_constraint.parse(">=1.0.0")
  should.be_false(version_constraint.satisfies(v, vc))
}

pub fn satisfies_lte_test() {
  let assert Ok(v) = semver.parse("1.0.0")
  let assert Ok(vc) = version_constraint.parse("<=1.0.0")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_lte_greater_fails_test() {
  let assert Ok(v) = semver.parse("1.0.1")
  let assert Ok(vc) = version_constraint.parse("<=1.0.0")
  should.be_false(version_constraint.satisfies(v, vc))
}

pub fn satisfies_gt_test() {
  let assert Ok(v) = semver.parse("1.0.1")
  let assert Ok(vc) = version_constraint.parse(">1.0.0")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_gt_equal_fails_test() {
  let assert Ok(v) = semver.parse("1.0.0")
  let assert Ok(vc) = version_constraint.parse(">1.0.0")
  should.be_false(version_constraint.satisfies(v, vc))
}

pub fn satisfies_lt_test() {
  let assert Ok(v) = semver.parse("0.9.9")
  let assert Ok(vc) = version_constraint.parse("<1.0.0")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_lt_equal_fails_test() {
  let assert Ok(v) = semver.parse("1.0.0")
  let assert Ok(vc) = version_constraint.parse("<1.0.0")
  should.be_false(version_constraint.satisfies(v, vc))
}

// ============================================================================
// Satisfies — Caret
// ============================================================================

pub fn satisfies_caret_exact_test() {
  let assert Ok(v) = semver.parse("1.2.3")
  let assert Ok(vc) = version_constraint.parse("^1.2.3")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_caret_patch_bump_test() {
  let assert Ok(v) = semver.parse("1.2.4")
  let assert Ok(vc) = version_constraint.parse("^1.2.3")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_caret_minor_bump_test() {
  let assert Ok(v) = semver.parse("1.9.0")
  let assert Ok(vc) = version_constraint.parse("^1.2.3")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_caret_major_bump_fails_test() {
  let assert Ok(v) = semver.parse("2.0.0")
  let assert Ok(vc) = version_constraint.parse("^1.2.3")
  should.be_false(version_constraint.satisfies(v, vc))
}

pub fn satisfies_caret_lower_fails_test() {
  let assert Ok(v) = semver.parse("1.2.2")
  let assert Ok(vc) = version_constraint.parse("^1.2.3")
  should.be_false(version_constraint.satisfies(v, vc))
}

pub fn satisfies_caret_zero_minor_pins_minor_test() {
  // ^0.2.3 means >=0.2.3, <0.3.0
  let assert Ok(v1) = semver.parse("0.2.5")
  let assert Ok(v2) = semver.parse("0.3.0")
  let assert Ok(vc) = version_constraint.parse("^0.2.3")
  should.be_true(version_constraint.satisfies(v1, vc))
  should.be_false(version_constraint.satisfies(v2, vc))
}

pub fn satisfies_caret_zero_zero_pins_patch_test() {
  // ^0.0.3 means >=0.0.3, <0.0.4
  let assert Ok(v1) = semver.parse("0.0.3")
  let assert Ok(v2) = semver.parse("0.0.4")
  let assert Ok(vc) = version_constraint.parse("^0.0.3")
  should.be_true(version_constraint.satisfies(v1, vc))
  should.be_false(version_constraint.satisfies(v2, vc))
}

// ============================================================================
// Satisfies — Tilde
// ============================================================================

pub fn satisfies_tilde_exact_test() {
  let assert Ok(v) = semver.parse("1.2.3")
  let assert Ok(vc) = version_constraint.parse("~1.2.3")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_tilde_patch_bump_test() {
  let assert Ok(v) = semver.parse("1.2.9")
  let assert Ok(vc) = version_constraint.parse("~1.2.3")
  should.be_true(version_constraint.satisfies(v, vc))
}

pub fn satisfies_tilde_minor_bump_fails_test() {
  let assert Ok(v) = semver.parse("1.3.0")
  let assert Ok(vc) = version_constraint.parse("~1.2.3")
  should.be_false(version_constraint.satisfies(v, vc))
}

pub fn satisfies_tilde_lower_fails_test() {
  let assert Ok(v) = semver.parse("1.2.2")
  let assert Ok(vc) = version_constraint.parse("~1.2.3")
  should.be_false(version_constraint.satisfies(v, vc))
}

// ============================================================================
// Satisfies — Prerelease
// ============================================================================

pub fn satisfies_prerelease_lower_precedence_test() {
  // 1.0.0-alpha < 1.0.0, so ^1.0.0 should not match 1.0.0-alpha
  // (prerelease version is less than the release)
  let assert Ok(v) = semver.parse("1.0.0-alpha")
  let assert Ok(vc) = version_constraint.parse("^1.0.0")
  should.be_false(version_constraint.satisfies(v, vc))
}
