// EXPECT: zilc: error: in `main`: syscall with more than 6 arguments (runtime supports 0..6)
f0: i32 main() {
  @b0:
    v1: i64 = const 1
    v2: i64 = syscall v1, v1, v1, v1, v1, v1, v1, v1
    v3: i32 = const 0
    ret v3
}
