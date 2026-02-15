import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile
import skillc/error
import skillc/parser
import skillc/types

// ============================================================================
// §1.1 skill.yaml Parsing
// ============================================================================

pub fn parse_valid_skill_yaml_test() {
  let content = read_fixture("valid-skill/skill.yaml")
  let result = parser.parse_skill_yaml(content)
  let assert Ok(skill) = result
  should.equal(skill.name, "test-skill")
  should.equal(skill.description, "A test skill for validation")
  should.equal(skill.version, "1.2.3")
  should.equal(skill.license, Some("MIT"))
  should.equal(skill.homepage, Some("https://example.com/test-skill"))
  should.equal(skill.repository, Some("https://github.com/example/test-skill"))
}

pub fn parse_valid_skill_yaml_metadata_test() {
  let content = read_fixture("valid-skill/skill.yaml")
  let assert Ok(skill) = parser.parse_skill_yaml(content)
  let assert Some(metadata) = skill.metadata
  should.equal(metadata.author, Some("Test Author"))
  should.equal(metadata.author_email, Some("test@example.com"))
  should.equal(metadata.tags, ["test", "example", "demo"])
}

pub fn parse_valid_skill_yaml_dependencies_test() {
  let content = read_fixture("valid-skill/skill.yaml")
  let assert Ok(skill) = parser.parse_skill_yaml(content)
  should.equal(
    skill.dependencies,
    [
      types.Dependency(name: "helper-skill", version: "^1.0.0", optional: False),
      types.Dependency(name: "extra-skill", version: "~2.1.0", optional: True),
    ],
  )
}

pub fn parse_valid_skill_yaml_config_test() {
  let content = read_fixture("valid-skill/skill.yaml")
  let assert Ok(skill) = parser.parse_skill_yaml(content)
  should.equal(
    skill.config,
    [
      types.ConfigField(
        name: "api_key",
        description: "API key for authentication",
        required: True,
        secret: True,
        default: None,
      ),
      types.ConfigField(
        name: "timeout",
        description: "Request timeout in seconds",
        required: False,
        secret: False,
        default: Some("30"),
      ),
    ],
  )
}

pub fn parse_minimal_skill_yaml_test() {
  let content = read_fixture("minimal-skill/skill.yaml")
  let assert Ok(skill) = parser.parse_skill_yaml(content)
  should.equal(skill.name, "minimal")
  should.equal(skill.description, "A minimal skill")
  should.equal(skill.version, "0.1.0")
  should.equal(skill.license, None)
  should.equal(skill.homepage, None)
  should.equal(skill.repository, None)
  should.equal(skill.metadata, None)
  should.equal(skill.dependencies, [])
  should.equal(skill.config, [])
}

pub fn parse_invalid_yaml_fails_test() {
  let content = read_fixture("invalid-yaml/skill.yaml")
  let result = parser.parse_skill_yaml(content)
  should.be_error(result)
  let assert Error(error.ParseError(file, _msg)) = result
  should.equal(file, "skill.yaml")
}

pub fn parse_missing_name_fails_test() {
  let content = read_fixture("missing-name/skill.yaml")
  let result = parser.parse_skill_yaml(content)
  should.be_error(result)
  let assert Error(error.ValidationError(field, msg)) = result
  should.equal(field, "name")
  should.be_true(string.contains(msg, "name"))
}

pub fn parse_missing_description_fails_test() {
  let content = read_fixture("missing-description/skill.yaml")
  let result = parser.parse_skill_yaml(content)
  should.be_error(result)
  let assert Error(error.ValidationError(field, msg)) = result
  should.equal(field, "description")
  should.be_true(string.contains(msg, "description"))
}

pub fn parse_missing_version_fails_test() {
  let content = read_fixture("missing-version/skill.yaml")
  let result = parser.parse_skill_yaml(content)
  should.be_error(result)
  let assert Error(error.ValidationError(field, msg)) = result
  should.equal(field, "version")
  should.be_true(string.contains(msg, "version"))
}

