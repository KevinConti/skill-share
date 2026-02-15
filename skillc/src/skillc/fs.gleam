import gleam/list
import gleam/result
import simplifile
import skillc/error.{type SkillError, map_file_error}
import skillc/path
import skillc/types.{type FileCopy}

pub fn copy_file_list(
  files: List(FileCopy),
  dest_dir: String,
) -> Result(Nil, SkillError) {
  case files {
    [] -> Ok(Nil)
    _ -> {
      use _ <- result.try(
        simplifile.create_directory_all(dest_dir)
        |> map_file_error(dest_dir),
      )
      list.try_each(files, fn(f) {
        let dest = dest_dir <> "/" <> f.relative_path
        let parent = path.parent_dir(dest)
        use _ <- result.try(
          simplifile.create_directory_all(parent)
          |> map_file_error(parent),
        )
        simplifile.copy_file(f.src, dest)
        |> map_file_error(f.src)
      })
    }
  }
}
