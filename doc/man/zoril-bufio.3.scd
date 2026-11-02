zoril-bufio(3)

# NAME

zoril-bufio - Buffered stream wrappers (BufReader, BufWriter)

# SYNOPSIS

*import* "bufio.zrl";

```
pub struct BufWriter<W> {
/* private fields */
}
pub struct BufReader<R> {
/* private fields */
}
impl<W: Write> BufWriter<W> {
    pub fn new(inner: W) -> BufWriter<W>;
    pub fn with_capacity(inner: W, cap: usize) -> BufWriter<W>;
    pub fn new_in(inner: W, a: &Arena) -> BufWriter<W>;
    pub fn with_capacity_in(inner: W, a: &Arena, cap: usize) -> BufWriter<W>;
    pub fn get_ref(self: &BufWriter<W>) -> &W;
    pub fn get_mut(self: &mut BufWriter<W>) -> &mut W;
    pub fn capacity(self: &BufWriter<W>) -> usize;
    pub fn buffer(self: &BufWriter<W>) -> [u8];
    pub fn flush(self: &mut BufWriter<W>) -> Result<(), Error>;
    pub fn into_inner(mut self) -> Result<W, Error>;
}
impl<W: Write> Write for BufWriter<W> {
    pub fn write(self: &mut BufWriter<W>, s: [u8]) -> Result<usize, Error>;
}
impl<W: Write> Drop for BufWriter<W> {
    pub fn drop(self: &mut BufWriter<W>);
}
impl<R> BufReader<R> {
    pub fn new(inner: R) -> BufReader<R>;
    pub fn with_capacity(inner: R, cap: usize) -> BufReader<R>;
    pub fn new_in(inner: R, a: &Arena) -> BufReader<R>;
    pub fn with_capacity_in(inner: R, a: &Arena, cap: usize) -> BufReader<R>;
    pub fn get_ref(self: &BufReader<R>) -> &R;
    pub fn get_mut(self: &mut BufReader<R>) -> &mut R;
    pub fn capacity(self: &BufReader<R>) -> usize;
    pub fn buffer(self: &BufReader<R>) -> [u8];
    pub fn consume(self: &mut BufReader<R>, amt: usize);
    pub fn into_inner(mut self) -> R;
}
impl<R: Read> BufReader<R> {
    pub fn fill_buf(self: &mut BufReader<R>) -> Result<[u8], Error>;
    pub fn read_until(self: &mut BufReader<R>, delim: u8, out: &mut Vec<u8>) -> Result<usize, Error>;
    pub fn read_line(self: &mut BufReader<R>, out: &mut String) -> Result<usize, Error>;
}
impl<R: Read> Read for BufReader<R> {
    pub fn read(self: &mut BufReader<R>, buf: [mut u8]) -> Result<usize, Error>;
}
```

# DESCRIPTION

The *bufio* module provides buffered stream wrappers (bufreader, bufwriter) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*BufWriter*
```
pub struct BufWriter<W> {
/* private fields */
}
```

	Buffered stream wrapper that batches writes to an underlying sink to reduce system call overhead.

*new*
```
pub fn new(inner: W) -> BufWriter<W>;
```

	Creates a new BufWriter wrapping inner with the default buffer capacity (8192 bytes).

*with_capacity*
```
pub fn with_capacity(inner: W, cap: usize) -> BufWriter<W>;
```

	Creates a new BufWriter wrapping inner with the specified buffer capacity.

*new_in*
```
pub fn new_in(inner: W, a: &Arena) -> BufWriter<W>;
```

	Creates a new BufWriter allocated in arena a with the default buffer capacity.

*with_capacity_in*
```
pub fn with_capacity_in(inner: W, a: &Arena, cap: usize) -> BufWriter<W>;
```

	Creates a new BufWriter allocated in arena a with the specified buffer capacity.

*get_ref*
```
pub fn get_ref(self: &BufWriter<W>) -> &W;
```

	Returns an immutable reference to the underlying writer.

*get_mut*
```
pub fn get_mut(self: &mut BufWriter<W>) -> &mut W;
```

	Returns a mutable reference to the underlying writer.

*capacity*
```
pub fn capacity(self: &BufWriter<W>) -> usize;
```

	Returns the total byte capacity of the internal buffer.

*buffer*
```
pub fn buffer(self: &BufWriter<W>) -> [u8];
```

	Returns the unwritten buffered data as a byte slice.

*flush*
```
pub fn flush(self: &mut BufWriter<W>) -> Result<(), Error>;
```

	Flushes all buffered bytes to the underlying writer.

*into_inner*
```
pub fn into_inner(mut self) -> Result<W, Error>;
```

	Flushes remaining bytes and returns the underlying writer.

*write*
```
pub fn write(self: &mut BufWriter<W>, s: [u8]) -> Result<usize, Error>;
```

	Writes bytes into the buffer, flushing to the inner writer when full.

*drop*
```
pub fn drop(self: &mut BufWriter<W>);
```

	Flushes remaining buffered bytes and releases resources.

*BufReader*
```
pub struct BufReader<R> {
/* private fields */
}
```

	Buffered stream wrapper that reads ahead from an underlying source to reduce system call overhead.

*new*
```
pub fn new(inner: R) -> BufReader<R>;
```

	Creates a new BufReader wrapping inner with the default buffer capacity (8192 bytes).

*with_capacity*
```
pub fn with_capacity(inner: R, cap: usize) -> BufReader<R>;
```

	Creates a new BufReader wrapping inner with the specified buffer capacity.

*new_in*
```
pub fn new_in(inner: R, a: &Arena) -> BufReader<R>;
```

	Creates a new BufReader allocated in arena a with the default buffer capacity.

*with_capacity_in*
```
pub fn with_capacity_in(inner: R, a: &Arena, cap: usize) -> BufReader<R>;
```

	Creates a new BufReader allocated in arena a with the specified buffer capacity.

*get_ref*
```
pub fn get_ref(self: &BufReader<R>) -> &R;
```

	Returns an immutable reference to the underlying reader.

*get_mut*
```
pub fn get_mut(self: &mut BufReader<R>) -> &mut R;
```

	Returns a mutable reference to the underlying reader.

*capacity*
```
pub fn capacity(self: &BufReader<R>) -> usize;
```

	Returns the total byte capacity of the internal read buffer.

*buffer*
```
pub fn buffer(self: &BufReader<R>) -> [u8];
```

	Returns the available unconsumed buffered data as a byte slice.

*consume*
```
pub fn consume(self: &mut BufReader<R>, amt: usize);
```

	Advances the internal read position by amt bytes.

*into_inner*
```
pub fn into_inner(mut self) -> R;
```

	Unwraps the BufReader, returning the underlying reader.

*fill_buf*
```
pub fn fill_buf(self: &mut BufReader<R>) -> Result<[u8], Error>;
```

	Refills the internal buffer from the underlying reader if empty and returns available bytes.

*read_until*
```
pub fn read_until(self: &mut BufReader<R>, delim: u8, out: &mut Vec<u8>) -> Result<usize, Error>;
```

	Reads bytes into buf until delimiter delim is encountered or EOF is reached.

*read_line*
```
pub fn read_line(self: &mut BufReader<R>, out: &mut String) -> Result<usize, Error>;
```

	Reads bytes into buf until a newline (0x0A) byte is encountered or EOF is reached.

*read*
```
pub fn read(self: &mut BufReader<R>, buf: [mut u8]) -> Result<usize, Error>;
```

	Reads bytes into buf from the internal buffer, refilling from the underlying reader as needed.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
