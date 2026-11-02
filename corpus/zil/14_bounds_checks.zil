// expected exit code: 0
// 14_bounds_checks.zil: Exercises bounds checking

f1: i32 main() {
  @b0:
    v1: u64 = const 5
    v2: u64 = const 10
    v3: unit = bounds_check v1, v2
    v4: i32 = const 0
    ret v4
}
