// expected exit code: 2
// 03_bitwise.zil: Exercises bitwise opcodes

f1: i32 main() {
  @b0:
    v1: i32 = const 1
    v2: i32 = const 1
    v3: i32 = shl v1, v2
    ret v3
}
