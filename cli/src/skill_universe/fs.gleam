import gleam/list
import gleam/result
import simplifile
import skill_universe/error.{type SkillError, map_file_error}
import skill_universe/path
import skill_universe/types.{
  type FileCopy, file_copy_relative_path, file_copy_src,
}

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
        let dest = dest_dir <> "/" <> file_copy_relative_path(f)
        let parent = path.parent_dir(dest)
        use _ <- result.try(
          simplifile.create_directory_all(parent)
          |> map_file_error(parent),
        )
        simplifile.copy_file(file_copy_src(f), dest)
        |> map_file_error(file_copy_src(f))
      })
    }
  }
}
