// EXPECT: zilc: error: in `main`: operand v99 names no defined value
// An operand id that names no value (neither a parameter nor an instruction result) must be
// refused. Treating it as SSA 4294967295 produced a wild store that segfaulted.
f0: i32 main() {
  @b0:
    v1: i32 = const 0
    v2: i32 = add v1, v99
    ret v2
}
