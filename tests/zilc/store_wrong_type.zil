// EXPECT: zilc: error: in `main`: store of `f32` through `Ptr<i32>`
// A store whose value is not of the pointee's type: the float's bits would land in an int.
f0: i32 main() {
  @b0:
    v1: Ptr<i32, 'local> = alloc 'local, i32
    v2: f32 = const 0
    store v1, v2
    v3: i32 = const 0
    ret v3
}