pub fn parse_empty_yaml_fails_test() {
  let result = parser.parse_skill_yaml("")
  should.be_error(result)
}

// ============================================================================
// §1.2 Field Validation
// ============================================================================

pub fn valid_semver_test() {
  should.be_ok(parser.validate_semver("1.0.0"))
  should.be_ok(parser.validate_semver("0.1.0"))
  should.be_ok(parser.validate_semver("10.20.30"))
}

pub fn valid_semver_prerelease_test() {
  should.be_ok(parser.validate_semver("1.0.0-alpha"))
  should.be_ok(parser.validate_semver("1.0.0-beta.1"))
}

pub fn valid_semver_build_metadata_test() {
  should.be_ok(parser.validate_semver("1.0.0+build"))
  should.be_ok(parser.validate_semver("1.0.0+build.123"))
}

pub fn valid_semver_build_metadata_with_dashes_test() {
  // Build metadata can contain dashes — must strip + before -
  should.be_ok(parser.validate_semver("1.0.0+build-123"))
  should.be_ok(parser.validate_semver("1.0.0+20130313144700-abc"))
}

pub fn valid_semver_prerelease_and_build_test() {
  should.be_ok(parser.validate_semver("1.0.0-alpha+build"))
  should.be_ok(parser.validate_semver("1.0.0-rc.1+build-456"))
}

pub fn invalid_semver_test() {
  let content = read_fixture("bad-version/skill.yaml")
  let result = parser.parse_skill_yaml(content)
  should.be_error(result)
  let assert Error(error.ValidationError(field, _msg)) = result
  should.equal(field, "version")
}

pub fn invalid_semver_format_test() {
  should.be_error(parser.validate_semver("not-a-version"))
  should.be_error(parser.validate_semver("1.0"))
  should.be_error(parser.validate_semver("1"))
  should.be_error(parser.validate_semver(""))
}

pub fn invalid_semver_error_message_test() {
  let assert Error(error.ValidationError(field, msg)) =
    parser.validate_semver("bad")
  should.equal(field, "version")
  should.be_true(string.contains(msg, "Invalid semver"))
  should.be_true(string.contains(msg, "bad"))
}

// ============================================================================
// error.to_string coverage
// ============================================================================

pub fn error_to_string_parse_error_test() {
  let err = error.ParseError("skill.yaml", "unexpected token")
  let s = error.to_string(err)
  should.be_true(string.contains(s, "skill.yaml"))
  should.be_true(string.contains(s, "unexpected token"))
}

pub fn error_to_string_validation_error_test() {
  let err = error.ValidationError("version", "Invalid semver format: bad")
  let s = error.to_string(err)
  should.be_true(string.contains(s, "version"))
  should.be_true(string.contains(s, "Invalid semver"))
}

pub fn error_to_string_template_error_test() {
  let err = error.TemplateError(42, "Unclosed block")
  let s = error.to_string(err)
  should.be_true(string.contains(s, "42"))
  should.be_true(string.contains(s, "Unclosed block"))
}

// ============================================================================
// §1.5 Provider Metadata
// ============================================================================

pub fn parse_openclaw_metadata_test() {
  let content = read_fixture("valid-skill/providers/openclaw/metadata.yaml")
  let result = parser.parse_metadata_yaml(content, "openclaw")
  should.be_ok(result)
}

pub fn parse_claude_code_metadata_test() {
  let content = read_fixture("valid-skill/providers/claude-code/metadata.yaml")
  let result = parser.parse_metadata_yaml(content, "claude-code")
  should.be_ok(result)
}

pub fn parse_codex_metadata_test() {
  let content = read_fixture("valid-skill/providers/codex/metadata.yaml")
  let result = parser.parse_metadata_yaml(content, "codex")
  should.be_ok(result)
}

