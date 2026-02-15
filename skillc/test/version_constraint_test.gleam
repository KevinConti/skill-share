import gleeunit/should
import skillc/version_constraint

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
