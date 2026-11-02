// expected exit code: 24
// 09_phi.zil: Exercises complex phi nodes

f1: i32 main() {
  @b0:
    v1: i32 = const 10
    v2: bool = const 1
    branch v2, @b1, @b2
  @b1:
    v3: i32 = const 14
    jump @b3
  @b2:
    v4: i32 = const 20
    jump @b3
  @b3:
    v5: i32 = phi [@b1: v3, @b2: v4]
    v6: i32 = add v1, v5
    ret v6
}
