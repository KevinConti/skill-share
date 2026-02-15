import gleam/list
import gleeunit/should
import skillc/provider
import skillc/types

// ============================================================================
// §1.4 Provider Discovery
// ============================================================================

pub fn discover_valid_providers_test() {
  let result = provider.discover_providers("test/fixtures/valid-skill")
  let assert Ok(providers) = result
  should.equal(providers, [types.ClaudeCode, types.Codex, types.OpenClaw])
}

pub fn discover_minimal_provider_test() {
  let result = provider.discover_providers("test/fixtures/minimal-skill")
  let assert Ok(providers) = result
  should.equal(providers, [types.OpenClaw])
}

pub fn discover_no_providers_directory_test() {
  let result = provider.discover_providers("test/fixtures/no-providers")
  let assert Ok(providers) = result
  should.equal(providers, [])
}

pub fn discover_empty_providers_directory_test() {
  let result = provider.discover_providers("test/fixtures/empty-providers")
  let assert Ok(providers) = result
  should.equal(providers, [])
}

pub fn subdirectory_without_metadata_ignored_test() {
  let result = provider.discover_providers("test/fixtures/provider-no-metadata")
  let assert Ok(providers) = result
  should.equal(providers, [])
}

pub fn is_supported_valid_test() {
  should.be_true(provider.is_supported(
    "test/fixtures/valid-skill",
    types.OpenClaw,
  ))
  should.be_true(provider.is_supported(
    "test/fixtures/valid-skill",
    types.ClaudeCode,
  ))
  should.be_true(provider.is_supported("test/fixtures/valid-skill", types.Codex))
}

pub fn is_supported_invalid_test() {
  should.be_false(provider.is_supported(
    "test/fixtures/no-providers",
    types.OpenClaw,
  ))
}

pub fn validate_provider_supported_test() {
  let result =
    provider.validate_provider("test/fixtures/valid-skill", types.OpenClaw)
  should.be_ok(result)
}

pub fn validate_provider_unsupported_test() {
  let result =
    provider.validate_provider("test/fixtures/no-providers", types.OpenClaw)
  should.be_error(result)
}

pub fn known_providers_no_warnings_test() {
  // valid-skill fixture only has known providers, all should be discovered
  let assert Ok(providers) =
    provider.discover_providers("test/fixtures/valid-skill")
  should.equal(list.length(providers), 3)
}

pub fn unknown_provider_silently_skipped_test() {
  // unknown-provider fixture has "my-custom-provider" which is not in known list
  let assert Ok(providers) =
    provider.discover_providers("test/fixtures/unknown-provider")
  // Should only discover openclaw (my-custom-provider silently skipped)
  should.equal(providers, [types.OpenClaw])
}
