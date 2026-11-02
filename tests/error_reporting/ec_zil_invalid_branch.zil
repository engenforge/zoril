f1: i32 main() {
  @b0:
    v1: bool = const 1
    branch v1, @b1, @b2 // @error "branch to non-existent block @b2" :5
  @b1:
    v2: i32 = const 0
    ret v2
}
