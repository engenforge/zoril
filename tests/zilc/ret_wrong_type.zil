// EXPECT: zilc: error: in `main`: return of `f64` from a function returning `i32`
// A returned value that is not of the function's result type.
f0: i32 main() {
  @b0:
    v1: f64 = const 0
    ret v1
}
