// EXPECT: zilc: line 7: expected a declaration, found 'garbage'
f0: i32 helper() {
  @b0:
    v1: i32 = const 1
    ret v1
}
garbage
f1: i32 main() {
  @b0:
    v1: i32 = const 0
    ret v1
}
