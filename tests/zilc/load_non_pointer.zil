// EXPECT: zilc: error: in `main`: load through `i64`, which is not a pointer
f0: i32 main() {
  @b0:
    v1: i64 = const 42
    v2: i64 = load v1
    v3: i32 = const 0
    ret v3
}
