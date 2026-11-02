// EXPECT: zilc: error: in `main`: field_addr 2 of `PtrMut<..>`, which does not point at a struct or tuple with that field
// A field index past the tuple's elements addresses memory beside it.
f0: i32 main() {
  @b0:
    v1: PtrMut<(i32, i32), 'local> = alloc 'local, (i32, i32)
    v2: PtrMut<i32, 'local> = field_addr v1, 2
    v3: i32 = const 0
    ret v3
}
