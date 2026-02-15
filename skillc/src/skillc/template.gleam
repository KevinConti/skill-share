import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import skillc/error.{type SkillError, TemplateError}
import skillc/types.{type Skill}
import yay

const escaped_brace_placeholder = "___ESCAPED_OPEN_BRACE___"

// ============================================================================
// Public API
// ============================================================================

pub fn render_template(
  content: String,
  target: String,
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
  target: String,
) -> Result(String, SkillError) {
  do_process_provider_blocks(content, target, "", content)
}

fn do_process_provider_blocks(
  remaining: String,
  target: String,
  acc: String,
  original: String,
) -> Result(String, SkillError) {
  case string.split_once(remaining, "{{#provider ") {
    Ok(#(before, after_open)) -> {
      // Line number in original source at the opening tag
      let error_line =
        line_at(string.slice(
          original,
          0,
          string.length(original)
            - string.length(remaining)
            + string.length(before),
        ))
      case parse_provider_tag(after_open) {
        Ok(#(providers, after_tag)) -> {
          case find_closing_provider(after_tag, 1) {
            Ok(#(block_content, after_close)) -> {
              let should_include = list.contains(providers, target)
              let new_acc = case should_include {
                True ->
                  acc
                  <> before
                  <> strip_surrounding_newlines(block_content)
                  <> "\n"
                False -> acc <> strip_trailing_newlines(before)
              }
              do_process_provider_blocks(after_close, target, new_acc, original)
            }
            Error(_) ->
              Error(TemplateError(error_line, "Unclosed {{#provider}} block"))
          }
        }
        Error(_) ->
          Error(TemplateError(
            error_line,
            "Malformed {{#provider}} tag: missing provider names or closing }}",
          ))
      }
    }
    Error(_) -> Ok(acc <> remaining)
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
  // Render template (pass content as original for line number tracking)
  use output <- result.try(render_tokens(content, context, content))
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
  original: String,
) -> Result(String, SkillError) {
  do_render(content, ctx, "", original)
}

fn do_render(
  remaining: String,
  ctx: Value,
  acc: String,
  original: String,
) -> Result(String, SkillError) {
  case string.split_once(remaining, "{{") {
    Error(_) -> Ok(acc <> remaining)
    Ok(#(before, after_open)) -> {
      // Compute line in original source from position of remaining
      let source_line =
        line_at(string.slice(
          original,
          0,
          string.length(original)
            - string.length(remaining)
            + string.length(before),
        ))
      case string.split_once(after_open, "}}") {
        Error(_) ->
          Error(TemplateError(source_line, "Unbalanced tag: missing closing }}"))
        Ok(#(tag_body, after_close)) -> {
          let tag = string.trim(tag_body)
          case tag {
            // Block helpers
            "#if " <> path -> {
              let path = string.trim(path)
              use #(block_content, rest) <- result.try(find_block_end(
                after_close,
                "if",
                source_line,
              ))
              let value = resolve_path(path, ctx)
              case is_truthy(value) {
                True -> {
                  use rendered_block <- result.try(render_tokens(
                    block_content,
                    ctx,
                    original,
                  ))
                  do_render(
                    rest,
                    ctx,
                    acc <> before <> rendered_block,
                    original,
                  )
                }
                False -> do_render(rest, ctx, acc <> before, original)
              }
            }
            "#unless " <> path -> {
              let path = string.trim(path)
              use #(block_content, rest) <- result.try(find_block_end(
                after_close,
                "unless",
                source_line,
              ))
              let value = resolve_path(path, ctx)
              case is_truthy(value) {
                True -> do_render(rest, ctx, acc <> before, original)
                False -> {
                  use rendered_block <- result.try(render_tokens(
                    block_content,
                    ctx,
                    original,
                  ))
                  do_render(
                    rest,
                    ctx,
                    acc <> before <> rendered_block,
                    original,
                  )
                }
              }
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
                  use rendered_items <- result.try(render_each_items(
                    block_content,
                    items,
                    ctx,
                    0,
                    len,
                    "",
                    original,
                  ))
                  do_render(
                    rest,
                    ctx,
                    acc <> before <> rendered_items,
                    original,
                  )
                }
                _ -> do_render(rest, ctx, acc <> before, original)
              }
            }
            // Variable interpolation
            _ -> {
              let value = resolve_path(tag, ctx)
              let str_value = value_to_string(value)
              do_render(after_close, ctx, acc <> before <> str_value, original)
            }
          }
        }
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
  original: String,
) -> Result(String, SkillError) {
  case items {
    [] -> Ok(acc)
    [item, ..rest] -> {
      // Build context: parent props (fallback), then item props + specials (priority)
      let is_last = index == total - 1
      let is_first = index == 0
      let special_keys = [
        #("@index", VInt(index)),
        #("@first", VBool(is_first)),
        #("@last", VBool(is_last)),
      ]
      let parent_props = case parent_ctx {
        VDict(props) -> props
        _ -> []
      }
      // Item-specific keys come first (higher priority in list.find lookup)
      let item_keys = case item {
        VDict(props) ->
          list.append([#("this", item)], list.append(props, special_keys))
        _ -> list.append([#("this", item)], special_keys)
      }
      let item_ctx = VDict(list.append(item_keys, parent_props))
      use rendered <- result.try(render_tokens(template, item_ctx, original))
      render_each_items(
        template,
        rest,
        parent_ctx,
        index + 1,
        total,
        acc <> rendered,
        original,
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

fn find_position(haystack: String, needle: String) -> option.Option(Int) {
  do_find_position(haystack, needle, 0)
}

fn do_find_position(
  haystack: String,
  needle: String,
  pos: Int,
) -> option.Option(Int) {
  case string.starts_with(haystack, needle) {
    True -> Some(pos)
    False -> {
      case string.pop_grapheme(haystack) {
        Ok(#(_, rest)) -> do_find_position(rest, needle, pos + 1)
        Error(_) -> None
      }
    }
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
    ["this"] ->
      case lookup_key("this", ctx) {
        VNil -> ctx
        value -> value
      }
    ["this", ..rest] -> {
      let this_val = case lookup_key("this", ctx) {
        VNil -> ctx
        value -> value
      }
      resolve_parts(rest, this_val)
    }
    ["@index"] -> lookup_key("@index", ctx)
    ["@first"] -> lookup_key("@first", ctx)
    ["@last"] -> lookup_key("@last", ctx)
    [key, ..rest] -> {
      let value = lookup_key(key, ctx)
      case rest {
        [] -> value
        _ -> resolve_parts(rest, value)
      }
    }
  }
}

fn lookup_key(key: String, ctx: Value) -> Value {
  case ctx {
    VDict(props) ->
      case list.find(props, fn(p) { p.0 == key }) {
        Ok(#(_, value)) -> value
        Error(_) -> VNil
      }
    _ -> VNil
  }
}

// ============================================================================
// Value helpers
// ============================================================================

fn line_at(consumed: String) -> Int {
  list.length(string.split(consumed, "\n"))
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
  target: String,
  provider_meta: yay.Node,
) -> Value {
  let base_props = [
    #("name", VStr(skill.name)),
    #("version", VStr(skill.version)),
    #("description", VStr(skill.description)),
    #("provider", VStr(target)),
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
        #("version", VStr(dep.version)),
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
      let default_prop = case cf.default {
        Some(d) -> [#("default", VStr(d))]
        None -> []
      }
      VDict(
        list.flatten([
          [
            #("name", VStr(cf.name)),
            #("description", VStr(cf.description)),
            #("required", VBool(cf.required)),
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