pub fn parse_invalid_provider_metadata_fails_test() {
  let result = parser.parse_metadata_yaml("{{invalid: yaml: [", "test")
  should.be_error(result)
  let assert Error(error.ParseError(file, _msg)) = result
  should.equal(file, "providers/test/metadata.yaml")
}

// ============================================================================
// §1.6 Dependencies
// ============================================================================

pub fn dependency_with_name_and_version_test() {
  let yaml =
    "name: dep-test
description: Test
version: 1.0.0
dependencies:
  - name: my-dep
    version: ^1.0.0
  - name: optional-dep
    version: ~2.0.0
    optional: true
"
  let assert Ok(skill) = parser.parse_skill_yaml(yaml)
  should.equal(
    skill.dependencies,
    [
      types.Dependency(name: "my-dep", version: "^1.0.0", optional: False),
      types.Dependency(name: "optional-dep", version: "~2.0.0", optional: True),
    ],
  )
}

// ============================================================================
// §1.3 INSTRUCTIONS.md Parsing
// ============================================================================

pub fn has_frontmatter_detects_yaml_frontmatter_test() {
  let content = read_fixture("frontmatter-instructions/INSTRUCTIONS.md")
  should.be_true(parser.has_frontmatter(content))
}

pub fn has_frontmatter_false_for_normal_markdown_test() {
  let content = read_fixture("valid-skill/INSTRUCTIONS.md")
  should.be_false(parser.has_frontmatter(content))
}

pub fn has_frontmatter_false_for_empty_test() {
  should.be_false(parser.has_frontmatter(""))
}

// ============================================================================
// §1.6 Dependencies (additional)
// ============================================================================

pub fn dependency_without_name_skipped_test() {
  let yaml =
    "name: dep-test
description: Test
version: 1.0.0
dependencies:
  - version: ^1.0.0
  - name: valid-dep
    version: ~2.0.0
"
  let assert Ok(skill) = parser.parse_skill_yaml(yaml)
  // The entry without a name should be silently skipped
  should.equal(
    skill.dependencies,
    [types.Dependency(name: "valid-dep", version: "~2.0.0", optional: False)],
  )
}

pub fn dependency_default_version_star_test() {
  let yaml =
    "name: dep-test
description: Test
version: 1.0.0
dependencies:
  - name: no-version-dep
"
  let assert Ok(skill) = parser.parse_skill_yaml(yaml)
  let assert [dep] = skill.dependencies
  should.equal(dep.version, "*")
}

// ============================================================================
// §1.7 Configuration Schema
// ============================================================================

pub fn config_field_without_name_skipped_test() {
  let yaml =
    "name: config-test
description: Test
version: 1.0.0
config:
  - description: missing name field
    required: true
  - name: valid_field
    description: has a name
"
  let assert Ok(skill) = parser.parse_skill_yaml(yaml)
  // Entry without name should be skipped
  should.equal(
    skill.config,
    [
      types.ConfigField(
        name: "valid_field",
        description: "has a name",
        required: False,
        secret: False,
        default: None,
      ),
    ],
  )
}

pub fn config_field_all_properties_test() {
  let yaml =
    "name: config-test
description: Test
version: 1.0.0
config:
  - name: api_key
    description: API key
    required: true
    secret: true
  - name: cache_ttl
    description: Cache TTL
    required: false
    default: \"300\"
"
  let assert Ok(skill) = parser.parse_skill_yaml(yaml)
  let assert [first, second] = skill.config
  should.equal(first.name, "api_key")
  should.equal(first.required, True)
  should.equal(first.secret, True)
  should.equal(first.default, None)
  should.equal(second.name, "cache_ttl")
  should.equal(second.required, False)
  should.equal(second.secret, False)
  should.equal(second.default, Some("300"))
}

// ============================================================================
// Helpers
// ============================================================================

fn read_fixture(path: String) -> String {
  let full_path = "test/fixtures/" <> path
  let assert Ok(content) = simplifile.read(full_path)
  content
}
