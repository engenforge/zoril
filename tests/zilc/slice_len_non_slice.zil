// EXPECT: zilc: error: in `main`: slice_len of `i64`, which is not a slice
f0: i32 main() {
  @b0:
    v1: i64 = const 42
    v2: u64 = slice_len v1
    v3: i32 = const 0
    ret v3
}
