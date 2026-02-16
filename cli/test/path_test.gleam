import gleeunit/should
import skill_universe/path

pub fn parent_dir_nested_test() {
  should.equal(path.parent_dir("a/b/c"), "a/b")
}

pub fn parent_dir_root_relative_test() {
  should.equal(path.parent_dir("/foo"), "/")
}

pub fn parent_dir_single_component_test() {
  should.equal(path.parent_dir("foo"), ".")
}

pub fn basename_nested_test() {
  should.equal(path.basename("a/b/c"), "c")
}

pub fn basename_trailing_slash_test() {
  should.equal(path.basename("a/b/c/"), "c")
}

pub fn basename_single_component_test() {
  should.equal(path.basename("foo"), "foo")
}
