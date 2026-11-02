// EXPECT: zilc: error: in `main`: field_addr 2 of `PtrMut<..>`, which does not point at a struct or tuple with that field
// A field index past the struct's fields addresses memory beside it.
type T0: struct { x: i64, y: i64 }

f0: i32 main() {
  @b0:
    v1: PtrMut<T0, 'local> = alloc 'local, T0
    v2: PtrMut<i64, 'local> = field_addr v1, 2
    v3: i32 = const 0
    ret v3
}
