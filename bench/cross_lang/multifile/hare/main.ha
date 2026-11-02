use os;

export fn main() void = {
    let p = count_primes(10000);
    let _chk = compute_checksum(p, 5000);
    if (p != 1229) os::exit(1);
};
