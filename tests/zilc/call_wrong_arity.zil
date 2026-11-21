// EXPECT: zilc: error: in `main`: call expected 2 arguments, got 1
f0: i32 helper(v0: i32, v1: i32) {
  @b0:
    v2: i32 = add v0, v1
    ret v2
}

f1: i32 main() {
  @b0:
    v1: i32 = const 1
    v2: i32 = call f0(v1)
    ret v2
}
