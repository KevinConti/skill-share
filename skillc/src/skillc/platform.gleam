pub type Platform {
  Windows
  Linux
  MacOS
  Other(String)
}

pub fn detect() -> Platform {
  case platform_string() {
    "win32" -> Windows
    "linux" -> Linux
    "darwin" -> MacOS
    other -> Other(other)
  }
}

pub fn is_windows() -> Bool {
  detect() == Windows
}

@external(javascript, "../skillc_ffi.mjs", "platform_string")
fn platform_string() -> String

@external(javascript, "../skillc_ffi.mjs", "tmpdir")
pub fn tmpdir() -> String
