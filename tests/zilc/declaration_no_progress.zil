// EXPECT: zilc: line 5: cannot read `t`
// The leftovers of an unknown type spelling: a `t` that starts no `type` declaration, because
// parse_type had left `, 'local>}` behind. The dispatch must not spin on a byte it cannot
// read -- before 2026-10-13 this looped forever instead of failing.
t, 'local>}
