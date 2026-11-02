pub fn computeChecksum(seed: i32, count: i32) i32 {
    var acc: i64 = seed;
    var i: i64 = 0;
    while (i < count) : (i += 1) {
        acc = @mod(acc * 31 + i, 1000007);
    }
    return @intCast(acc);
}
