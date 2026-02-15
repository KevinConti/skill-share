import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import skillc/error.{type SkillError, TemplateError}
import skillc/types.{type Skill}
import yay

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
  do_process_provider_blocks(content, target, "")
}

fn do_process_provider_blocks(
  remaining: String,
  target: String,
  acc: String,
) -> Result(String, SkillError) {
  case string.split_once(remaining, "{{#provider ") {
    Ok(#(before, after_open)) -> {
      case parse_provider_tag(after_open) {
        Ok(#(providers, after_tag)) -> {
          case find_closing_provider(after_tag, 1) {
            Ok(#(block_content, after_close)) -> {
              let should_include = list.contains(providers, target)
              let new_acc = case should_include {
                True -> acc <> before <> string.trim(block_content) <> "\n"
                False -> acc <> before
              }
              do_process_provider_blocks(after_close, target, new_acc)
            }
            Error(_) ->
              Error(TemplateError(
                line_at(acc <> before),
                "Unclosed {{#provider}} block",
              ))
          }
        }
        Error(_) ->
          Error(TemplateError(
            line_at(acc <> before),
            "Malformed {{#provider}} tag: missing provider names or closing }}",
          ))
      }
    }
    Error(_) -> Ok(acc <> remaining)
  }
}

fn parse_provider_tag(
  content: String,
) -> Result(#(List(String), String), Nil) {
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
  let placeholder = "___ESCAPED_OPEN_BRACE___"
  let content = string.replace(content, "\\{{", placeholder)
  // Render template
  use output <- result.try(render_tokens(content, context))
  // Post-process: restore escaped braces
  let output = string.replace(output, placeholder, "{{")
  Ok(output)
}

fn process_raw_blocks(content: String, acc: String) -> String {
  case string.split_once(content, "{{{{raw}}}}") {
    Ok(#(before, after_open)) -> {
      case string.split_once(after_open, "{{{{/raw}}}}") {
        Ok(#(raw_content, after_close)) -> {
          let placeholder = "___ESCAPED_OPEN_BRACE___"
          let escaped = string.replace(raw_content, "{{", placeholder)
          process_raw_blocks(after_close, acc <> before <> escaped)
        }
        Error(_) -> acc <> content
      }
    }
    Error(_) -> acc <> content
  }
}

fn render_tokens(content: String, ctx: Value) -> Result(String, SkillError) {
  do_render(content, ctx, "")
}

