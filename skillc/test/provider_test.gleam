import gleeunit/should
import skillc/provider

// ============================================================================
// §1.4 Provider Discovery
// ============================================================================

pub fn discover_valid_providers_test() {
  let result = provider.discover_providers("test/fixtures/valid-skill")
  let assert Ok(discovery) = result
  should.equal(
    discovery.providers,
    ["claude-code", "codex", "openclaw"],
  )
}

pub fn discover_minimal_provider_test() {
  let result = provider.discover_providers("test/fixtures/minimal-skill")
  let assert Ok(discovery) = result
  should.equal(discovery.providers, ["openclaw"])
}

pub fn discover_no_providers_directory_test() {
  let result = provider.discover_providers("test/fixtures/no-providers")
  let assert Ok(discovery) = result
  should.equal(discovery.providers, [])
}

pub fn discover_empty_providers_directory_test() {
  let result = provider.discover_providers("test/fixtures/empty-providers")
  let assert Ok(discovery) = result
  should.equal(discovery.providers, [])
}

pub fn subdirectory_without_metadata_ignored_test() {
  let result =
    provider.discover_providers("test/fixtures/provider-no-metadata")
  let assert Ok(discovery) = result
  should.equal(discovery.providers, [])
}

pub fn is_supported_valid_test() {
  should.be_true(provider.is_supported("test/fixtures/valid-skill", "openclaw"))
  should.be_true(provider.is_supported(
    "test/fixtures/valid-skill",
    "claude-code",
  ))
  should.be_true(provider.is_supported("test/fixtures/valid-skill", "codex"))
}

pub fn is_supported_invalid_test() {
  should.be_false(provider.is_supported(
    "test/fixtures/valid-skill",
    "nonexistent",
  ))
  should.be_false(provider.is_supported("test/fixtures/no-providers", "openclaw"))
}

pub fn validate_provider_supported_test() {
  let result =
    provider.validate_provider("test/fixtures/valid-skill", "openclaw")
  should.be_ok(result)
}

pub fn validate_provider_unsupported_test() {
  let result =
    provider.validate_provider("test/fixtures/valid-skill", "nonexistent")
  should.be_error(result)
}

pub fn unknown_provider_warning_test() {
  // provider-no-metadata has openclaw dir but without metadata.yaml
  // The valid-skill fixture only has known providers, so no warnings
  let assert Ok(discovery) =
    provider.discover_providers("test/fixtures/valid-skill")
  should.equal(discovery.warnings, [])
}
