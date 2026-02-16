import gleam/string
import skill_universe/platform

@external(javascript, "../skill_universe_ffi.mjs", "exec")
pub fn exec(cmd: String) -> Result(String, String)

pub fn quote(s: String) -> String {
  case platform.is_windows() {
    True -> "\"" <> string.replace(s, "\"", "\\\"") <> "\""
    False -> "'" <> string.replace(s, "'", "'\\''") <> "'"
  }
}
