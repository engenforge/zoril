f1: i32 main() {
  @b0:
    v1: BoxMut<i32> = alloc 'heap, i32
    v2: BoxMut<i32> = move v1
    v3: i32 = load v1 // @error "use of moved value v1" :15
    ret v3
}
