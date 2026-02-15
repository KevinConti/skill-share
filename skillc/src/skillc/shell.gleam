import gleam/string

@external(javascript, "../skillc_ffi.mjs", "exec")
pub fn exec(cmd: String) -> Result(String, String)

pub fn quote(s: String) -> String {
  "'" <> string.replace(s, "'", "'\\''") <> "'"
}
