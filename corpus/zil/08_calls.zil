// expected exit code: 6
// 08_calls.zil: Exercises function calls

f0: i32 add_one(x: i32) {
  @b0:
    v2: i32 = const 1
    v3: i32 = add v1, v2
    ret v3
}

f1: i32 main() {
  @b0:
    v1: i32 = const 5
    v2: i32 = call f0(v1)
    ret v2
}
