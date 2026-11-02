// expected exit code: 7
// 10_globals.zil: Exercises global variable access

global g0: i32 = { 7, 0, 0, 0 }

f1: i32 main() {
  @b0:
    v1: PtrMut<i32, 'static> = global_addr 0
    v2: i32 = load v1
    ret v2
}
