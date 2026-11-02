// expected exit code: 42
// 18_func_ptr.zil: Exercises func_addr and call_ptr (indirect calls)

f0: i32 double_it(x: i32) {
  @b0:
    v2: i32 = add v1, v1
    ret v2
}

f1: i32 main() {
  @b0:
    v1: fn(i32) -> i32 = func_addr f0
    v2: i32 = const 21
    v3: i32 = call_ptr v1(v2)
    ret v3
}
