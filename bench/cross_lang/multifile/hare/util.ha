export fn compute_checksum(seed: int, count: int) int = {
    let acc: i64 = seed: i64;
    for (let i = 0i64; i < count: i64; i += 1) {
        acc = (acc * 31i64 + i) % 1000007i64;
    };
    return acc: int;
};
