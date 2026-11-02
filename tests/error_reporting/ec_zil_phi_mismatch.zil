f1: i32 main(cond: bool) {
  @b0:
    v2: i32 = const 10
    v3: i64 = const 20
    branch v1, @b1, @b2
  @b1:
    jump @b3
  @b2:
    jump @b3
  @b3:
    v4: i32 = phi [@b1: v2, @b2: v3] // @error "phi incoming type mismatch" :15
    ret v4
}
