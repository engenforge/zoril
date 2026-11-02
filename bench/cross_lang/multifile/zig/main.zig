const math = @import("math.zig");
const util = @import("util.zig");

pub fn main() u8 {
    const p = math.countPrimes(10000);
    _ = util.computeChecksum(p, 5000);
    if (p != 1229) return 1;
    return 0;
}
