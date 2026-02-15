import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import skillc/error.{type SkillError, TemplateError}
import skillc/semver
import skillc/types.{
  type Provider, type Skill, Optional, OptionalWithDefault, Required,
}
import skillc/version_constraint
import yay

const escaped_brace_placeholder = "___ESCAPED_OPEN_BRACE___"

const key_index = "@index"

const key_first = "@first"

const key_last = "@last"

const key_this = "this"

type ConditionalBlock {
  ConditionalBlock(
    if_content: String,
    else_content: Option(String),
    remaining: String,
  )
}

// ============================================================================
// Public API
// ============================================================================

pub fn render_template(
  content: String,
  target: Provider,
  skill: Skill,
  provider_meta: yay.Node,
) -> Result(String, SkillError) {
  use processed <- result.try(process_provider_blocks(content, target))
  let context = build_context(skill, target, provider_meta)
  render(processed, context)
}

// ============================================================================
// Context type (simple tree of values)
// ============================================================================

pub type Value {
  VStr(String)
  VBool(Bool)
  VInt(Int)
  VFloat(Float)
  VList(List(Value))
  VDict(List(#(String, Value)))
  VNil
}

// ============================================================================
// Phase 1: Provider block processing
// ============================================================================

pub fn process_provider_blocks(
  content: String,
  target: Provider,
) -> Result(String, SkillError) {
  let target_str = types.provider_to_string(target)
  do_process_provider_blocks(content, target_str, "", 1)
}

fn do_process_provider_blocks(
  remaining: String,
  target: String,
  acc: String,
  line: Int,
) -> Result(String, SkillError) {
  case string.split_once(remaining, "{{#provider ") {
    Error(_) -> Ok(acc <> remaining)
    Ok(#(before, after_open)) -> {
      let error_line = line + count_newlines(before)
      use #(providers, after_tag) <- result.try(
        parse_provider_tag(after_open)
        |> result.replace_error(TemplateError(
          error_line,
          "Malformed {{#provider}} tag: missing provider names or closing }}",
        )),
      )
      use #(block_content, after_close) <- result.try(
        find_closing_provider(after_tag, 1)
        |> result.replace_error(TemplateError(
          error_line,
          "Unclosed {{#provider}} block",
        )),
      )
      let should_include = list.contains(providers, target)
      let new_acc = case should_include {
        True ->
          acc <> before <> strip_surrounding_newlines(block_content) <> "\n"
        False -> acc <> strip_trailing_newlines(before)
      }
      let new_line = error_line + count_newlines(block_content)
      do_process_provider_blocks(after_close, target, new_acc, new_line)
    }
  }
}

fn strip_surrounding_newlines(s: String) -> String {
  let s = case string.starts_with(s, "\n") {
    True -> string.drop_start(s, 1)
    False -> s
  }
  case string.ends_with(s, "\n") {
    True -> string.drop_end(s, 1)
    False -> s
  }
}

fn strip_trailing_newlines(s: String) -> String {
  case string.ends_with(s, "\n") {
    True -> strip_trailing_newlines(string.drop_end(s, 1))
    False -> s
  }
}

