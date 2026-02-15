import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import skillc/error
import skillc/semver
import skillc/template
import skillc/types.{
  type Skill, ConfigField, Optional, Required, Skill, SkillMetadata,
}
import skillc/version_constraint
import yay

// ============================================================================
// §2.1 Provider Block Helper
// ============================================================================

pub fn provider_block_included_test() {
  let content =
    "before\n{{#provider \"openclaw\"}}openclaw content{{/provider}}\nafter"
  let assert Ok(result) = template.process_provider_blocks(content, "openclaw")
  should.be_true(string.contains(result, "openclaw content"))
  should.be_true(string.contains(result, "before"))
  should.be_true(string.contains(result, "after"))
}

pub fn provider_block_excluded_test() {
  let content =
    "before\n{{#provider \"openclaw\"}}openclaw content{{/provider}}\nafter"
  let assert Ok(result) =
    template.process_provider_blocks(content, "claude-code")
  should.be_false(string.contains(result, "openclaw content"))
  should.be_true(string.contains(result, "before"))
  should.be_true(string.contains(result, "after"))
}

pub fn multi_provider_block_included_test() {
  let content =
    "{{#provider \"openclaw\" \"codex\"}}shared content{{/provider}}"
  let assert Ok(result_openclaw) =
    template.process_provider_blocks(content, "openclaw")
  let assert Ok(result_codex) =
    template.process_provider_blocks(content, "codex")
  should.be_true(string.contains(result_openclaw, "shared content"))
  should.be_true(string.contains(result_codex, "shared content"))
}

pub fn multi_provider_block_excluded_test() {
  let content =
    "{{#provider \"openclaw\" \"codex\"}}shared content{{/provider}}"
  let assert Ok(result) =
    template.process_provider_blocks(content, "claude-code")
  should.be_false(string.contains(result, "shared content"))
}

pub fn empty_provider_block_test() {
  let content = "before{{#provider \"openclaw\"}}{{/provider}}after"
  let assert Ok(result) = template.process_provider_blocks(content, "openclaw")
  should.be_true(string.contains(result, "before"))
  should.be_true(string.contains(result, "after"))
}

pub fn nested_provider_blocks_test() {
  let content =
    "{{#provider \"openclaw\"}}outer{{#provider \"openclaw\"}}inner{{/provider}}end{{/provider}}"
  let assert Ok(result) = template.process_provider_blocks(content, "openclaw")
  should.be_true(string.contains(result, "outer"))
  should.be_true(string.contains(result, "inner"))
}

pub fn unclosed_provider_block_returns_error_test() {
  let content = "before\n{{#provider \"openclaw\"}}no closing tag"
  let result = template.process_provider_blocks(content, "openclaw")
  should.be_error(result)
}

pub fn malformed_provider_tag_returns_error_test() {
  // Missing closing }} on the tag
  let content = "{{#provider \"openclaw\" some content"
  let result = template.process_provider_blocks(content, "openclaw")
  should.be_error(result)
}

// ============================================================================
// §2.2 Variable Interpolation
// ============================================================================