fn do_render(
  remaining: String,
  ctx: Value,
  acc: String,
) -> Result(String, SkillError) {
  case string.split_once(remaining, "{{") {
    Error(_) -> Ok(acc <> remaining)
    Ok(#(before, after_open)) -> {
      case string.split_once(after_open, "}}") {
        Error(_) ->
          Error(TemplateError(
            line_at(acc <> before),
            "Unbalanced tag: missing closing }}",
          ))
        Ok(#(tag_body, after_close)) -> {
          let tag = string.trim(tag_body)
          case tag {
            // Block helpers
            "#if " <> path -> {
              let path = string.trim(path)
              use #(block_content, rest) <- result.try(
                find_block_end(after_close, "if", acc <> before),
              )
              let value = resolve_path(path, ctx)
              case is_truthy(value) {
                True -> {
                  use rendered_block <- result.try(
                    render_tokens(block_content, ctx),
                  )
                  do_render(rest, ctx, acc <> before <> rendered_block)
                }
                False -> do_render(rest, ctx, acc <> before)
              }
            }
            "#unless " <> path -> {
              let path = string.trim(path)
              use #(block_content, rest) <- result.try(
                find_block_end(after_close, "unless", acc <> before),
              )
              let value = resolve_path(path, ctx)
              case is_truthy(value) {
                True -> do_render(rest, ctx, acc <> before)
                False -> {
                  use rendered_block <- result.try(
                    render_tokens(block_content, ctx),
                  )
                  do_render(rest, ctx, acc <> before <> rendered_block)
                }
              }
            }
            "#each " <> path -> {
              let path = string.trim(path)
              use #(block_content, rest) <- result.try(
                find_block_end(after_close, "each", acc <> before),
              )
              let value = resolve_path(path, ctx)
              case value {
                VList(items) -> {
                  let len = list.length(items)
                  use rendered_items <- result.try(
                    render_each_items(block_content, items, ctx, 0, len, ""),
                  )
                  do_render(rest, ctx, acc <> before <> rendered_items)
                }
                _ -> do_render(rest, ctx, acc <> before)
              }
            }
            // Variable interpolation
            _ -> {
              let value = resolve_path(tag, ctx)
              let str_value = value_to_string(value)
              do_render(after_close, ctx, acc <> before <> str_value)
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
  _parent_ctx: Value,
  index: Int,
  total: Int,
  acc: String,
) -> Result(String, SkillError) {
  case items {
    [] -> Ok(acc)
    [item, ..rest] -> {
      // Build context for each item: the item itself + @index, @first, @last
      let is_last = index == total - 1
      let is_first = index == 0
      let special_keys = [
        #("@index", VInt(index)),
        #("@first", VBool(is_first)),
        #("@last", VBool(is_last)),
      ]
      let item_ctx = case item {
        VDict(props) ->
          VDict(
            list.append(
              [#("this", item)],
              list.append(props, special_keys),
            ),
          )
        _ ->
          VDict(list.append([#("this", item)], special_keys))
      }
      use rendered <- result.try(render_tokens(template, item_ctx))
      render_each_items(template, rest, VNil, index + 1, total, acc <> rendered)
    }
  }
}

fn find_block_end(
  content: String,
  block_type: String,
  consumed_before: String,
) -> Result(#(String, String), SkillError) {
  let open_tag = "{{#" <> block_type <> " "
  let close_tag = "{{/" <> block_type <> "}}"
  do_find_block_end(content, open_tag, close_tag, 1, "", consumed_before)
}

fn do_find_block_end(
  remaining: String,
  open_tag: String,
  close_tag: String,
  depth: Int,
  acc: String,
  consumed_before: String,
) -> Result(#(String, String), SkillError) {
  case depth {
    0 -> Ok(#(acc, remaining))
    _ -> {
      // Find the next occurrence of either open or close tag
      let open_pos = find_position(remaining, open_tag)
      let close_pos = find_position(remaining, close_tag)
      case close_pos {
        -1 -> {
          let block_name =
            open_tag
            |> string.replace("{{#", "")
            |> string.trim()
          Error(TemplateError(
            line_at(consumed_before <> acc),
            "Unclosed {{#" <> block_name <> "}} block",
          ))
        }
        _ -> {
          case open_pos >= 0 && open_pos < close_pos {
            True -> {
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
                consumed_before,
              )
            }
            False -> {
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
                    consumed_before,
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

fn find_position(haystack: String, needle: String) -> Int {
  do_find_position(haystack, needle, 0)
}

fn do_find_position(haystack: String, needle: String, pos: Int) -> Int {
  case string.starts_with(haystack, needle) {
    True -> pos
    False -> {
      case string.pop_grapheme(haystack) {
        Ok(#(_, rest)) -> do_find_position(rest, needle, pos + 1)
        Error(_) -> -1
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

fn count_newlines(s: String) -> Int {
  string.to_graphemes(s)
  |> list.count(fn(c) { c == "\n" })
}

fn line_at(consumed: String) -> Int {
  count_newlines(consumed) + 1
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
  let props = [
    #("name", VStr(skill.name)),
    #("version", VStr(skill.version)),
    #("description", VStr(skill.description)),
    #("provider", VStr(target)),
  ]

  let props = case skill.license {
    Some(l) -> list.append(props, [#("license", VStr(l))])
    None -> props
  }

  let props = case skill.homepage {
    Some(h) -> list.append(props, [#("homepage", VStr(h))])
    None -> props
  }

  let props = case skill.repository {
    Some(r) -> list.append(props, [#("repository", VStr(r))])
    None -> props
  }

  // Add dependencies as a list
  let dep_values =
    list.map(skill.dependencies, fn(dep) {
      VDict([
        #("name", VStr(dep.name)),
        #("version", VStr(dep.version)),
        #("optional", VBool(dep.optional)),
      ])
    })
  let props = list.append(props, [#("dependencies", VList(dep_values))])

  // Add universal metadata
  let props = case skill.metadata {
    Some(m) -> {
      let metadata_props = []
      let metadata_props = case m.author {
        Some(a) -> list.append(metadata_props, [#("author", VStr(a))])
        None -> metadata_props
      }
      let metadata_props = case m.author_email {
        Some(e) -> list.append(metadata_props, [#("author_email", VStr(e))])
        None -> metadata_props
      }
      let metadata_props =
        list.append(metadata_props, [
          #("tags", VList(list.map(m.tags, fn(t) { VStr(t) }))),
        ])
      list.append(props, [#("metadata", VDict(metadata_props))])
    }
    None -> props
  }

  // Add config as a list
  let config_values =
    list.map(skill.config, fn(cf) {
      let config_props = [
        #("name", VStr(cf.name)),
        #("description", VStr(cf.description)),
        #("required", VBool(cf.required)),
        #("secret", VBool(cf.secret)),
      ]
      let config_props = case cf.default {
        Some(d) -> list.append(config_props, [#("default", VStr(d))])
        None -> config_props
      }
      VDict(config_props)
    })
  let props = list.append(props, [#("config", VList(config_values))])

  // Add meta from provider metadata node
  let meta_value = node_to_value(provider_meta)
  let props = list.append(props, [#("meta", meta_value)])

  VDict(props)
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
