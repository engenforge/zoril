// expected exit code: 1
// 02_comparison.zil: Exercises comparison opcodes

f1: i32 main() {
  @b0:
    v1: i32 = const 10
    v2: i32 = const 20
    v3: bool = lt v1, v2
    v4: i32 = bitcast v3
    ret v4
}