pub fn variable_name_test() {
  let result =
    template.render_template(
      "Hello {{name}}",
      types.OpenClaw,
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
      types.OpenClaw,
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
      types.OpenClaw,
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
      types.OpenClaw,
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
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

pub fn nested_metadata_access_test() {
  // Access meta.requires.bins (nested path)
  let result =
    template.render_template(
      "{{#each meta.requires.bins}}{{this}} {{/each}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "python3"))
  should.be_true(string.contains(output, "curl"))
}

// ============================================================================
// §2.3 Standard Conditionals
// ============================================================================

pub fn if_block_truthy_test() {
  let result =
    template.render_template(
      "{{#if meta.emoji}}has emoji{{/if}}",
      types.OpenClaw,
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
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "no field"))
}

pub fn if_block_falsy_path_test() {
  // #if on a non-existent variable should exclude the block
  let result =
    template.render_template(
      "before{{#if meta.nonexistent}}hidden{{/if}}after",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

pub fn if_block_false_bool_test() {
  // #if on a false boolean should exclude the block
  let skill =
    Skill(..test_skill(), config: [
      ConfigField(
        name: "test",
        description: "test",
        requirement: Optional,
        secret: False,
      ),
    ])
  let result =
    template.render_template(
      "{{#each config}}{{#if this.required}}req{{/if}}{{#unless this.required}}opt{{/unless}}{{/each}}",
      types.OpenClaw,
      skill,
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "opt"))
  should.be_false(string.contains(output, "req"))
}

pub fn each_block_test() {
  let result =
    template.render_template(
      "{{#each config}}{{this.name}} {{/each}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "api_key"))
}

pub fn each_block_at_index_test() {
  let skill =
    Skill(..test_skill(), config: [
      ConfigField(
        name: "a",
        description: "",
        requirement: Optional,
        secret: False,
      ),
      ConfigField(
        name: "b",
        description: "",
        requirement: Optional,
        secret: False,
      ),
    ])
  let result =
    template.render_template(
      "{{#each config}}{{@index}}:{{this.name}} {{/each}}",
      types.OpenClaw,
      skill,
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "0:a"))
  should.be_true(string.contains(output, "1:b"))
}

pub fn each_block_at_first_last_test() {
  let skill =
    Skill(..test_skill(), config: [
      ConfigField(
        name: "first",
        description: "",
        requirement: Optional,
        secret: False,
      ),
      ConfigField(
        name: "middle",
        description: "",
        requirement: Optional,
        secret: False,
      ),
      ConfigField(
        name: "last",
        description: "",
        requirement: Optional,
        secret: False,
      ),
    ])
  let result =
    template.render_template(
      "{{#each config}}{{#if @first}}[FIRST]{{/if}}{{#if @last}}[LAST]{{/if}}{{this.name}} {{/each}}",
      types.OpenClaw,
      skill,
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "[FIRST]first"))
  should.be_true(string.contains(output, "[LAST]last"))
  should.be_false(string.contains(output, "[FIRST]middle"))
  should.be_false(string.contains(output, "[LAST]middle"))
}

pub fn each_empty_list_test() {
  let skill = Skill(..test_skill(), config: [])
  let result =
    template.render_template(
      "before{{#each config}}item{{/each}}after",
      types.OpenClaw,
      skill,
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

// ============================================================================
// §2.3b Conditional Else Blocks
// ============================================================================

pub fn if_else_truthy_renders_if_branch_test() {
  let result =
    template.render_template(
      "{{#if meta.emoji}}has emoji{{else}}no emoji{{/if}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "has emoji"))
  should.be_false(string.contains(output, "no emoji"))
}

pub fn if_else_falsy_renders_else_branch_test() {
  let result =
    template.render_template(
      "{{#if meta.nonexistent}}yes{{else}}no{{/if}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "no"))
  should.be_false(string.contains(output, "yes"))
}

pub fn unless_else_truthy_renders_else_branch_test() {
  let result =
    template.render_template(
      "{{#unless meta.emoji}}hidden{{else}}shown{{/unless}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "shown"))
  should.be_false(string.contains(output, "hidden"))
}

pub fn unless_else_falsy_renders_unless_branch_test() {
  let result =
    template.render_template(
      "{{#unless meta.nonexistent}}shown{{else}}hidden{{/unless}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "shown"))
  should.be_false(string.contains(output, "hidden"))
}

pub fn if_else_with_variables_test() {
  let result =
    template.render_template(
      "{{#if meta.emoji}}Icon: {{meta.emoji}}{{else}}Name: {{name}}{{/if}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "Icon:"))
}

pub fn if_else_falsy_with_variables_test() {
  let result =
    template.render_template(
      "{{#if meta.nonexistent}}hidden{{else}}fallback: {{name}}{{/if}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "fallback: test-skill"))
}

pub fn nested_if_else_test() {
  let result =
    template.render_template(
      "{{#if meta.emoji}}{{#if meta.nonexistent}}inner{{else}}outer else{{/if}}{{else}}top else{{/if}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "outer else"))
  should.be_false(string.contains(output, "inner"))
  should.be_false(string.contains(output, "top else"))
}

pub fn if_else_empty_else_block_test() {
  let result =
    template.render_template(
      "before{{#if meta.nonexistent}}content{{else}}{{/if}}after",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

// ============================================================================
// §2.4 Escaping
// ============================================================================

pub fn backslash_escape_test() {
  let result =
    template.render_template(
      "\\{{not processed}}",
      types.OpenClaw,
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
      types.OpenClaw,
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
      types.OpenClaw,
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
      types.OpenClaw,
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
      types.OpenClaw,
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
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  should.be_error(result)
}

pub fn unclosed_each_block_fails_test() {
  let result =
    template.render_template(
      "{{#each config}}no closing tag",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  should.be_error(result)
}

pub fn unclosed_unless_block_fails_test() {
  let result =
    template.render_template(
      "{{#unless meta.emoji}}no closing tag",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  should.be_error(result)
}

// ============================================================================
// §2.2 Template Context: dependencies and metadata
// ============================================================================

pub fn each_dependencies_test() {
  let skill =
    Skill(..test_skill(), dependencies: [
      types.Dependency(
        name: "helper-skill",
        version: assert_parse_vc("^1.0.0"),
        optional: False,
      ),
      types.Dependency(
        name: "extra-skill",
        version: assert_parse_vc("~2.0.0"),
        optional: True,
      ),
    ])
  let result =
    template.render_template(
      "{{#each dependencies}}{{this.name}}({{this.version}}) {{/each}}",
      types.OpenClaw,
      skill,
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "helper-skill(^1.0.0)"))
  should.be_true(string.contains(output, "extra-skill(~2.0.0)"))
}

pub fn metadata_author_in_context_test() {
  let result =
    template.render_template(
      "Author: {{metadata.author}}",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "Author: Test"))
}

pub fn metadata_tags_in_context_test() {
  let skill =
    Skill(
      ..test_skill(),
      metadata: Some(
        SkillMetadata(author: None, author_email: None, tags: ["web", "api"]),
      ),
    )
  let result =
    template.render_template(
      "{{#each metadata.tags}}{{this}} {{/each}}",
      types.OpenClaw,
      skill,
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.be_true(string.contains(output, "web"))
  should.be_true(string.contains(output, "api"))
}

// ============================================================================
// §2.6 Error messages include line numbers
// ============================================================================

pub fn template_error_has_line_number_test() {
  // The unclosed #if is on line 3
  let result =
    template.render_template(
      "line 1\nline 2\n{{#if meta.emoji}}unclosed",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  should.be_error(result)
  let assert Error(error.TemplateError(line, msg)) = result
  should.equal(line, 3)
  should.be_true(string.contains(msg, "Unclosed"))
}

pub fn unbalanced_tag_error_has_line_number_test() {
  let result =
    template.render_template(
      "line 1\nline 2\nline 3\n{{unbalanced",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  should.be_error(result)
  let assert Error(error.TemplateError(line, _msg)) = result
  should.equal(line, 4)
}

pub fn unclosed_provider_error_has_line_number_test() {
  let content = "line 1\nline 2\n{{#provider \"openclaw\"}}no close"
  let result = template.process_provider_blocks(content, "openclaw")
  should.be_error(result)
  let assert Error(error.TemplateError(line, msg)) = result
  should.equal(line, 3)
  should.be_true(string.contains(msg, "Unclosed"))
}

// ============================================================================
// Group D: Additional template rendering tests
// ============================================================================

pub fn unless_with_truthy_value_excludes_content_test() {
  let result =
    template.render_template(
      "before{{#unless meta.emoji}}hidden{{/unless}}after",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

pub fn if_with_empty_string_is_falsy_test() {
  // Create provider meta with an empty string field
  let meta = yay.NodeMap([#(yay.NodeStr("empty_field"), yay.NodeStr(""))])
  let result =
    template.render_template(
      "before{{#if meta.empty_field}}hidden{{/if}}after",
      types.OpenClaw,
      test_skill(),
      meta,
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

pub fn if_with_empty_list_is_falsy_test() {
  let skill = Skill(..test_skill(), dependencies: [], config: [])
  let result =
    template.render_template(
      "before{{#if config}}shown{{/if}}after",
      types.OpenClaw,
      skill,
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

pub fn each_with_simple_string_items_test() {
  // {{#each}} over a list of strings, using {{this}}
  let result =
    template.render_template(
      "{{#each metadata.tags}}[{{this}}]{{/each}}",
      types.OpenClaw,
      Skill(
        ..test_skill(),
        metadata: Some(
          SkillMetadata(author: None, author_email: None, tags: [
            "web",
            "api",
            "test",
          ]),
        ),
      ),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "[web][api][test]")
}

pub fn undefined_deep_nested_path_resolves_empty_test() {
  let result =
    template.render_template(
      "before{{a.b.c.d}}after",
      types.OpenClaw,
      test_skill(),
      test_provider_meta(),
    )
  let assert Ok(output) = result
  should.equal(output, "beforeafter")
}

// ============================================================================
// Test Helpers
// ============================================================================

fn test_skill() -> Skill {
  let assert Ok(v) = semver.parse("1.0.0")
  Skill(
    name: "test-skill",
    description: "A test skill",
    version: v,
    license: Some("MIT"),
    homepage: None,
    repository: None,
    metadata: Some(
      SkillMetadata(author: Some("Test"), author_email: None, tags: []),
    ),
    dependencies: [],
    config: [
      ConfigField(
        name: "api_key",
        description: "API key",
        requirement: Required,
        secret: True,
      ),
    ],
  )
}

fn assert_parse_vc(input: String) -> version_constraint.VersionConstraint {
  let assert Ok(vc) = version_constraint.parse(input)
  vc
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
