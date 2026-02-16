import gleam/list
import gleam/string

const special_chars = [
  ":", "#", " ", "\"", "'", "[", "]", "{", "}", ",", "&", "*", "!", "|", ">",
  "%", "@", "\n",
]

const reserved_words = [
  "true", "false", "yes", "no", "on", "off", "null", "~", "",
]

pub fn quote_string(s: String) -> String {
  let needs_quoting =
    list.any(special_chars, fn(c) { string.contains(s, c) })
    || list.contains(reserved_words, s)
  case needs_quoting {
    True -> {
      // Escape backslashes first, then double quotes, then newlines
      let escaped = string.replace(s, "\\", "\\\\")
      let escaped = string.replace(escaped, "\"", "\\\"")
      let escaped = string.replace(escaped, "\n", "\\n")
      "\"" <> escaped <> "\""
    }
    False -> s
  }
}
