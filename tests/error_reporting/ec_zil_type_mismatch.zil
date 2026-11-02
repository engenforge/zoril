f1: i32 main() {
  @b0:
    v1: i32 = const 10
    v2: i64 = const 20
    v3: i32 = add v1, v2 // @error "arithmetic type mismatch (right)" :15
    ret v3
}
