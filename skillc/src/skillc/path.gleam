import gleam/list
import gleam/string

pub fn parent_dir(path: String) -> String {
  case string.split(path, "/") |> list.reverse() {
    [_, ..rest] if rest != [] ->
      case string.join(list.reverse(rest), "/") {
        "" -> "/"
        result -> result
      }
    _ -> "."
  }
}

pub fn basename(path: String) -> String {
  let trimmed = case string.ends_with(path, "/") {
    True -> string.drop_end(path, 1)
    False -> path
  }
  case string.split(trimmed, "/") |> list.last() {
    Ok(name) -> name
    Error(_) -> trimmed
  }
}
