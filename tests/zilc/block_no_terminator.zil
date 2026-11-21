// EXPECT: zilc: error: in `main`: block ends without a terminator
f0: i32 main() {
  @b0:
    v1: i32 = const 0
}
