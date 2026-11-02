// EXPECT: zilc: error: in `main`: store through `u64`, which is not a pointer
// A store's address operand must be pointer-typed. `{ } *r = 5` once lowered to a store whose
// address was an integer multiplication; zilc emitted it and the program faulted.
f0: i32 main() {
  @b0:
    v1: u64 = const 3
    v2: i32 = const 9
    store v1, v2
    v3: i32 = const 0
    ret v3
}
