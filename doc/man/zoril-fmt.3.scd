zoril-fmt(3)

# NAME

zoril-fmt - Sink-agnostic formatting for decimal integers and hexadecimal bytes

# SYNOPSIS

*import* "fmt.zrl";

```
pub fn write_u64<W: Write>(w: &mut W, v: u64) -> Result<(), Error>;
pub fn write_i64<W: Write>(w: &mut W, v: i64) -> Result<(), Error>;
pub fn write_u64_hex<W: Write>(w: &mut W, v: u64) -> Result<(), Error>;
pub fn write_hex_byte<W: Write>(w: &mut W, b: u8) -> Result<(), Error>;
```

# DESCRIPTION

The *fmt* module provides sink-agnostic formatting for decimal integers and hexadecimal bytes for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*write_u64*
```
pub fn write_u64<W: Write>(w: &mut W, v: u64) -> Result<(), Error>;
```

	Formats a 64-bit unsigned integer as decimal digits to any Write sink.

*write_i64*
```
pub fn write_i64<W: Write>(w: &mut W, v: i64) -> Result<(), Error>;
```

	Formats a 64-bit signed integer as decimal digits to any Write sink.

*write_u64_hex*
```
pub fn write_u64_hex<W: Write>(w: &mut W, v: u64) -> Result<(), Error>;
```

	Formats a 64-bit unsigned integer as hexadecimal digits to any Write sink.

*write_hex_byte*
```
pub fn write_hex_byte<W: Write>(w: &mut W, b: u8) -> Result<(), Error>;
```

	Formats a byte as two lowercase hexadecimal digits to any Write sink.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
