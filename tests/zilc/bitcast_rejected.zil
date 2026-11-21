// EXPECT: zilc: line 6: unknown opcode 'bitcast' (use 'cast')
// One spelling for cast: zilc refuses 'bitcast' and directs the author to 'cast'.
f0: i32 main() {
  @b0:
    v1: i64 = const 1
    v2: i32 = bitcast v1
    ret v2
}
