// expected exit code: 7
// 20_variadic.zil: Exercises variadic function definition and call
// The variadic function ignores extra args and returns its fixed parameter.

f0: i32 return_first(x: i32, ...) {
  @b0:
    ret v1
}

f1: i32 main() {
  @b0:
    v1: i32 = const 7
    v2: i32 = const 100
    v3: i32 = const 200
    v4: i32 = call f0(v1, v2, v3)
    ret v4
}
