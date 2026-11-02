zoril-sha256(3)

# NAME

zoril-sha256 - Cryptographic SHA-256 digest computation (Sha256)

# SYNOPSIS

*import* "sha256.zrl";

```
pub struct Sha256 {
pub state: [u32; 8],
pub buffer: [u8; 64],
pub buf_len: usize,
pub total_len: u64,
pub k: [u32; 64],
}
impl Sha256 {
    pub fn new() -> Sha256;
    pub fn reset(self: &mut Sha256);
    pub fn update(self: &mut Sha256, data: [u8]);
    pub fn finalize(self: &mut Sha256) -> [u8; 32];
    pub fn finalize_hex(self: &mut Sha256, out: &mut [u8; 64]);
}
pub fn sha256(data: [u8]) -> [u8; 32];
pub fn sha256_to_hex(digest: &[u8; 32], out: &mut [u8; 64]);
pub fn sha256_hex(data: [u8], out: &mut [u8; 64]);
pub fn sha256_hex_arr(data: [u8]) -> [u8; 64];
```

# DESCRIPTION

The *sha256* module provides cryptographic sha-256 digest computation (sha256) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*Sha256*
```
pub struct Sha256 {
pub state: [u32; 8],
pub buffer: [u8; 64],
pub buf_len: usize,
pub total_len: u64,
pub k: [u32; 64],
}
```

	Streaming cryptographic SHA-256 digest hasher.

*new*
```
pub fn new() -> Sha256;
```

	Creates a new Sha256 hasher initialized to the standard FIPS 180-4 constants.

*reset*
```
pub fn reset(self: &mut Sha256);
```

	Resets the hasher back to initial state for computing a new digest.

*update*
```
pub fn update(self: &mut Sha256, data: [u8]);
```

	Feeds a byte slice of data into the running SHA-256 state.

*finalize*
```
pub fn finalize(self: &mut Sha256) -> [u8; 32];
```

	Completes the hash computation and returns the 32-byte binary digest.

*finalize_hex*
```
pub fn finalize_hex(self: &mut Sha256, out: &mut [u8; 64]);
```

	Completes the hash computation and writes the 64-character lowercase hex digest into out.

*sha256*
```
pub fn sha256(data: [u8]) -> [u8; 32];
```

	One-shot helper computing the 32-byte SHA-256 digest of data.

*sha256_to_hex*
```
pub fn sha256_to_hex(digest: &[u8; 32], out: &mut [u8; 64]);
```

	Formats a 32-byte binary digest into a 64-character hex string allocated in arena a.

*sha256_hex*
```
pub fn sha256_hex(data: [u8], out: &mut [u8; 64]);
```

	One-shot helper computing the 64-character hex SHA-256 digest of data in arena a.

*sha256_hex_arr*
```
pub fn sha256_hex_arr(data: [u8]) -> [u8; 64];
```

	One-shot helper computing the 64-character hex SHA-256 digest into an array.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
