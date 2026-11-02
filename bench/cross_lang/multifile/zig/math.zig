pub fn isPrime(n: i32) bool {
    if (n <= 1) return false;
    var d: i32 = 2;
    while (d * d <= n) : (d += 1) {
        if (@mod(n, d) == 0) return false;
    }
    return true;
}

pub fn countPrimes(limit: i32) i32 {
    var count: i32 = 0;
    var n: i32 = 2;
    while (n <= limit) : (n += 1) {
        if (isPrime(n)) count += 1;
    }
    return count;
}
