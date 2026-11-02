zoril-softfp(3)

# NAME

zoril-softfp - Software floating-point arithmetic primitives

# SYNOPSIS

*import* "softfp.zrl";

```
pub fn softfp_u64_to_f64_bits(v: u64) -> u64;
pub fn softfp_f64_add_bits(a: u64, b: u64) -> u64;
pub fn softfp_f64_mul_bits(a: u64, b: u64) -> u64;
pub fn softfp_f64_to_f32_bits(bits: u64) -> u32;
```

# DESCRIPTION

The *softfp* module provides software floating-point arithmetic primitives for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*softfp_u64_to_f64_bits*
```
pub fn softfp_u64_to_f64_bits(v: u64) -> u64;
```

	u64 -> f64 bits, round-to-nearest-even (matches hardware unsigned convert).

*softfp_f64_add_bits*
```
pub fn softfp_f64_add_bits(a: u64, b: u64) -> u64;
```

	f64 + f64 on bit patterns. Both operands must be non-negative and finite.

*softfp_f64_mul_bits*
```
pub fn softfp_f64_mul_bits(a: u64, b: u64) -> u64;
```

	f64 \* f64 on bit patterns. Finite operands; signs, denormals, and
	underflow-to-denormal handled; overflow is an ICE (the compiler never
	multiplies its way to infinity).

*softfp_f64_to_f32_bits*
```
pub fn softfp_f64_to_f32_bits(bits: u64) -> u32;
```

	f64 bits -> f32 bits, round-to-nearest-even (matches cvtsd2ss). Finite
	input; overflow produces the f32 infinity like the hardware does.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
