f1: i32 main() {
  @b0:
    v1: i32 = add v2, v3 // @error "use of undefined SSA ID v2" :15
    ret v1
}
