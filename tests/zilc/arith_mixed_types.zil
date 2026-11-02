// EXPECT: zilc: error: in `main`: arithmetic on `i64` and `i32`
// Arithmetic operands of different widths: the narrower one's upper bits would be garbage.
f0: i32 main() {
  @b0:
    v1: i64 = const 1
    v2: i32 = const 2
    v3: i64 = add v1, v2
    v4: i32 = const 0
    ret v4
}
