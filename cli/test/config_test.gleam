import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import skill_universe
import skill_universe/config
import skill_universe/semver
import skill_universe/types.{
  type Skill, ConfigField, Optional, OptionalWithDefault, Required, Skill,
}

// ============================================================================
// Template Generation
// ============================================================================

pub fn generate_template_with_fields_test() {
  let skill = test_skill_with_config()
  let template = config.generate_template(skill)
  should.be_true(string.contains(template, "SKILL_CONFIG_TEST_SKILL_API_KEY="))
  should.be_true(string.contains(template, "Required"))
  should.be_true(string.contains(template, "Secret: yes"))
  should.be_true(string.contains(template, "SKILL_CONFIG_TEST_SKILL_TIMEOUT="))
  should.be_true(string.contains(template, "default: 30"))
  should.be_true(string.contains(template, "30"))
}

pub fn generate_template_no_fields_test() {
  let skill = test_skill_no_config()
  let template = config.generate_template(skill)
  should.be_true(string.contains(template, "No configuration fields"))
}

pub fn generate_template_includes_description_test() {
  let skill = test_skill_with_config()
  let template = config.generate_template(skill)
  should.be_true(string.contains(template, "API key for the service"))
  should.be_true(string.contains(template, "Request timeout"))
}

// ============================================================================
// Config Check with Injectable Lookup
// ============================================================================

pub fn check_all_satisfied_test() {
  let skill = test_skill_with_config()
  let lookup = fn(name) {
    case name {
      "SKILL_CONFIG_TEST_SKILL_API_KEY" -> Ok("my-key")
      "SKILL_CONFIG_TEST_SKILL_TIMEOUT" -> Ok("60")
      "SKILL_CONFIG_TEST_SKILL_DEBUG" -> Ok("")
      _ -> Error(Nil)
    }
  }
  let statuses = config.check_with_lookup(skill, lookup)
  let missing =
    list.filter(statuses, fn(s) {
      case s {
        config.MissingRequired(_) -> True
        _ -> False
      }
    })
  should.equal(missing, [])
}

pub fn check_missing_required_test() {
  let skill = test_skill_with_config()
  let lookup = fn(_name) { Error(Nil) }
  let statuses = config.check_with_lookup(skill, lookup)
  let missing =
    list.filter_map(statuses, fn(s) {
      case s {
        config.MissingRequired(field:) -> Ok(field.name)
        _ -> Error(Nil)
      }
    })
  should.be_true(list.contains(missing, "api_key"))
}

pub fn check_optional_not_missing_test() {
  let skill = test_skill_with_config()
  let lookup = fn(_name) { Error(Nil) }
  let statuses = config.check_with_lookup(skill, lookup)
  let missing =
    list.filter_map(statuses, fn(s) {
      case s {
        config.MissingRequired(field:) -> Ok(field.name)
        _ -> Error(Nil)
      }
    })
  // debug is optional, should not be in missing
  should.be_false(list.contains(missing, "debug"))
}

pub fn check_default_used_when_not_set_test() {
  let skill = test_skill_with_config()
  let lookup = fn(_name) { Error(Nil) }
  let statuses = config.check_with_lookup(skill, lookup)
  let timeout_status =
    list.find(statuses, fn(s) {
      case s {
        config.Provided(field:, ..) -> field.name == "timeout"
        config.DefaultUsed(field:, ..) -> field.name == "timeout"
        config.MissingRequired(field:) -> field.name == "timeout"
        config.Skipped(field:) -> field.name == "timeout"
      }
    })
  let assert Ok(config.DefaultUsed(_, default)) = timeout_status
  should.equal(default, "30")
}

pub fn check_empty_string_counts_as_missing_for_required_test() {
  let skill = test_skill_with_config()
  let lookup = fn(name) {
    case name {
      "SKILL_CONFIG_TEST_SKILL_API_KEY" -> Ok("")
      _ -> Error(Nil)
    }
  }
  let statuses = config.check_with_lookup(skill, lookup)
  let missing =
    list.filter_map(statuses, fn(s) {
      case s {
        config.MissingRequired(field:) -> Ok(field.name)
        _ -> Error(Nil)
      }
    })
  should.be_true(list.contains(missing, "api_key"))
}

// ============================================================================
// CLI Routing
// ============================================================================

pub fn cli_config_init_test() {
  let assert Ok(output) =
    skill_universe.run(["config", "init", "test/fixtures/valid-skill"])
  should.be_true(string.contains(output, "SKILL_CONFIG_"))
}

pub fn cli_config_check_missing_dir_test() {
  let result = skill_universe.run(["config", "check", "/tmp/nonexistent-dir-xyz"])
  should.be_error(result)
}

// ============================================================================
// Test Helpers
// ============================================================================

fn test_skill_with_config() -> Skill {
  let assert Ok(v) = semver.parse("1.0.0")
  Skill(
    name: "test-skill",
    description: "A test skill",
    version: v,
    license: None,
    homepage: None,
    repository: None,
    metadata: None,
    dependencies: [],
    config: [
      ConfigField(
        name: "api_key",
        description: "API key for the service",
        requirement: Required,
        secret: True,
      ),
      ConfigField(
        name: "timeout",
        description: "Request timeout",
        requirement: OptionalWithDefault("30"),
        secret: False,
      ),
      ConfigField(
        name: "debug",
        description: "Enable debug mode",
        requirement: Optional,
        secret: False,
      ),
    ],
  )
}

fn test_skill_no_config() -> Skill {
  let assert Ok(v) = semver.parse("1.0.0")
  Skill(
    name: "simple-skill",
    description: "A simple skill",
    version: v,
    license: None,
    homepage: None,
    repository: None,
    metadata: None,
    dependencies: [],
    config: [],
  )
}
