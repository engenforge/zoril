// EXPECT: zilc: error: in `main`: branch/jump target names no defined block
f0: i32 main() {
  @b0:
    jump @b99
}
