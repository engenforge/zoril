// expected exit code: 99
// 22_region_cast.zil: Exercises region_cast (cast pointer to shorter-lived region)

global g0: i32 = { 99, 0, 0, 0 }

f1: i32 main() {
  @b0:
    // Take address of static global, cast down to 'local region
    v1: PtrMut<i32, 'static> = global_addr 0
    v2: Ptr<i32, 'local> = region_cast 'local, v1
    v3: i32 = load v2
    ret v3
}
