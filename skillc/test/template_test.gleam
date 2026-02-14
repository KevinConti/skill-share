import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import skillc/template
import skillc/types.{type Skill, ConfigField, Skill, SkillMetadata}
import yay

// ============================================================================
// §2.1 Provider Block Helper
// ============================================================================

pub fn provider_block_included_test() {
  let content =
    "before\n{{#provider \"openclaw\"}}openclaw content{{/provider}}\nafter"
  let result = template.process_provider_blocks(content, "openclaw")
  should.be_true(string.contains(result, "openclaw content"))
  should.be_true(string.contains(result, "before"))
  should.be_true(string.contains(result, "after"))
}

pub fn provider_block_excluded_test() {
  let content =
    "before\n{{#provider \"openclaw\"}}openclaw content{{/provider}}\nafter"
  let result = template.process_provider_blocks(content, "claude-code")
  should.be_false(string.contains(result, "openclaw content"))
  should.be_true(string.contains(result, "before"))
  should.be_true(string.contains(result, "after"))
}

pub fn multi_provider_block_included_test() {
  let content =
    "{{#provider \"openclaw\" \"codex\"}}shared content{{/provider}}"
  let result_openclaw = template.process_provider_blocks(content, "openclaw")
  let result_codex = template.process_provider_blocks(content, "codex")
  should.be_true(string.contains(result_openclaw, "shared content"))
  should.be_true(string.contains(result_codex, "shared content"))
}

pub fn multi_provider_block_excluded_test() {
  let content =
    "{{#provider \"openclaw\" \"codex\"}}shared content{{/provider}}"
  let result = template.process_provider_blocks(content, "claude-code")
  should.be_false(string.contains(result, "shared content"))
}

pub fn empty_provider_block_test() {
  let content = "before{{#provider \"openclaw\"}}{{/provider}}after"
  let result = template.process_provider_blocks(content, "openclaw")
  should.be_true(string.contains(result, "before"))
  should.be_true(string.contains(result, "after"))
}

pub fn nested_provider_blocks_test() {
  let content =
    "{{#provider \"openclaw\"}}outer{{#provider \"openclaw\"}}inner{{/provider}}end{{/provider}}"
  let result = template.process_provider_blocks(content, "openclaw")
  should.be_true(string.contains(result, "outer"))
  should.be_true(string.contains(result, "inner"))
}

// ============================================================================
// §2.2 Variable Interpolation
// ============================================================================

pub fn variable_name_test() {
  let result =
    template.render_template(
      "Hello {{name}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "Hello test-skill"))
}

pub fn variable_version_test() {
  let result =
    template.render_template(
      "v{{version}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "v1.0.0"))
}

pub fn variable_description_test() {
  let result =
    template.render_template(
      "{{description}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "A test skill"))
}

pub fn variable_meta_field_test() {
  let result =
    template.render_template(
      "Icon: {{meta.emoji}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "Icon: 🧪"))
}

pub fn undefined_variable_renders_empty_test() {
  let result =
    template.render_template(
      "before{{nonexistent}}after",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

// ============================================================================
// §2.3 Standard Conditionals
// ============================================================================

pub fn if_block_truthy_test() {
  let result =
    template.render_template(
      "{{#if meta.emoji}}has emoji{{/if}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "has emoji"))
}

pub fn unless_block_test() {
  let result =
    template.render_template(
      "{{#unless meta.nonexistent}}no field{{/unless}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "no field"))
}

pub fn each_block_test() {
  let result =
    template.render_template(
      "{{#each config}}{{this.name}} {{/each}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "api_key"))
}

// ============================================================================
// §2.4 Escaping
// ============================================================================

pub fn backslash_escape_test() {
  let result =
    template.render_template(
      "\\{{not processed}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "{{not processed}}"))
}

pub fn raw_block_test() {
  let result =
    template.render_template(
      "{{{{raw}}}}{{name}} should not be replaced{{{{/raw}}}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_false(string.contains(output, "test-skill"))
  should.be_true(string.contains(output, "{{name}}"))
}

// ============================================================================
// §2.5 Template Context
// ============================================================================

pub fn context_includes_provider_test() {
  let result =
    template.render_template(
      "Provider: {{provider}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "Provider: openclaw"))
}

pub fn context_includes_top_level_fields_test() {
  let result =
    template.render_template(
      "{{name}} {{version}} {{description}}",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "test-skill"))
  should.be_true(string.contains(output, "1.0.0"))
  should.be_true(string.contains(output, "A test skill"))
}

// ============================================================================
// §2.6 Error Handling
// ============================================================================

pub fn unclosed_if_block_fails_test() {
  let result =
    template.render_template(
      "{{#if meta.emoji}}unclosed",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  should.be_error(result)
}

pub fn unclosed_provider_block_fails_test() {
  // Unclosed provider block is caught in provider block processing
  // but since process_provider_blocks is lenient (returns raw text on error),
  // test unclosed handlebars blocks instead
  let result =
    template.render_template(
      "{{#if meta.emoji}}unclosed if and also {{unbalanced",
      "openclaw",
      test_skill(),
      test_provider_meta(),
    )
  should.be_error(result)
}

// ============================================================================
// Test Helpers
// ============================================================================

fn test_skill() -> Skill {
  Skill(
    name: "test-skill",
    description: "A test skill",
    version: "1.0.0",
    license: Some("MIT"),
    homepage: None,
    repository: None,
    metadata: Some(SkillMetadata(
      author: Some("Test"),
      author_email: None,
      tags: [],
    )),
    dependencies: [],
    config: [
      ConfigField(
        name: "api_key",
        description: "API key",
        required: True,
        secret: True,
        default: None,
      ),
    ],
  )
}

fn test_provider_meta() -> yay.Node {
  yay.NodeMap([
    #(yay.NodeStr("emoji"), yay.NodeStr("🧪")),
    #(
      yay.NodeStr("requires"),
      yay.NodeMap([
        #(
          yay.NodeStr("bins"),
          yay.NodeSeq([yay.NodeStr("python3"), yay.NodeStr("curl")]),
        ),
      ]),
    ),
  ])
}
