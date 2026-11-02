// expected exit code: 11
// 07_branching.zil: Exercises branching and jumps

f1: i32 main() {
  @b0:
    v1: bool = const 1
    branch v1, @b1, @b2
  @b1:
    v2: i32 = const 11
    jump @b3
  @b2:
    v3: i32 = const 22
    jump @b3
  @b3:
    v4: i32 = phi [@b1: v2, @b2: v3]
    ret v4
}
