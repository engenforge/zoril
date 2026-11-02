// EXPECT: zilc: line 5: unknown instruction `frobnicate`
// zilc must reject an instruction it does not know, not drop it and carry on.
f0: i32 main() {
  @b0:
    frobnicate
    v1: i32 = const 0
    ret v1
}
