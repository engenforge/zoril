// EXPECT: zilc: line 7: unknown type name `WibblePtr`
// A type spelling this zilc does not know: the ZIL was written by a newer compiler, so the
// name is a type CONSTRUCTOR (it takes `<...>`), not a var type. Reading it as a var type
// left the arguments behind and the parser then looped in parse_module until the build's
// timeout, with no message at all -- which is how the fresh-checkout bootstrap failed on
// 2026-10-13, when src/ began writing Phase D's `RawPtr`/`RawPtrMut`.
type T0: struct {p: WibblePtr<u8, 'local>}
