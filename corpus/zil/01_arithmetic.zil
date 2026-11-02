// expected exit code: 30
// 01_arithmetic.zil: Exercises arithmetic opcodes

f1: i32 main() {
  @b0:
    v1: i32 = const 10
    v2: i32 = const 20
    v3: i32 = add v1, v2
    ret v3
}
