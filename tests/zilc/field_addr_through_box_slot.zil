// EXPECT: zilc: error: in `main`: field_addr 1 of `PtrMut<..>`, which does not point at a struct or tuple with that field
// A field address is taken from a pointer to the struct. This takes it from a pointer to the slot that
// holds a pointer to the struct, so field 1 lies 8 bytes past the slot: the lowering of `r.y` on
// `&Box<S>` that skipped the box's dereference.
type T0: struct { x: i64, y: i64 }

f0: i32 main() {
  @b0:
    v1: PtrMut<T0, 'local> = alloc 'local, T0
    v2: PtrMut<PtrMut<T0, 'local>, 'local> = alloc 'local, PtrMut<T0, 'local>
    store v2, v1
    v3: PtrMut<i64, 'local> = field_addr v2, 1
    v4: i32 = const 0
    ret v4
}