fn parse_provider_tag(content: String) -> Result(#(List(String), String), Nil) {
  case string.split_once(content, "}}") {
    Ok(#(tag_content, rest)) -> {
      let providers = parse_provider_names(string.trim(tag_content))
      case providers {
        [] -> Error(Nil)
        _ -> Ok(#(providers, rest))
      }
    }
    Error(_) -> Error(Nil)
  }
}

fn parse_provider_names(content: String) -> List(String) {
  string.split(content, " ")
  |> list.filter_map(fn(part) {
    let trimmed = string.trim(part)
    case string.starts_with(trimmed, "\""), string.ends_with(trimmed, "\"") {
      True, True -> {
        let name =
          trimmed
          |> string.drop_start(1)
          |> string.drop_end(1)
        case name {
          "" -> Error(Nil)
          _ -> Ok(name)
        }
      }
      _, _ -> Error(Nil)
    }
  })
}

fn find_closing_provider(
  content: String,
  depth: Int,
) -> Result(#(String, String), Nil) {
  case depth {
    0 -> Ok(#("", content))
    _ -> {
      case string.split_once(content, "{{/provider}}") {
        Ok(#(before, after)) -> {
          let nested_opens = count_opens(before, 0)
          let new_depth = depth + nested_opens - 1
          case new_depth {
            0 -> Ok(#(before, after))
            _ -> {
              use #(rest_content, rest_after) <- result.try(
                find_closing_provider(after, new_depth),
              )
              Ok(#(before <> "{{/provider}}" <> rest_content, rest_after))
            }
          }
        }
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn count_opens(content: String, acc: Int) -> Int {
  case string.split_once(content, "{{#provider ") {
    Ok(#(_, rest)) -> count_opens(rest, acc + 1)
    Error(_) -> acc
  }
}

// ============================================================================
// Phase 2: Template rendering (custom Handlebars-like engine)
// ============================================================================

fn render(content: String, context: Value) -> Result(String, SkillError) {
  // Pre-process raw blocks
  let content = process_raw_blocks(content, "")
  // Pre-process backslash escapes
  let content = string.replace(content, "\\{{", escaped_brace_placeholder)
  // Render template with line counter starting at 1
  use #(output, _) <- result.try(render_tokens(content, context, 1))
  // Post-process: restore escaped braces
  let output = string.replace(output, escaped_brace_placeholder, "{{")
  Ok(output)
}

fn process_raw_blocks(content: String, acc: String) -> String {
  case string.split_once(content, "{{{{raw}}}}") {
    Ok(#(before, after_open)) -> {
      case string.split_once(after_open, "{{{{/raw}}}}") {
        Ok(#(raw_content, after_close)) -> {
          let escaped =
            string.replace(raw_content, "{{", escaped_brace_placeholder)
          process_raw_blocks(after_close, acc <> before <> escaped)
        }
        Error(_) -> acc <> content
      }
    }
    Error(_) -> acc <> content
  }
}

fn render_tokens(
  content: String,
  ctx: Value,
  line: Int,
) -> Result(#(String, Int), SkillError) {
  do_render(content, ctx, "", line)
}

fn do_render(
  remaining: String,
  ctx: Value,
  acc: String,
  line: Int,
) -> Result(#(String, Int), SkillError) {
  case string.split_once(remaining, "{{") {
    Error(_) -> Ok(#(acc <> remaining, line + count_newlines(remaining)))
    Ok(#(before, after_open)) -> {
      let source_line = line + count_newlines(before)
      case string.split_once(after_open, "}}") {
        Error(_) ->
          Error(TemplateError(source_line, "Unbalanced tag: missing closing }}"))
        Ok(#(tag_body, after_close)) -> {
          let tag = string.trim(tag_body)
          let after_tag_line = source_line + count_newlines(tag_body)
          case tag {
            // Block helpers
            "#if " <> path -> {
              let path = string.trim(path)
              use block <- result.try(find_block_end_with_else(
                after_close,
                "if",
                source_line,
              ))
              let value = resolve_path(path, ctx)
              let should_render = is_truthy(value)
              render_conditional_block(
                should_render,
                block,
                before,
                ctx,
                acc,
                after_tag_line,
              )
            }
            "#unless " <> path -> {
              let path = string.trim(path)
              use block <- result.try(find_block_end_with_else(
                after_close,
                "unless",
                source_line,
              ))
              let value = resolve_path(path, ctx)
              let should_render = !is_truthy(value)
              render_conditional_block(
                should_render,
                block,
                before,
                ctx,
                acc,
                after_tag_line,
              )
            }
            "#each " <> path -> {
              let path = string.trim(path)
              use #(block_content, rest) <- result.try(find_block_end(
                after_close,
                "each",
                source_line,
              ))
              let value = resolve_path(path, ctx)
              case value {
                VList(items) -> {
                  let len = list.length(items)
                  use #(rendered_items, _) <- result.try(render_each_items(
                    block_content,
                    items,
                    ctx,
                    0,
                    len,
                    "",
                    after_tag_line,
                  ))
                  do_render(
                    rest,
                    ctx,
                    acc <> before <> rendered_items,
                    after_tag_line + count_newlines(block_content),
                  )
                }
                _ ->
                  do_render(
                    rest,
                    ctx,
                    acc <> before,
                    after_tag_line + count_newlines(block_content),
                  )
              }
            }
            // Variable interpolation
            _ -> {
              let value = resolve_path(tag, ctx)
              let str_value = value_to_string(value)
              do_render(
                after_close,
                ctx,
                acc <> before <> str_value,
                after_tag_line,
              )
            }
          }
        }
      }
    }
  }
}

fn render_conditional_block(
  should_render: Bool,
  block: ConditionalBlock,
  before: String,
  ctx: Value,
  acc: String,
  line: Int,
) -> Result(#(String, Int), SkillError) {
  let total_content = case block.else_content {
    Some(else_content) -> block.if_content <> "{{else}}" <> else_content
    None -> block.if_content
  }
  let after_block_line = line + count_newlines(total_content)
  case should_render {
    True -> {
      use #(rendered_block, _) <- result.try(render_tokens(
        block.if_content,
        ctx,
        line,
      ))
      do_render(
        block.remaining,
        ctx,
        acc <> before <> rendered_block,
        after_block_line,
      )
    }
    False -> {
      case block.else_content {
        Some(else_content) -> {
          use #(rendered_else, _) <- result.try(render_tokens(
            else_content,
            ctx,
            line + count_newlines(block.if_content),
          ))
          do_render(
            block.remaining,
            ctx,
            acc <> before <> rendered_else,
            after_block_line,
          )
        }
        None ->
          do_render(block.remaining, ctx, acc <> before, after_block_line)
      }
    }
  }
}

fn render_each_items(
  template: String,
  items: List(Value),
  parent_ctx: Value,
  index: Int,
  total: Int,
  acc: String,
  line: Int,
) -> Result(#(String, Int), SkillError) {
  case items {
    [] -> Ok(#(acc, line))
    [item, ..rest] -> {
      // Build context: parent props (fallback), then item props + specials (priority)
      let is_last = index == total - 1
      let is_first = index == 0
      let special_keys = [
        #(key_index, VInt(index)),
        #(key_first, VBool(is_first)),
        #(key_last, VBool(is_last)),
      ]
      let parent_props = case parent_ctx {
        VDict(props) -> props
        _ -> []
      }
      // Item-specific keys come first (higher priority in list.find lookup)
      let item_keys = case item {
        VDict(props) -> [#(key_this, item), ..list.append(props, special_keys)]
        _ -> [#(key_this, item), ..special_keys]
      }
      let item_ctx = VDict(list.append(item_keys, parent_props))
      use #(rendered, new_line) <- result.try(render_tokens(
        template,
        item_ctx,
        line,
      ))
      render_each_items(
        template,
        rest,
        parent_ctx,
        index + 1,
        total,
        acc <> rendered,
        new_line,
      )
    }
  }
}

fn find_block_end(
  content: String,
  block_type: String,
  open_line: Int,
) -> Result(#(String, String), SkillError) {
  let open_tag = "{{#" <> block_type <> " "
  let close_tag = "{{/" <> block_type <> "}}"
  do_find_block_end(content, open_tag, close_tag, 1, "", open_line)
}

fn do_find_block_end(
  remaining: String,
  open_tag: String,
  close_tag: String,
  depth: Int,
  acc: String,
  open_line: Int,
) -> Result(#(String, String), SkillError) {
  case depth {
    0 -> Ok(#(acc, remaining))
    _ -> {
      // Find the next occurrence of either open or close tag
      let open_pos = find_position(remaining, open_tag)
      let close_pos = find_position(remaining, close_tag)
      case close_pos {
        None -> {
          let block_name =
            open_tag
            |> string.replace("{{#", "")
            |> string.trim()
          Error(TemplateError(
            open_line,
            "Unclosed {{#" <> block_name <> "}} block",
          ))
        }
        Some(close_pos) -> {
          case open_pos {
            Some(open_pos) if open_pos < close_pos -> {
              // Found nested open before close
              let before_len = open_pos + string.length(open_tag)
              let before = string.slice(remaining, 0, before_len)
              let rest = string.drop_start(remaining, before_len)
              do_find_block_end(
                rest,
                open_tag,
                close_tag,
                depth + 1,
                acc <> before,
                open_line,
              )
            }
            _ -> {
              case depth {
                1 -> {
                  // This close tag matches our block
                  let block_content = string.slice(remaining, 0, close_pos)
                  let rest =
                    string.drop_start(
                      remaining,
                      close_pos + string.length(close_tag),
                    )
                  Ok(#(acc <> block_content, rest))
                }
                _ -> {
                  // Nested close
                  let before_len = close_pos + string.length(close_tag)
                  let before = string.slice(remaining, 0, before_len)
                  let rest = string.drop_start(remaining, before_len)
                  do_find_block_end(
                    rest,
                    open_tag,
                    close_tag,
                    depth - 1,
                    acc <> before,
                    open_line,
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

fn find_block_end_with_else(
  content: String,
  block_type: String,
  open_line: Int,
) -> Result(ConditionalBlock, SkillError) {
  let open_tag = "{{#" <> block_type <> " "
  let close_tag = "{{/" <> block_type <> "}}"
  let else_tag = "{{else}}"
  do_find_block_end_with_else(
    content,
    open_tag,
    close_tag,
    else_tag,
    1,
    "",
    None,
    open_line,
  )
}

fn do_find_block_end_with_else(
  remaining: String,
  open_tag: String,
  close_tag: String,
  else_tag: String,
  depth: Int,
  acc: String,
  else_split: Option(String),
  open_line: Int,
) -> Result(ConditionalBlock, SkillError) {
  case depth {
    0 ->
      case else_split {
        Some(if_content) ->
          Ok(ConditionalBlock(
            if_content: if_content,
            else_content: Some(acc),
            remaining: remaining,
          ))
        None ->
          Ok(ConditionalBlock(
            if_content: acc,
            else_content: None,
            remaining: remaining,
          ))
      }
    _ -> {
      let open_pos = find_position(remaining, open_tag)
      let close_pos = find_position(remaining, close_tag)
      let else_pos = case depth {
        1 -> find_position(remaining, else_tag)
        _ -> None
      }
      case close_pos {
        None -> {
          let block_name =
            open_tag
            |> string.replace("{{#", "")
            |> string.trim()
          Error(TemplateError(
            open_line,
            "Unclosed {{#" <> block_name <> "}} block",
          ))
        }
        Some(cp) -> {
          // Check if else comes before both open and close at depth 1
          let use_else = case else_pos, else_split {
            Some(ep), None if ep < cp -> is_before_open(ep, open_pos)
            _, _ -> False
          }
          case use_else, else_pos {
            True, Some(ep) -> {
              let before_else = string.slice(remaining, 0, ep)
              let after_else =
                string.drop_start(remaining, ep + string.length(else_tag))
              do_find_block_end_with_else(
                after_else,
                open_tag,
                close_tag,
                else_tag,
                depth,
                "",
                Some(acc <> before_else),
                open_line,
              )
            }
            _, _ -> {
              case open_pos {
                Some(op) if op < cp -> {
                  let before_len = op + string.length(open_tag)
                  let before = string.slice(remaining, 0, before_len)
                  let rest = string.drop_start(remaining, before_len)
                  do_find_block_end_with_else(
                    rest,
                    open_tag,
                    close_tag,
                    else_tag,
                    depth + 1,
                    acc <> before,
                    else_split,
                    open_line,
                  )
                }
                _ -> {
                  case depth {
                    1 -> {
                      let block_content = string.slice(remaining, 0, cp)
                      let rest =
                        string.drop_start(remaining, cp + string.length(close_tag))
                      case else_split {
                        Some(if_content) ->
                          Ok(ConditionalBlock(
                            if_content: if_content,
                            else_content: Some(acc <> block_content),
                            remaining: rest,
                          ))
                        None ->
                          Ok(ConditionalBlock(
                            if_content: acc <> block_content,
                            else_content: None,
                            remaining: rest,
                          ))
                      }
                    }
                    _ -> {
                      let before_len = cp + string.length(close_tag)
                      let before = string.slice(remaining, 0, before_len)
                      let rest = string.drop_start(remaining, before_len)
                      do_find_block_end_with_else(
                        rest,
                        open_tag,
                        close_tag,
                        else_tag,
                        depth - 1,
                        acc <> before,
                        else_split,
                        open_line,
                      )
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn is_before_open(else_pos: Int, open_pos: Option(Int)) -> Bool {
  case open_pos {
    None -> True
    Some(op) -> else_pos < op
  }
}

fn find_position(haystack: String, needle: String) -> Option(Int) {
  case string.split_once(haystack, needle) {
    Ok(#(before, _)) -> Some(string.length(before))
    Error(_) -> None
  }
}

// ============================================================================
// Path resolution
// ============================================================================

fn resolve_path(path: String, ctx: Value) -> Value {
  let parts = string.split(path, ".")
  resolve_parts(parts, ctx)
}

fn resolve_parts(parts: List(String), ctx: Value) -> Value {
  case parts {
    [] -> ctx
    [part, ..rest] if part == key_this -> {
      let this_val = resolve_this(ctx)
      resolve_parts(rest, this_val)
    }
    [part] if part == key_index -> lookup_key(key_index, ctx)
    [part] if part == key_first -> lookup_key(key_first, ctx)
    [part] if part == key_last -> lookup_key(key_last, ctx)
    [key, ..rest] -> {
      let value = lookup_key(key, ctx)
      case rest {
        [] -> value
        _ -> resolve_parts(rest, value)
      }
    }
  }
}

fn resolve_this(ctx: Value) -> Value {
  case lookup_key(key_this, ctx) {
    VNil -> ctx
    value -> value
  }
}

fn lookup_key(key: String, ctx: Value) -> Value {
  case ctx {
    VDict(props) ->
      case list.key_find(props, key) {
        Ok(value) -> value
        Error(_) -> VNil
      }
    _ -> VNil
  }
}

// ============================================================================
// Value helpers
// ============================================================================

fn count_newlines(s: String) -> Int {
  do_count_newlines(s, 0)
}

fn do_count_newlines(s: String, acc: Int) -> Int {
  case string.split_once(s, "\n") {
    Ok(#(_, rest)) -> do_count_newlines(rest, acc + 1)
    Error(_) -> acc
  }
}

fn is_truthy(value: Value) -> Bool {
  case value {
    VNil -> False
    VBool(False) -> False
    VStr("") -> False
    VList([]) -> False
    _ -> True
  }
}

fn value_to_string(value: Value) -> String {
  case value {
    VStr(s) -> s
    VBool(True) -> "true"
    VBool(False) -> "false"
    VInt(i) -> int.to_string(i)
    VFloat(f) -> float.to_string(f)
    VList(_) -> ""
    VDict(_) -> ""
    VNil -> ""
  }
}

// ============================================================================
// Context building from skill + provider metadata
// ============================================================================

pub fn build_context(
  skill: Skill,
  target: Provider,
  provider_meta: yay.Node,
) -> Value {
  let base_props = [
    #("name", VStr(skill.name)),
    #("version", VStr(semver.to_string(skill.version))),
    #("description", VStr(skill.description)),
    #("provider", VStr(types.provider_to_string(target))),
  ]

  let optional_props =
    list.filter_map(
      [
        #("license", skill.license),
        #("homepage", skill.homepage),
        #("repository", skill.repository),
      ],
      fn(pair) {
        case pair.1 {
          Some(value) -> Ok(#(pair.0, VStr(value)))
          None -> Error(Nil)
        }
      },
    )

  let dep_values =
    list.map(skill.dependencies, fn(dep) {
      VDict([
        #("name", VStr(dep.name)),
        #("version", VStr(version_constraint.to_string(dep.version))),
        #("optional", VBool(dep.optional)),
      ])
    })

  let metadata_props = case skill.metadata {
    Some(m) -> {
      let inner =
        list.flatten([
          list.filter_map(
            [#("author", m.author), #("author_email", m.author_email)],
            fn(pair) {
              case pair.1 {
                Some(value) -> Ok(#(pair.0, VStr(value)))
                None -> Error(Nil)
              }
            },
          ),
          [#("tags", VList(list.map(m.tags, fn(t) { VStr(t) })))],
        ])
      [#("metadata", VDict(inner))]
    }
    None -> []
  }

  let config_values =
    list.map(skill.config, fn(cf) {
      let #(required_val, default_prop) = case cf.requirement {
        Required -> #(True, [])
        Optional -> #(False, [])
        OptionalWithDefault(d) -> #(False, [#("default", VStr(d))])
      }
      VDict(
        list.flatten([
          [
            #("name", VStr(cf.name)),
            #("description", VStr(cf.description)),
            #("required", VBool(required_val)),
            #("secret", VBool(cf.secret)),
          ],
          default_prop,
        ]),
      )
    })

  VDict(
    list.flatten([
      base_props,
      optional_props,
      [#("dependencies", VList(dep_values))],
      metadata_props,
      [#("config", VList(config_values))],
      [#("meta", node_to_value(provider_meta))],
    ]),
  )
}

fn node_to_value(node: yay.Node) -> Value {
  case node {
    yay.NodeStr(s) -> VStr(s)
    yay.NodeInt(i) -> VInt(i)
    yay.NodeFloat(f) -> VFloat(f)
    yay.NodeBool(b) -> VBool(b)
    yay.NodeNil -> VNil
    yay.NodeSeq(items) -> VList(list.map(items, node_to_value))
    yay.NodeMap(pairs) ->
      VDict(
        list.filter_map(pairs, fn(pair) {
          case pair {
            #(yay.NodeStr(key), value) -> Ok(#(key, node_to_value(value)))
            _ -> Error(Nil)
          }
        }),
      )
  }
}
