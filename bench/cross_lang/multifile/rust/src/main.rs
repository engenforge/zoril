mod math;
mod util;

fn main() {
    let p = math::count_primes(10000);
    let _chk = util::compute_checksum(p, 5000);
    if p != 1229 {
        std::process::exit(1);
    }
}
