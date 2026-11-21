// EXPECT: zilc: error: in `main`: slice_ptr of `i64`, which is not a slice
f0: i32 main() {
  @b0:
    v1: i64 = const 42
    v2: Ptr<u8, 'local> = slice_ptr v1
    v3: i32 = const 0
    ret v3
}
