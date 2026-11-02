pub fn compute_checksum(seed: i32, count: i32) -> i32 {
    let mut acc: i64 = seed as i64;
    for i in 0..count as i64 {
        acc = (acc * 31 + i) % 1000007;
    }
    acc as i32
}
