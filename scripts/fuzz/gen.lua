-- scripts/fuzz/gen.lua -- generate safe (no `unsafe`) programs for the Phase B fuzzer.
--
-- Compositional rather than templated: a program is built as a tree from a small grammar of the
-- subset Zoril and Rust share (integers, references, structs with reference fields, tuples,
-- `Option<&T>`, arrays, slices, `Box`, arenas, closures, `while`, `match`/`if let`,
-- reference-forwarding functions and generics), and both languages are printed from that one tree.
-- Types are respected as the tree is built, so the corpus is mostly programs both compilers can
-- talk about; *lifetimes* are not guaranteed, which is the point - the boundary shapes (a borrow
-- stored past its block, a value passed where an address is expected) are what the two oracles are
-- for. The ten hand-written templates of the first version stay available as a fixed seed set
-- (`--mode=templates`).
--
-- Two things beyond the crash differential live here, because a crash is not the only way a
-- memory-safety hole shows itself:
--
--   * value canaries.  A generated program writes a known value into a stack slot or an arena
--     allocation (`7 + i * 92` on iteration `i`, and a fresh `99` allocation after every
--     `reset`/`reset_to`) and checks the value it reads back through a reference, slice or closure.
--     A dangling read then reads the *next* occupant (99) instead of the value it was created
--     with (7) and the program exits 92 - a fault the crash oracle could never see, because the
--     page is still mapped and the read is "successful".
--   * drop accounting.  A value with a `Drop` impl increments `DROPS` and every construction
--     increments `CONSTRUCTED`; `main` exits 91 when they differ. A double drop (a shallow copy
--     dropped twice) or a missing drop is then a fault rather than a program that exits 0.
--
-- The `--mode=calibration` stream emits one program per known memory-safety hole, each of which is
-- expected to be *rejected* by a fixed compiler and to exit 91/92/139 today. `bench/fuzz/README.md`
-- records the table, and `scripts/fuzz_calibrate.sh` runs it.
--
-- Deterministic from (--seed, --count): a tiny LCG, not math.random, so a finding reproduces on any
-- Lua version. Every program prints one manifest line: `TAGS program path`, the tags naming what it
-- contains, which is what the driver turns into a coverage report.
--
-- Usage: lua scripts/fuzz/gen.lua --seed N --count K --out DIR
--            [--mode grammar|templates|both|mix|mismatch|calibration] [--boundary P] [--types N] [--split P]

if not math.tointeger then io.stderr:write("gen.lua needs Lua 5.3 or newer (this is " .. _VERSION .. ")\n"); os.exit(2) end
local mode, seed, count, outdir, boundary_pct, max_types = "grammar", 1, 4, nil, 30, 2
local holes = 0
-- Percent of the compositional programs whose declarations go into a library module the program imports
-- (`--split 0` keeps every program one file). Decided from the seed and the program number, not the
-- generator's stream, so the programs themselves do not change.
local split_pct = 34
local swarm = 1            -- per-program random subset of the builders (`--swarm 0` draws from all of them)

local function feature_list()
    local fs = {
        "reference-to-local", "mutable-reference-to-local", "dereference",
        "write-through-mut-ref", "owned-box", "option-of-reference",
        "reference-in-struct-field", "reference-in-tuple", "read-through-struct-ref-field",
        "read-through-tuple-ref", "reference-forwarding-helper", "borrow-inside-a-block",
        "borrow-inside-a-loop", "match-binding-through-reference",
        "if-let-binding-through-reference", "closure-capturing-a-reference",
        "drop-type-holding-a-reference", "raw-pointer-value-in-a-struct",
        "address-like-value-passed-loosely", "borrow-of-an-inner-local-kept-outside",
        "closure-assigned-out-of-its-block", "call-forwarding-a-reference",
        "borrow-passed-as-owned-box", "owned-box-passed-as-borrow", "box-field-through-reference",
        "raw-pointer-dereferenced-through-a-container",
        "capability-mismatch", "capability-mismatch-ref-shared-for-mut",
        "capability-mismatch-raw-shared-for-mut", "capability-mismatch-ref-for-box",
        "capability-mismatch-box-for-ref", "capability-mismatch-as-argument",
        "capability-mismatch-as-let", "capability-mismatch-as-return",
        "capability-mismatch-as-struct-field",
        "capability-mismatch-raw-deref-through-a-container",
        "arena-value", "collection-tied-to-an-arena",
        -- the array/slice/indexing grammar (Unified Solution A's routes)
        "array-value", "array-repeat", "index-read", "index-borrow", "index-mut-borrow",
        "index-compound-assign", "immutable-index-write", "slice-value",
        -- arena lifecycle (ring 1 of the runtime oracle)
        "arena-push", "arena-slice", "arena-reset", "arena-mark", "arena-reset-to",
        "boxed-arena-slice", "arena-index-reset",
        -- borrow dataflow routes (Unified Solution B)
        "branch-conditional-borrow", "loop-carried-borrow",
        "loop-carried-container-growth", "by-value-container-move",
        -- return storage (Unified Solution C)
        "reference-returning-helper", "reference-returning-helper-alias",
        "struct-wrapping-reference", "link-reference-helper",
        -- closure ownership (Unified Solution D)
        "closure-captures-owning-value", "closure-returns-capture",
        "loop-closure-environment-escape", "drop-count",
        -- pattern lowering (Unified Solution E)
        "destructure-owning-tuple", "match-borrowed-enum-payload", "raw-pointer-pattern",
        -- plain function pointers
        "function-pointer-call", "function-pointer-mut-container",
        -- runtime checks reached with a value computed at run time (the generator knows which fire)
        "dynamic-array-index", "dynamic-slice-index", "dynamic-divisor", "dynamic-shift-count",
        "expected-trap",
        -- collection buffer ownership (review round 4, 2026-10-22)
        "local-buffer-return", "buffer-view", "drop-while-borrowed",
        -- a `fn` value whose callee stores a reference parameter (review round 5, 2026-10-22)
        "fn-value", "store-through-parameter", "stack-pointer-store",
        -- the program's helpers, types and statics live in a library module its `main` imports (Z2)
        "multi-module", "module-contract-attribute", "library-private-item", "user-trait-default-method", "private-trait-impl", "library-generic-impl-shapes", "box-allocator-in-interface", "impl-in-another-module", "private-item-across-modules", "module-name-not-an-identifier", "module-name-shape", "root-name-leading-digit", "stdlib-generic-contract",
    }
    table.sort(fs)
    return fs
end

local function parse_args()
    local i = 1
    while i <= #arg do
        local a = arg[i]
        if a == "--seed" then seed = tonumber(arg[i+1]); i = i + 2
        elseif a == "--count" then count = tonumber(arg[i+1]); i = i + 2
        elseif a == "--out" then outdir = arg[i+1]; i = i + 2
        elseif a == "--mode" then mode = arg[i+1]; i = i + 2
        elseif a == "--boundary" then boundary_pct = tonumber(arg[i+1]); i = i + 2
        elseif a == "--holes" then holes = tonumber(arg[i+1]); i = i + 2
        elseif a == "--swarm" then swarm = tonumber(arg[i+1]); i = i + 2
        elseif a == "--split" then split_pct = tonumber(arg[i+1]); i = i + 2
        elseif a == "--features" then
            print(table.concat(feature_list(), "\n"))
            os.exit(0)
        elseif a == "--types" then max_types = tonumber(arg[i+1]); i = i + 2
        else io.stderr:write("gen.lua: unknown argument " .. tostring(a) .. "\n"); os.exit(2) end
    end
    if not outdir then
        io.stderr:write("gen.lua: --out is required\n"); os.exit(2)
    end
end

-- A 32-bit LCG (Numerical Recipes): deterministic everywhere, and independent of Lua's own RNG.
local rng_state = 0
local function rng_seed(s) rng_state = (s * 2654435761) % 4294967296 end
local function rnd(n)                                     -- 1..n
    rng_state = (1103515245 * rng_state + 12345) % 2147483648
    return (math.floor(rng_state / 65536) % n) + 1
end
local function chance(percent) return rnd(100) <= percent end

-- Types the grammar knows. `spell` is the source spelling per language; `ref` marks the address-like
-- ones (what the loose-operand rule may exchange), `scoped_ref` the ones whose value borrows a local.
local TYPES = {
    I32       = { name = "I32",         z = "i32",       r = "i32",       int = true },
    REF_I32   = { name = "REF_I32",     z = "&i32",      r = "&i32",      ref = true, borrows = true },
    REFMUT_I32= { name = "REFMUT_I32",  z = "&mut i32",  r = "&mut i32",  ref = true, mutable = true, borrows = true },
    BOX_I32   = { name = "BOX_I32",     z = "Box<i32>",  r = "Box<i32>",  box = true },
    OPT_REF   = { name = "OPT_REF",     z = "Option<&i32>", r = "Option<&i32>", borrows = true },
    HOLDER    = { name = "HOLDER",      z = "Holder",    r = "Holder<'a>", borrows = true, holder = true },
    TUP2      = { name = "TUP2",        z = "(i32, &i32)", r = "(i32, &i32)", borrows = true },
    RAW       = { name = "RAW",         z = "*mut i32",  r = "*mut i32",  raw = true },
    -- A closure value: carried so a program can hold one, but not address-like, so no other
    -- statement reaches for it as an operand.
    CLOSURE   = { name = "CLOSURE",     z = "fn(i32) -> i32", r = "fn(i32) -> i32" },
    -- Owning values. An arena is Zoril-only, so its Rust twin is the lifetime shim `ArenaVec`
    -- (printed below): a value that borrows an `Arena` for as long as the value is used, which is
    -- what makes `rustc` a real borrow oracle for arena invalidation. `owns` marks a value as
    -- owning something, which is what the manifest counts.
    ARENA     = { name = "ARENA",       z = "Arena",      r = "Arena",     owns = true, arena = true },
    VEC_ARENA = { name = "VEC_ARENA",   z = "Vec<i32>",   r = "ArenaVec<i32>", owns = true },
    DROPOWN   = { name = "DROPOWN",     z = "DHolder",    r = "DHolder<'a>", owns = true, borrows = true },
    -- Fixed arrays and slices. Zoril's `[T]` is a fat value; Rust's is `&[T]`, and a mutable Zoril
    -- slice `[mut T]` has no spelling in Rust, so the twin uses `&mut [T]` for it.
    ARR_I32   = { name = "ARR_I32",     z = "[i32; 4]",  r = "[i32; 4]",  array = true },
    ARR_REF65 = { name = "ARR_REF65",   z = "[&i32; 65]", r = "[&i32; 65]", array = true, borrows = true },
    SLICE_I32 = { name = "SLICE_I32",   z = "[i32]",     r = "&[i32]",    slice = true, borrows = true },
    SLICE_MUT = { name = "SLICE_MUT",   z = "[mut i32]", r = "&mut [i32]", slice = true, mutable = true, borrows = true },
    BOX_SLICE = { name = "BOX_SLICE",   z = "Box<[i32]>", r = "Box<&[i32]>", box = true, borrows = true },
    OPT_SLICE = { name = "OPT_SLICE",   z = "Option<[i32]>", r = "Option<&[i32]>", borrows = true },
    LINK      = { name = "LINK",        z = "Link",      r = "Link<'a>",  link = true, borrows = true },
}

-- Program state: locals in scope (with type and whether they are mutable), helper functions, and the
-- set of feature tags this program contains.
local P

local function tag(t) P.tags[t] = true end

-- Mark a program as carrying a *known* memory-safety hole (`--mode calibration`, the append in `mix`,
-- and the random hole builders). The driver reports such a program's fault under the hole's row and
-- never files it as a finding, so a run can tell "the known holes still fault" from "something new
-- broke"; the marker is `// fuzz: calibration <id>` on its own line.
local function calibration(id)
    P.calibration = P.calibration or {}
    P.calibration[id] = true
end

-- How many of the values the program created own something (`owns` in TYPES), and how many there are.
-- The manifest carries both, which is how the share item 2 asks for is measured rather than asserted.
local function owns_count()
    -- A template program is printed from its own `P`, which has no value list: the manifest still needs
    -- the two fields, so that counts as a program with nothing to count rather than crashing the run.
    if not P or not P.locals then return 0 end
    local n = 0
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty] and TYPES[l.ty].owns then n = n + 1 end
    end
    return n
end
local function fresh(prefix) P.n = P.n + 1; return string.format("%s%d", prefix, P.n) end
local function int_literal()
    local v = rnd(20)
    if chance(20) then return "-" .. tostring(v) end
    return tostring(v)
end

-- Build an expression of the requested type where the grammar has one, or nil.
-- `strict` keeps off the names a live `&mut` points at even in boundary mode, for a builder that
-- reads several operands of one expression (a read of the place and a later read through the borrow).
local function expr_of(ty, depth, strict)
    depth = depth or 0
    if depth > 2 then return nil end
    if ty == "I32" then
        -- Names a live `&mut` points at, unless this program is in boundary mode: reading one would
        -- make Zoril reject the program for aliasing, and a rejected program says nothing about the
        -- shapes the differential oracle is looking for.
        local off_limits = {}
        if strict or not chance(boundary_pct) then
            for _, l in ipairs(P.locals) do
                if l.ty == "REFMUT_I32" and l.target then off_limits[l.target] = true end
            end
        end
        local choices = { "int" }
        local places = {}
        for _, l in ipairs(P.locals) do
            if TYPES[l.ty].int and not off_limits[l.name] then table.insert(places, l) end
        end
        if #places > 0 then table.insert(choices, "local") end
        local refs = {}
        for _, l in ipairs(P.locals) do
            if l.ty == "REF_I32" or l.ty == "REFMUT_I32" then table.insert(refs, l) end
        end
        if #refs > 0 then table.insert(choices, "deref") end
        if P.holder_local then table.insert(choices, "holder_read") end
        if P.tup_local then table.insert(choices, "tup_elem") end
        if P.array_local then table.insert(choices, "index_read") end
        local c = choices[rnd(#choices)]
        if c == "int" then return { k = "Int", v = int_literal(), ty = "I32" } end
        if c == "local" then
            local l = places[rnd(#places)]
            return { k = "Local", name = l.name, ty = "I32" }
        end
        if c == "deref" then
            local l = refs[rnd(#refs)]
            return { k = "Deref", e = { k = "Local", name = l.name, ty = l.ty }, ty = "I32" }
        end
        if c == "holder_read" then
            local h = P.holder_local
            tag("read-through-struct-ref-field")
            return { k = "HolderRead", name = h, ty = "I32" }
        end
        if c == "index_read" then
            tag("index-read")
            return { k = "IndexRead", name = P.array_local, idx = 1, ty = "I32" }
        end
        local t = P.tup_local
        tag("read-through-tuple-ref")
        return { k = "TupElem", name = t, index = 1, ty = "I32" }
    end
    if ty == "RAW" then return { k = "RawNull", ty = "RAW" } end
    return nil
end

-- A place of the requested type: a local, or a dereference of a reference local.
local function place_of(ty)
    local candidates = {}
    for _, l in ipairs(P.locals) do
        if l.ty == ty then table.insert(candidates, l) end
    end
    if #candidates > 0 then
        local l = candidates[rnd(#candidates)]
        return { k = "Local", name = l.name, ty = ty, mutable = l.mutable }
    end
    if TYPES[ty].int then
        for _, l in ipairs(P.locals) do
            if l.ty == "REFMUT_I32" then
                tag("write-through-mut-ref")
                return { k = "DerefMutLocal", name = l.name, ty = ty }
            end
        end
    end
    return nil
end

-- Statement builders. Each returns a node; the printers walk them.
-- Capability mismatches: a value of one pointer class where another is expected. Zoril accepted these
-- until the conversion audit found them by hand - the generator never produced one -
-- and that is the rule this table exists to satisfy: a hole a review finds leaves a generator rule
-- behind, so the next one in its class is found mechanically. The Rust twin is written so `rustc`
-- refuses the same construct for the same reason (a type error, not a lifetime one), which is what
-- makes the pair a calibration rather than noise.
--
-- The `box-shared-for-mut` shape (`Box<i32>` where `BoxMut<i32>` is expected) is deliberately absent:
-- Rust's `Box` is always mutable, so there is no twin to compare against, and its Zoril half is pinned
-- by `tests/error_reporting/err_shared_box_for_mut_param.zrl` instead.
local CAP_MISMATCHES = {
    -- family                    the slot's type    the value's type      ... that borrows nothing
    { t = "ref-shared-for-mut", want = "&mut i32", z = "&x",         r = "&x" },
    { t = "raw-shared-for-mut", want = "*mut i32", z = "&x as *i32", r = "&x as *const i32", z_free = "0 as *i32", r_free = "0 as *const i32" },
    { t = "ref-for-box",        want = "Box<i32>", z = "&x",         r = "&x" },
    { t = "box-for-ref",        want = "&i32",     z = "box 1",      r = "Box::new(1)", z_free = "box 1", r_free = "Box::new(1)" },
}
local CAP_POSITIONS = { "as-argument", "as-let", "as-return", "as-struct-field" }

-- The shapes a program can carry: every (family, position) that the Rust twin can refuse for the
-- capability alone. A `return` of a value that borrows a local is refused by rustc for the lifetime
-- too, which the differential oracle reads as a different class, so a borrowing family is only
-- returned in its borrow-free spelling.
local function cap_shapes()
    local shapes = {}
    for _, fam in ipairs(CAP_MISMATCHES) do
        for _, pos in ipairs(CAP_POSITIONS) do
            if pos ~= "as-return" or fam.z_free then
                table.insert(shapes, { fam = fam, pos = pos, free = (pos == "as-return") })
            end
        end
    end
    return shapes
end
local STMT = {}

STMT.let_int = function()
    local v = expr_of("I32")
    if not v then return nil end
    local name = fresh("a")
    table.insert(P.locals, { name = name, ty = "I32", mutable = false })
    return { k = "LetInt", name = name, e = v }
end

STMT.let_mut_int = function()
    local v = expr_of("I32")
    if not v then return nil end
    local name = fresh("m")
    table.insert(P.locals, { name = name, ty = "I32", mutable = true })
    local s = { k = "LetMutInt", name = name, e = v }
    P.ints_mutable = true
    return s
end

STMT.assign_through_mut_ref = function()
    local v = expr_of("I32")
    if not v then return nil end
    tag("write-through-mut-ref")
    local dst = nil
    for _, l in ipairs(P.locals) do
        if l.ty == "REFMUT_I32" then
            dst = { k = "DerefMutLocal", name = l.name, ty = "I32" }
            break
        end
    end
    if not dst then
        -- None yet: this statement makes its own mutable borrow, which is what it writes through.
        local b = STMT.let_mut_borrow()
        if not b then return nil end
        for _, l in ipairs(P.locals) do
            if l.ty == "REFMUT_I32" then
                dst = { k = "DerefMutLocal", name = l.name, ty = "I32" }
            end
        end
        if not dst then return nil end
        return { k = "AssignThroughRefAfterBorrow", borrow = b, dst = dst, e = v }
    end
    tag("write-through-mut-ref")
    return { k = "AssignThroughRef", dst = dst, e = v }
end

STMT.let_borrow = function()
    local target = nil
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty].int then target = l break end
    end
    if not target then return nil end
    local name = fresh("r")
    table.insert(P.locals, { name = name, ty = "REF_I32", mutable = false })
    tag("reference-to-local")
    return { k = "LetBorrow", name = name, target = target.name }
end

STMT.let_mut_borrow = function()
    for _, l in ipairs(P.locals) do
        if l.ty == "REFMUT_I32" then return nil end   -- one live mutable borrow per program
    end
    local target = nil
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty].int and l.mutable then target = l break end
    end
    if not target then return nil end
    local name = fresh("rm")
    table.insert(P.locals, { name = name, ty = "REFMUT_I32", mutable = false, target = target.name })
    tag("mutable-reference-to-local")
    return { k = "LetMutBorrow", name = name, target = target.name }
end

STMT.let_box = function()
    local v = expr_of("I32")
    if not v then return nil end
    local name = fresh("b")
    table.insert(P.locals, { name = name, ty = "BOX_I32", mutable = false })
    tag("owned-box")
    return { k = "LetBox", name = name, e = v }
end

STMT.let_arena = function()
    local a = fresh("a")
    local w = fresh("w")
    table.insert(P.locals, { name = a, ty = "ARENA", mutable = false })
    table.insert(P.locals, { name = w, ty = "VEC_ARENA", mutable = false })
    P.needs_arena = true
    tag("arena-value")
    tag("collection-tied-to-an-arena")
    tag("arena-push")
    tag("arena-slice")
    return { k = "LetArena", arena = a, vec = w }
end

STMT.let_opt_ref = function()
    P.uses_option = true
    local target = nil
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty].int then target = l break end
    end
    if not target then return nil end
    local name = fresh("o")
    table.insert(P.locals, { name = name, ty = "OPT_REF", mutable = false })
    tag("option-of-reference")
    if chance(25) then
        return { k = "LetOptRef", name = name, none = true }
    end
    return { k = "LetOptRef", name = name, target = target.name }
end

STMT.let_holder = function()
    local target = nil
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty].int then target = l break end
    end
    if not target then return nil end
    P.has_holders = true
    local name = fresh("h")
    tag("reference-in-struct-field")
    tag("read-through-struct-ref-field")
    local v = expr_of("I32") or { k = "Int", v = "1", ty = "I32" }
    table.insert(P.locals, { name = name, ty = "HOLDER", mutable = false })
    P.holder_local = name
    return { k = "LetHolder", name = name, target = target.name, e = v }
end

-- A struct held by a `Box`, read and written through `&Box<S>` and `&mut Box<S>`. A field access through
-- the reference has to reach the boxed struct, not the stack slot that holds the box: the expected-value
-- oracle catches the wrong read (exit 93) and the crash and value oracles the out-of-bounds write.
STMT.box_point = function()
    local a = expr_of("I32", 0, true) or { k = "Int", v = "20", ty = "I32" }
    local b = expr_of("I32", 0, true) or { k = "Int", v = "22", ty = "I32" }
    local c = expr_of("I32", 0, true) or { k = "Int", v = "5", ty = "I32" }
    P.needs_boxpt = true
    tag("box-field-through-reference")
    tag("owned-box")
    return { k = "BoxPoint", name = fresh("bp"), a = a, b = b, c = c }
end

STMT.let_tuple = function()
    local target = nil
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty].int then target = l break end
    end
    if not target then return nil end
    P.has_tup = true
    local name = fresh("t")
    local v = expr_of("I32") or { k = "Int", v = "2", ty = "I32" }
    table.insert(P.locals, { name = name, ty = "TUP2", mutable = false })
    P.tup_local = name
    tag("reference-in-tuple")
    tag("read-through-tuple-ref")
    return { k = "LetTuple", name = name, target = target.name, e = v }
end

STMT.read_borrow = function()
    local refs = {}
    for _, l in ipairs(P.locals) do
        if l.ty == "REF_I32" or l.ty == "REFMUT_I32" then table.insert(refs, l) end
    end
    if #refs == 0 then return nil end
    local l = refs[rnd(#refs)]
    tag("dereference")
    return { k = "ReadBorrow", name = l.name, e = { k = "Deref", e = { k = "Local", name = l.name, ty = l.ty }, ty = "I32" } }
end

STMT.call_forward = function()
    if #P.helpers == 0 then return nil end
    local h = P.helpers[rnd(#P.helpers)]
    local candidates = {}
    for _, l in ipairs(P.locals) do
        local t = TYPES[l.ty]
        -- The loose-operand rule: any address-like or owned value in scope may be handed to an
        -- address-taking helper. That is a general rule - it is how a borrow/box/raw confusion can
        -- arise from composition rather than from a template aimed at one - and it is why the
        -- oracle, not the generator, is what decides whether the call was sound.
        -- Address-like values only: `Option<&T>`, a struct holding a reference and a tuple are
        -- aggregates, and handing one to an address-taking helper is a plain type error rather than
        -- the boundary this rule is for.
        if t.ref or t.box or t.raw then table.insert(candidates, l) end
    end
    if #candidates == 0 then return nil end
    if chance(100 - boundary_pct) then
        local exact = {}
        for _, l in ipairs(candidates) do
            if l.ty == "REF_I32" or l.ty == "REFMUT_I32" then table.insert(exact, l) end
        end
        if #exact > 0 then candidates = exact end
    else
        tag("address-like-value-passed-loosely")
    end
    local a = candidates[rnd(#candidates)]
    tag("call-forwarding-a-reference")
    return { k = "CallStmt", helper = h, arg = { k = "Local", name = a.name, ty = a.ty } }
end

STMT.block_borrow = function()
    local target = nil
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty].int then target = l break end
    end
    if not target then return nil end
    local name = fresh("q")
    local escape = chance(boundary_pct)
    if escape then
        -- The boundary composition: the referent lives in the block, the binding that keeps it does
        -- not. A correct checker rejects it; a broken one lets the outer binding dangle.
        tag("borrow-of-an-inner-local-kept-outside")
        table.insert(P.locals, { name = name, ty = "REF_I32", mutable = true })
        return { k = "BlockEscape", name = name, target = target.name }
    end
    tag("borrow-inside-a-block")
    return { k = "BlockInner", target = target.name }
end

STMT.while_borrow = function()
    local target = nil
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty].int then target = l break end
    end
    if not target then return nil end
    local name = fresh("w")
    table.insert(P.locals, { name = name, ty = "REF_I32", mutable = false })
    tag("borrow-inside-a-loop")
    return { k = "WhileBorrow", target = target.name, name = name, rounds = 1 + rnd(3) }
end

STMT.match_opt_ref = function()
    local o = nil
    for _, l in ipairs(P.locals) do
        if l.ty == "OPT_REF" then o = l break end
    end
    if not o then return nil end
    local name = fresh("mv")
    table.insert(P.locals, { name = name, ty = "I32", mutable = false })
    tag("match-binding-through-reference")
    return { k = "MatchOpt", src = o.name, name = name }
end

STMT.if_let_opt_ref = function()
    local o = nil
    for _, l in ipairs(P.locals) do
        if l.ty == "OPT_REF" then o = l break end
    end
    if not o then return nil end
    tag("if-let-binding-through-reference")
    return { k = "IfLetOpt", src = o.name }
end

STMT.closure_capture_ref = function()
    local name = fresh("g")
    table.insert(P.locals, { name = name, ty = "CLOSURE" })
    if chance(boundary_pct) then
        -- A capturing closure assigned to an outer function-pointer binding whose captured reference
        -- points at a local of the block that ends before the call (probe 173's shape: the fix there
        -- was silent, so only the differential oracle sees it).
        tag("closure-capturing-a-reference")
        tag("closure-assigned-out-of-its-block")
        return { k = "ClosureEscape", name = name }
    end
    tag("closure-capturing-a-reference")
    return { k = "ClosureInner", name = name }
end

STMT.drop_struct = function()
    local target = nil
    for _, l in ipairs(P.locals) do
        if TYPES[l.ty].int then target = l break end
    end
    if not target then return nil end
    P.drop_seen = true
    local name = fresh("dh")
    table.insert(P.locals, { name = name, ty = "DROPOWN", mutable = false })
    tag("drop-type-holding-a-reference")
    tag("drop-count")
    return { k = "DropStruct", name = name, target = target.name }
end

STMT.raw_in_container = function()
    local name = fresh("rp")
    table.insert(P.locals, { name = name, ty = "RAW", mutable = false })
    tag("raw-pointer-value-in-a-struct")
    return { k = "RawInStruct", name = name }
end

--- The new language dimensions, as *valid* programs ------------------------------------------------
-- These fill the routes the calibration stream later proves are covered. They are ordinary builders
-- (sampled by the grammar) rather than templates: a fixed program would exercise one spelling of a
-- route, and the point is to compose it with the rest of the tree.

STMT.let_array = function()
    local name = fresh("ar")
    table.insert(P.locals, { name = name, ty = "ARR_I32", mutable = false })
    P.array_local = name
    tag("array-value")
    tag("index-read")
    return { k = "LetArray", name = name }
end

STMT.array_index_borrow = function()
    if not P.array_local then return nil end
    tag("index-borrow")
    return { k = "Raw", z = {
        "{",
        "    let p: &i32 = &" .. P.array_local .. "[1];",
        "    if *p != 8 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let p: &i32 = &" .. P.array_local .. "[1];",
        "    if *p != 8 { std::process::exit(92); }",
        "}",
    } }
end

STMT.index_compound_assign = function()
    tag("index-compound-assign")
    return { k = "Raw", z = {
        "{",
        "    let mut ar: [i32; 4] = [1, 2, 3, 4];",
        "    ar[0] += 5;",
        "    if ar[0] != 6 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let mut ar: [i32; 4] = [1, 2, 3, 4];",
        "    ar[0] += 5;",
        "    if ar[0] != 6 { std::process::exit(92); }",
        "}",
    } }
end

STMT.array_repeat = function()
    tag("array-repeat")
    return { k = "Raw", z = {
        "{",
        "    let rep: [i32; 65] = [3; 65];",
        "    if rep[64] != 3 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let rep: [i32; 65] = [3; 65];",
        "    if rep[64] != 3 { std::process::exit(92); }",
        "}",
    } }
end

STMT.slice_value = function()
    P.needs_arena = true
    tag("slice-value")
    tag("arena-push")
    tag("arena-slice")
    return { k = "Raw", z = {
        "{",
        "    let mut a = Arena.new(65536 as u64).unwrap();",
        "    let mut v = Vec::<u64>.new_in(&a);",
        "    v.push(7 as u64);",
        "    let s: [u64] = v.as_slice();",
        "    if s[0] != 7 as u64 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let mut a = Arena::new(65536).unwrap();",
        "    let mut v = ArenaVec::<u64>::new_in(&a);",
        "    v.push(7);",
        "    let s: &[u64] = v.as_slice();",
        "    if s[0] != 7 { std::process::exit(92); }",
        "}",
    } }
end

STMT.boxed_slice = function()
    P.needs_arena = true
    tag("boxed-arena-slice")
    tag("arena-push")
    tag("arena-slice")
    return { k = "Raw", z = {
        "{",
        "    let mut a = Arena.new(65536 as u64).unwrap();",
        "    let mut v = Vec::<u64>.new_in(&a);",
        "    v.push(7 as u64);",
        "    let b: Box<[u64]> = box v.as_slice();",
        "    if (*b)[0] != 7 as u64 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let mut a = Arena::new(65536).unwrap();",
        "    let mut v = ArenaVec::<u64>::new_in(&a);",
        "    v.push(7);",
        "    let b: Box<&[u64]> = Box::new(v.as_slice());",
        "    if (*b)[0] != 7 { std::process::exit(92); }",
        "}",
    } }
end

STMT.arena_reset = function()
    P.needs_arena = true
    tag("arena-reset")
    tag("arena-push")
    return { k = "Raw", z = {
        "{",
        "    let mut a = Arena.new(65536 as u64).unwrap();",
        "    let mut v = Vec::<u64>.new_in(&a);",
        "    v.push(7 as u64);",
        "    a.reset();",
        "}",
    }, r = {
        "{",
        "    let mut a = Arena::new(65536).unwrap();",
        "    let mut v = ArenaVec::<u64>::new_in(&a);",
        "    v.push(7);",
        "    a.reset();",
        "}",
    } }
end

STMT.arena_mark_reset_to = function()
    P.needs_arena = true
    tag("arena-mark")
    tag("arena-reset-to")
    tag("arena-push")
    tag("arena-slice")
    -- A pre-mark container that is read and then untouched across `reset_to`: Zoril accepts it, and
    -- the Rust shim cannot model `reset_to` without rejecting every such program, so the differential
    -- oracle is told to skip this one (`// fuzz: no-rustc-diff`).
    return { k = "Raw", no_rustc = true, z = {
        "{",
        "    let mut a = Arena.new(65536 as u64).unwrap();",
        "    let mut v = Vec::<u64>.new_in(&a);",
        "    v.push(7 as u64);",
        "    let s: [u64] = v.as_slice();",
        "    if s[0] != 7 as u64 { return 92; }",
        "    let m = a.mark();",
        "    a.reset_to(m);",
        "}",
    }, r = {
        "{",
        "    let mut a = Arena::new(65536).unwrap();",
        "    let mut v = ArenaVec::<u64>::new_in(&a);",
        "    v.push(7);",
        "    let s: &[u64] = v.as_slice();",
        "    if s[0] != 7 { std::process::exit(92); }",
        "    let m = a.mark();",
        "    a.reset_to(m);",
        "}",
    } }
end

STMT.branch_conditional_borrow = function()
    tag("branch-conditional-borrow")
    return { k = "Raw", z = {
        "{",
        "    let x: i32 = 3;",
        "    let y: i32 = 5;",
        "    let mut r: &i32 = &x;",
        "    let cond = x > 0;",
        "    if cond { r = &y; }",
        "    if *r != 5 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let x: i32 = 3;",
        "    let y: i32 = 5;",
        "    let mut r: &i32 = &x;",
        "    let cond = x > 0;",
        "    if cond { r = &y; }",
        "    if *r != 5 { std::process::exit(92); }",
        "}",
    } }
end

STMT.closure_returns_capture = function()
    P.needs_arena = true
    tag("closure-returns-capture")
    tag("arena-slice")
    return { k = "Raw", z = {
        "{",
        "    let mut a = Arena.new(65536 as u64).unwrap();",
        "    let mut v = Vec::<u64>.new_in(&a);",
        "    v.push(7 as u64);",
        "    let s: [u64] = v.as_slice();",
        "    let f = || -> [u64] { return s; };",
        "    let r: [u64] = f();",
        "    if r[0] != 7 as u64 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let mut a = Arena::new(65536).unwrap();",
        "    let mut v = ArenaVec::<u64>::new_in(&a);",
        "    v.push(7);",
        "    let s: &[u64] = v.as_slice();",
        "    let f = || -> &[u64] { return s; };",
        "    let r: &[u64] = f();",
        "    if r[0] != 7 { std::process::exit(92); }",
        "}",
    } }
end

STMT.function_pointer = function()
    P.needs_bump_i32 = true
    tag("function-pointer-call")
    return { k = "Raw", z = {
        "{",
        "    let f: fn(&mut i32) = bump_i32;",
        "    let mut z: i32 = 1;",
        "    f(&mut z);",
        "    if z != 2 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let f: fn(&mut i32) = bump_i32;",
        "    let mut z: i32 = 1;",
        "    f(&mut z);",
        "    if z != 2 { std::process::exit(92); }",
        "}",
    } }
end

STMT.destructure_plain = function()
    tag("destructure-owning-tuple")
    return { k = "Raw", z = {
        "{",
        "    let pair: (i32, i32) = (7, 2);",
        "    let (p, _) = pair;",
        "    if p != 7 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let pair: (i32, i32) = (7, 2);",
        "    let (p, _) = pair;",
        "    if p != 7 { std::process::exit(92); }",
        "}",
    } }
end

STMT.match_ref_enum = function()
    P.needs_enum = true
    tag("match-borrowed-enum-payload")
    return { k = "Raw", z = {
        "{",
        "    let e = E.Some(7);",
        "    match &e {",
        "        E.Some(x) => { if *x != 7 { return 92; } },",
        "        E.None => {},",
        "    }",
        "}",
    }, r = {
        "{",
        "    let e = E::Some(7);",
        "    match &e {",
        "        E::Some(x) => { if *x != 7 { std::process::exit(92); } },",
        "        E::None => {},",
        "    }",
        "}",
    } }
end

STMT.ref_helper_forms = function()
    P.needs_same_ref = true
    P.needs_choose_ref = true
    tag("reference-returning-helper")
    return { k = "Raw", z = {
        "{",
        "    let z: i32 = 3;",
        "    let a: &i32 = same_ref(&z);",
        "    let b: &i32 = choose_ref(&z);",
        "    if *a + *b != 6 { return 92; }",
        "}",
    }, r = {
        "{",
        "    let z: i32 = 3;",
        "    let a: &i32 = same_ref(&z);",
        "    let b: &i32 = choose_ref(&z);",
        "    if *a + *b != 6 { std::process::exit(92); }",
        "}",
    } }
end

-- One statement per (family, position), for the mismatch stream only - it is deliberately *not* in
-- `BUILDERS`, because a program that carries a mismatch never runs: the crash oracle sees none of it,
-- and every other feature generated beside it goes untested once the compiler stops there. The
-- declaration a shape needs goes into `P.cap_decls` and is printed at the top level, where both
-- languages allow it (`x` is `main`'s local, so anything mentioning it stays inside `main` and only the
-- declaration moves out).
STMT.capability_mismatch = function(fam, pos, free)
    local n = fresh("cm")
    tag("capability-mismatch")
    tag("capability-mismatch-" .. fam.t)
    tag("capability-mismatch-" .. pos)
    P.cap_decls = P.cap_decls or {}
    if pos == "as-argument" then
        table.insert(P.cap_decls, { k = "fn", name = n .. "_f", want = fam.want })
    elseif pos == "as-return" then
        table.insert(P.cap_decls, { k = "fn", name = n .. "_g", want = fam.want, ret = true })
    elseif pos == "as-struct-field" then
        table.insert(P.cap_decls, { k = "struct", name = "CapStruct" .. n, want = fam.want })
    end
    return { k = "CapMismatch", n = n, fam = fam, pos = pos, free = free }
end

local BUILDERS = {
    { "let_int", STMT.let_int, 16 },
    { "let_mut_int", STMT.let_mut_int, 8 },
    { "let_borrow", STMT.let_borrow, 14 },
    { "let_mut_borrow", STMT.let_mut_borrow, 6 },
    { "read_borrow", STMT.read_borrow, 10 },
    { "let_box", STMT.let_box, 8 },
    { "let_opt_ref", STMT.let_opt_ref, 10 },
    { "let_holder", STMT.let_holder, 5 },
    { "let_tuple", STMT.let_tuple, 5 },
    { "box_point", STMT.box_point, 4 },
    { "call_forward", STMT.call_forward, 10 },
    { "block_borrow", STMT.block_borrow, 7 },
    { "while_borrow", STMT.while_borrow, 5 },
    { "match_opt_ref", STMT.match_opt_ref, 4 },
    { "if_let_opt_ref", STMT.if_let_opt_ref, 9 },
    { "closure_capture_ref", STMT.closure_capture_ref, 5 },
    { "drop_struct", STMT.drop_struct, 3 },
    { "raw_in_container", STMT.raw_in_container, 3 },
    { "let_arena", STMT.let_arena, 9 },
    { "assign_through_mut_ref", STMT.assign_through_mut_ref, 4 },
    -- the new valid dimensions
    { "let_array", STMT.let_array, 8 },
    { "array_index_borrow", STMT.array_index_borrow, 5 },
    { "index_compound_assign", STMT.index_compound_assign, 5 },
    { "array_repeat", STMT.array_repeat, 4 },
    { "slice_value", STMT.slice_value, 5 },
    { "boxed_slice", STMT.boxed_slice, 4 },
    { "arena_reset", STMT.arena_reset, 4 },
    { "arena_mark_reset_to", STMT.arena_mark_reset_to, 4 },
    { "branch_conditional_borrow", STMT.branch_conditional_borrow, 5 },
    { "closure_returns_capture", STMT.closure_returns_capture, 4 },
    { "function_pointer", STMT.function_pointer, 4 },
    { "destructure_plain", STMT.destructure_plain, 4 },
    { "match_ref_enum", STMT.match_ref_enum, 4 },
    { "ref_helper_forms", STMT.ref_helper_forms, 4 },
}

--- The calibration stream: one program per known memory-safety hole -------------------------------
-- Every entry is a *self-contained* statement list, so it cannot be masked by another builder in the
-- same program, and it writes a canary / counts drops so the unmarked runtime oracle sees it. Each
-- entry's `setup` sets the declarations its program needs. `no_rustc` marks a shape whose Rust twin
-- cannot model the same rule (`reset_to`: Zoril deliberately accepts an untouched pre-mark container
-- across it, while the shim's `&mut Arena` borrow rejects every such program).
--
-- The tabular record of which oracle catches each one is `bench/fuzz/README.md`; the executable form
-- is `scripts/fuzz_calibrate.sh`. When a mechanism is fixed, its entry is expected to be *rejected*
-- by the compiler, and the calibration script reports that as a row to update.
local HOLES = {
    { id = "index_mut_borrow", tags = { "array-value", "index-mut-borrow", "immutable-index-write" },
      z = { "{", "    let arr: [i32; 2] = [7, 8];", "    let p: &mut i32 = &mut arr[0];", "    *p = 99;",
            "    if arr[0] != 7 { return 92; }", "}" },
      r = { "{", "    let arr: [i32; 2] = [7, 8];", "    let p: &mut i32 = &mut arr[0];", "    *p = 99;",
            "    if arr[0] != 7 { std::process::exit(92); }", "}" } },

    { id = "slice_index_mut_borrow", tags = { "slice-value", "index-mut-borrow", "immutable-index-write" },
      setup = function(p) p.needs_mutate_slice = true end,
      z = { "{", "    let arr: [i32; 2] = [7, 8];", "    mutate_slice(&arr);",
            "    if arr[0] != 7 { return 92; }", "}" },
      r = { "{", "    let arr: [i32; 2] = [7, 8];", "    mutate_slice(&arr);",
            "    if arr[0] != 7 { std::process::exit(92); }", "}" } },

    { id = "index_compound_assign", tags = { "array-value", "index-compound-assign", "immutable-index-write" },
      z = { "{", "    let arr: [i32; 2] = [7, 8];", "    arr[0] += 5;",
            "    if arr[0] != 7 { return 92; }", "}" },
      r = { "{", "    let arr: [i32; 2] = [7, 8];", "    arr[0] += 5;",
            "    if arr[0] != 7 { std::process::exit(92); }", "}" } },

    { id = "arena_index_reset", tags = { "arena-index-reset", "arena-reset", "index-borrow" },
      setup = function(p) p.needs_arena = true end,
      z = { "{",
            "    let mut a = Arena.new(65536 as u64).unwrap();",
            "    let mut v = Vec::<u64>.new_in(&a);",
            "    let mut i = 0 as u64;",
            "    while i < 64 { v.push(7 as u64); i = i + 1; }",
            "    let s: [u64] = v.as_slice();",
            "    let r: &u64 = &s[0];",
            "    a.reset();",
            "    let mut z = Vec::<u64>.new_in(&a);",
            "    let mut j = 0 as u64;",
            "    while j < 64 { z.push(99 as u64); j = j + 1; }",
            "    if *r != 7 as u64 { return 92; }",
            "}" },
      r = { "{",
            "    let mut a = Arena::new(65536).unwrap();",
            "    let mut v = ArenaVec::<u64>::new_in(&a);",
            "    let mut i: u64 = 0;",
            "    while i < 64 { v.push(7); i += 1; }",
            "    let s: &[u64] = v.as_slice();",
            "    let r: &u64 = &s[0];",
            "    a.reset();",
            "    let mut z = ArenaVec::<u64>::new_in(&a);",
            "    let mut j: u64 = 0;",
            "    while j < 64 { z.push(99); j += 1; }",
            "    if *r != 7 { std::process::exit(92); }",
            "}" } },

    { id = "arena_branch_reset", tags = { "branch-conditional-borrow", "arena-reset", "arena-slice" },
      setup = function(p) p.needs_arena = true; p.needs_optslice = true end,
      z = { "{",
            "    let mut a = Arena.new(65536 as u64).unwrap();",
            "    let mut v = Vec::<u64>.new_in(&a);",
            "    let mut i = 0 as u64;",
            "    while i < 64 { v.push(7 as u64); i = i + 1; }",
            "    let cond = v.len() > 0;",
            "    let mut opt: OptSlice = OptSlice.None;",
            "    if cond { opt = OptSlice.Some(v.as_slice()); }",
            "    a.reset();",
            "    let mut z = Vec::<u64>.new_in(&a);",
            "    let mut j = 0 as u64;",
            "    while j < 64 { z.push(99 as u64); j = j + 1; }",
            "    match opt {",
            "        OptSlice.Some(s) => { if s[0] != 7 as u64 { return 92; } },",
            "        OptSlice.None => {},",
            "    }",
            "}" },
      r = { "{",
            "    let mut a = Arena::new(65536).unwrap();",
            "    let mut v = ArenaVec::<u64>::new_in(&a);",
            "    let mut i: u64 = 0;",
            "    while i < 64 { v.push(7); i += 1; }",
            "    let cond = v.len() > 0;",
            "    let mut opt: OptSlice<'_> = OptSlice::None;",
            "    if cond { opt = OptSlice::Some(v.as_slice()); }",
            "    a.reset();",
            "    let mut z = ArenaVec::<u64>::new_in(&a);",
            "    let mut j: u64 = 0;",
            "    while j < 64 { z.push(99); j += 1; }",
            "    match opt {",
            "        OptSlice::Some(s) => { if s[0] != 7 { std::process::exit(92); } },",
            "        OptSlice::None => {},",
            "    }",
            "}" } },

    { id = "arena_loop_mark_reset_to", tags = { "loop-carried-container-growth", "arena-reset-to", "arena-mark" },
      no_rustc = true, setup = function(p) p.needs_arena = true end,
      z = { "{",
            "    let mut a = Arena.new(65536 as u64).unwrap();",
            "    let mut v = Vec::<u64>.new_in(&a);",
            "    v.push(7 as u64);",
            "    let m = a.mark();",
            "    let mut i = 0 as u64;",
            "    while i < 64 { v.push(7 as u64); i = i + 1; }",
            "    a.reset_to(m);",
            "    let mut z = Vec::<u64>.new_in(&a);",
            "    let mut j = 0 as u64;",
            "    while j < 64 { z.push(99 as u64); j = j + 1; }",
            "    if v.as_slice()[1] != 7 as u64 { return 92; }",
            "}" },
      r = { "{",
            "    let mut a = Arena::new(65536).unwrap();",
            "    let mut v = ArenaVec::<u64>::new_in(&a);",
            "    v.push(7);",
            "    let m = a.mark();",
            "    let mut i: u64 = 0;",
            "    while i < 64 { v.push(7); i += 1; }",
            "    a.reset_to(m);",
            "    let mut z = ArenaVec::<u64>::new_in(&a);",
            "    let mut j: u64 = 0;",
            "    while j < 64 { z.push(99); j += 1; }",
            "    if v.as_slice()[1] != 7 { std::process::exit(92); }",
            "}" } },

    { id = "branch_reassign_loop", tags = { "branch-conditional-borrow", "loop-carried-borrow" },
      z = { "{",
            "    let keep: i32 = 1;",
            "    let mut r: &i32 = &keep;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: i32 = 7 + i * 92;",
            "        if i != 0 {} else { r = &x; }",
            "        i = i + 1;",
            "    }",
            "    if *r != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let keep: i32 = 1;",
            "    let mut r: &i32 = &keep;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: i32 = 7 + i * 92;",
            "        if i != 0 {} else { r = &x; }",
            "        i += 1;",
            "    }",
            "    if *r != 7 { std::process::exit(92); }",
            "}" } },

    { id = "arena_box_slice_reset", tags = { "boxed-arena-slice", "arena-reset" },
      setup = function(p) p.needs_arena = true end,
      z = { "{",
            "    let mut a = Arena.new(65536 as u64).unwrap();",
            "    let mut v = Vec::<u64>.new_in(&a);",
            "    let mut i = 0 as u64;",
            "    while i < 64 { v.push(7 as u64); i = i + 1; }",
            "    let b: Box<[u64]> = box v.as_slice();",
            "    a.reset();",
            "    let mut z = Vec::<u64>.new_in(&a);",
            "    let mut j = 0 as u64;",
            "    while j < 64 { z.push(99 as u64); j = j + 1; }",
            "    if (*b)[0] != 7 as u64 { return 92; }",
            "}" },
      r = { "{",
            "    let mut a = Arena::new(65536).unwrap();",
            "    let mut v = ArenaVec::<u64>::new_in(&a);",
            "    let mut i: u64 = 0;",
            "    while i < 64 { v.push(7); i += 1; }",
            "    let b: Box<&[u64]> = Box::new(v.as_slice());",
            "    a.reset();",
            "    let mut z = ArenaVec::<u64>::new_in(&a);",
            "    let mut j: u64 = 0;",
            "    while j < 64 { z.push(99); j += 1; }",
            "    if (*b)[0] != 7 { std::process::exit(92); }",
            "}" } },

    { id = "arena_callptr_reset_to", tags = { "function-pointer-mut-container", "arena-reset-to", "arena-mark" },
      no_rustc = true, setup = function(p) p.needs_arena = true; p.needs_grow_vec = true end,
      z = { "{",
            "    let mut a = Arena.new(65536 as u64).unwrap();",
            "    let mut v = Vec::<u64>.new_in(&a);",
            "    let f: fn(&mut Vec<u64>) = grow_vec;",
            "    let vm = &mut v;",
            "    let m = a.mark();",
            "    f(vm);",
            "    a.reset_to(m);",
            "    let mut z = Vec::<u64>.new_in(&a);",
            "    let mut j = 0 as u64;",
            "    while j < 64 { z.push(99 as u64); j = j + 1; }",
            "    if v.as_slice()[0] != 7 as u64 { return 92; }",
            "}" },
      r = { "{",
            "    let mut a = Arena::new(65536).unwrap();",
            "    let mut v = ArenaVec::<u64>::new_in(&a);",
            "    let f: fn(&mut ArenaVec<u64>) = grow_vec;",
            "    let vm = &mut v;",
            "    let m = a.mark();",
            "    f(vm);",
            "    a.reset_to(m);",
            "    let mut z = ArenaVec::<u64>::new_in(&a);",
            "    let mut j: u64 = 0;",
            "    while j < 64 { z.push(99); j += 1; }",
            "    if v.as_slice()[0] != 7 { std::process::exit(92); }",
            "}" } },

    { id = "arena_closure_ret_reset", tags = { "closure-returns-capture", "arena-reset", "arena-slice" },
      setup = function(p) p.needs_arena = true end,
      z = { "{",
            "    let mut a = Arena.new(65536 as u64).unwrap();",
            "    let mut v = Vec::<u64>.new_in(&a);",
            "    let mut i = 0 as u64;",
            "    while i < 64 { v.push(7 as u64); i = i + 1; }",
            "    let r: [u64] = {",
            "        let s = v.as_slice();",
            "        let f = || -> [u64] { return s; };",
            "        f()",
            "    };",
            "    a.reset();",
            "    let mut z = Vec::<u64>.new_in(&a);",
            "    let mut j = 0 as u64;",
            "    while j < 64 { z.push(99 as u64); j = j + 1; }",
            "    if r[0] != 7 as u64 { return 92; }",
            "}" },
      r = { "{",
            "    let mut a = Arena::new(65536).unwrap();",
            "    let mut v = ArenaVec::<u64>::new_in(&a);",
            "    let mut i: u64 = 0;",
            "    while i < 64 { v.push(7); i += 1; }",
            "    let r: &[u64] = {",
            "        let s: &[u64] = v.as_slice();",
            "        let f = || -> &[u64] { return s; };",
            "        f()",
            "    };",
            "    a.reset();",
            "    let mut z = ArenaVec::<u64>::new_in(&a);",
            "    let mut j: u64 = 0;",
            "    while j < 64 { z.push(99); j += 1; }",
            "    if r[0] != 7 { std::process::exit(92); }",
            "}" } },

    { id = "enum_payload_block_escape", tags = { "match-borrowed-enum-payload", "loop-carried-borrow" },
      setup = function(p) p.needs_enum = true end,
      z = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let e = E.Some(7 + i * 92);",
            "        match &e {",
            "            E.Some(x) => { if i == 0 { out = x; } },",
            "            E.None => {},",
            "        }",
            "        i = i + 1;",
            "    }",
            "    if *out != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let e = E::Some(7 + i * 92);",
            "        match &e {",
            "            E::Some(x) => { if i == 0 { out = x; } },",
            "            E::None => {},",
            "        }",
            "        i += 1;",
            "    }",
            "    if *out != 7 { std::process::exit(92); }",
            "}" } },

    { id = "arena_repeat_reset", tags = { "array-repeat", "arena-reset" },
      setup = function(p) p.needs_arena = true end,
      z = { "{",
            "    let mut a = Arena.new(65536 as u64).unwrap();",
            "    let mut v = Vec::<u64>.new_in(&a);",
            "    let mut i = 0 as u64;",
            "    while i < 64 { v.push(7 as u64); i = i + 1; }",
            "    let arr: [[u64]; 65] = [v.as_slice(); 65];",
            "    a.reset();",
            "    let mut z = Vec::<u64>.new_in(&a);",
            "    let mut j = 0 as u64;",
            "    while j < 64 { z.push(99 as u64); j = j + 1; }",
            "    if arr[0][0] != 7 as u64 { return 92; }",
            "}" },
      r = { "{",
            "    let mut a = Arena::new(65536).unwrap();",
            "    let mut v = ArenaVec::<u64>::new_in(&a);",
            "    let mut i: u64 = 0;",
            "    while i < 64 { v.push(7); i += 1; }",
            "    let arr: [&[u64]; 65] = [v.as_slice(); 65];",
            "    a.reset();",
            "    let mut z = ArenaVec::<u64>::new_in(&a);",
            "    let mut j: u64 = 0;",
            "    while j < 64 { z.push(99); j += 1; }",
            "    if arr[0][0] != 7 { std::process::exit(92); }",
            "}" } },

    { id = "ret_storage_local_alias", tags = { "reference-returning-helper", "reference-returning-helper-alias", "loop-carried-borrow" },
      setup = function(p) p.needs_id_alias = true end,
      z = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: i32 = 7 + i * 92;",
            "        if i == 0 { out = id_alias(&x); }",
            "        i = i + 1;",
            "    }",
            "    if *out != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: i32 = 7 + i * 92;",
            "        if i == 0 { out = id_alias(&x); }",
            "        i += 1;",
            "    }",
            "    if *out != 7 { std::process::exit(92); }",
            "}" } },

    { id = "ret_storage_struct_wrap", tags = { "reference-returning-helper", "struct-wrapping-reference", "loop-carried-borrow" },
      setup = function(p) p.has_holders = true; p.needs_wrap = true end,
      z = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: i32 = 7 + i * 92;",
            "        if i == 0 { out = wrap(&x).r; }",
            "        i = i + 1;",
            "    }",
            "    if *out != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: i32 = 7 + i * 92;",
            "        if i == 0 { out = wrap(&x).r; }",
            "        i += 1;",
            "    }",
            "    if *out != 7 { std::process::exit(92); }",
            "}" } },

    { id = "same_type_borrow_loop_escape", tags = { "reference-returning-helper", "link-reference-helper", "loop-carried-borrow" },
      setup = function(p) p.needs_link = true end,
      z = { "{",
            "    let root = Link { v: 1, prev: OptLink.None };",
            "    let mut out: &Link = &root;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let inner = Link { v: 7 + i * 92, prev: OptLink.None };",
            "        let outer = Link { v: 2, prev: OptLink.Some(&inner) };",
            "        if i == 0 { out = get_prev(&outer); }",
            "        i = i + 1;",
            "    }",
            "    if out.v != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let root: Link<'_> = Link { v: 1, prev: None };",
            "    let mut out: &Link<'_> = &root;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let inner: Link<'_> = Link { v: 7 + i * 92, prev: None };",
            "        let outer: Link<'_> = Link { v: 2, prev: Some(&inner) };",
            "        if i == 0 { out = get_prev(&outer); }",
            "        i += 1;",
            "    }",
            "    if out.v != 7 { std::process::exit(92); }",
            "}" } },

    { id = "closure_capture_multiple_drop", tags = { "closure-captures-owning-value", "drop-count" },
      setup = function(p) p.needs_drop_counter = true end,
      z = { "{",
            "    let d = D { x: 7 };",
            "    CONSTRUCTED = CONSTRUCTED + 1;",
            "    let f = || -> i32 { return d.x; };",
            "    let a = f();",
            "    let b = f();",
            "}" },
      r = { "{",
            "    let d = D { x: 7 };",
            "    let f = || -> i32 { return d.x; };",
            "    let a = f();",
            "    let b = f();",
            "}" } },

    { id = "loop_closure_env_escape", tags = { "loop-closure-environment-escape", "loop-carried-borrow" },
      z = { "{",
            "    let zero: i32 = 0;",
            "    let mut f = || -> i32 { return zero; };",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: i32 = 7 + i * 92;",
            "        let cur = || -> i32 { return x; };",
            "        if i == 0 { f = cur; }",
            "        i = i + 1;",
            "    }",
            "    if f() != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let zero: i32 = 0;",
            "    let mut f = || -> i32 { return zero; };",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: i32 = 7 + i * 92;",
            "        let cur = || -> i32 { return x; };",
            "        if i == 0 { f = cur; }",
            "        i += 1;",
            "    }",
            "    if f() != 7 { std::process::exit(92); }",
            "}" } },

    { id = "let_destructure_double_drop", tags = { "destructure-owning-tuple", "drop-count" },
      setup = function(p) p.needs_drop_counter = true end,
      z = { "{",
            "    let pair: (D, i32) = (D { x: 7 }, 2);",
            "    CONSTRUCTED = CONSTRUCTED + 1;",
            "    let (d2, _) = pair;",
            "    if d2.x != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let pair: (D, i32) = (D { x: 7 }, 2);",
            "    let (d2, _) = pair;",
            "    if d2.x != 7 { std::process::exit(92); }",
            "}" } },

    { id = "premark_byvalue_reset_to", tags = { "by-value-container-move", "arena-reset-to", "arena-mark" },
      no_rustc = true, setup = function(p) p.needs_arena = true; p.needs_grow_by_value = true end,
      z = { "{",
            "    let mut a = Arena.new(65536 as u64).unwrap();",
            "    let v_pre = Vec::<u64>.new_in(&a);",
            "    let m = a.mark();",
            "    let w = grow_by_value(v_pre);",
            "    a.reset_to(m);",
            "    let mut z = Vec::<u64>.new_in(&a);",
            "    let mut j = 0 as u64;",
            "    while j < 64 { z.push(99 as u64); j = j + 1; }",
            "    if w.as_slice()[0] != 7 as u64 { return 92; }",
            "}" },
      r = { "{",
            "    let mut a = Arena::new(65536).unwrap();",
            "    let v_pre = ArenaVec::<u64>::new_in(&a);",
            "    let m = a.mark();",
            "    let w = grow_by_value(v_pre);",
            "    a.reset_to(m);",
            "    let mut z = ArenaVec::<u64>::new_in(&a);",
            "    let mut j: u64 = 0;",
            "    while j < 64 { z.push(99); j += 1; }",
            "    if w.as_slice()[0] != 7 { std::process::exit(92); }",
            "}" } },

    -- Two further routes of Unified Solution C, found by writing the fuzzer: `compute_ret_storage_zir`
    -- also misses `&arr[0]` and `&t.0` inside `&place` in `mark_ref_place`. Both poison the loop slot
    -- and read it through a reference to an array/tuple that lived in an earlier iteration.
    { id = "ret_storage_index_ref", tags = { "reference-returning-helper", "index-borrow", "loop-carried-borrow" },
      setup = function(p) p.needs_first_index = true end,
      z = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: [i32; 4] = [7 + i * 92, 0, 0, 0];",
            "        if i == 0 { out = first(&x); }",
            "        i = i + 1;",
            "    }",
            "    if *out != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: [i32; 4] = [7 + i * 92, 0, 0, 0];",
            "        if i == 0 { out = first(&x); }",
            "        i += 1;",
            "    }",
            "    if *out != 7 { std::process::exit(92); }",
            "}" } },

    { id = "ret_storage_tuple_field_ref", tags = { "reference-returning-helper", "reference-in-tuple", "loop-carried-borrow" },
      setup = function(p) p.needs_fst_tuple = true end,
      z = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: (i32, i32) = (7 + i * 92, 0);",
            "        if i == 0 { out = fst(&x); }",
            "        i = i + 1;",
            "    }",
            "    if *out != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let zero: i32 = 0;",
            "    let mut out: &i32 = &zero;",
            "    let mut i: i32 = 0;",
            "    while i < 2 {",
            "        let x: (i32, i32) = (7 + i * 92, 0);",
            "        if i == 0 { out = fst(&x); }",
            "        i += 1;",
            "    }",
            "    if *out != 7 { std::process::exit(92); }",
            "}" } },

    -- The two raw-pointer pattern holes. Their only observation is the fault itself, so they are
    -- emitted into the mismatch stream too (see below): an accepted one is a finding whatever else
    -- happens, and a segfault is the crash oracle's signal.
    { id = "raw_tuple_pattern_deref", tags = { "raw-pointer-pattern", "destructure-owning-tuple" },
      setup = function(p) p.needs_forge_tuple = true end,
      z = { "{", "    return forge_tuple(3735928559) as i32;", "}" },
      r = { "{", "    return forge_tuple(3735928559) as i32;", "}" } },

    { id = "raw_enum_pattern_deref", tags = { "raw-pointer-pattern", "match-borrowed-enum-payload" },
      setup = function(p) p.needs_forge_enum = true end,
      z = { "{", "    return forge_enum(3735928559) as i32;", "}" },
      r = { "{", "    return forge_enum(3735928559) as i32;", "}" } },

    -- An owning value moves into a tuple while a later operand uses a `&mut` taken from it: the move
    -- is where the value is written, so the later use is a use of a moved value (the Rust twin is
    -- E0505). The fixed state is `rejected`; accepted, `r.free()` releases the buffer the tuple owns.
    { id = "owning_move_before_borrow_use", tags = { "drop-while-borrowed", "buffer-view" },
      setup = function(p) p.needs_arena = true end,
      z = { "{",
            "    let mut om_v: Vec<i32> = Vec::<i32>.new();",
            "    om_v.push(7);",
            "    let om_r: &mut Vec<i32> = &mut om_v;",
            "    let mut om_t = (om_v, { om_r.free(); 0 });",
            "    om_t.0.push(8);",
            "    if *om_t.0.get(0).unwrap() != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let mut om_v: Vec<i32> = Vec::new();",
            "    om_v.push(7);",
            "    let om_r: &mut Vec<i32> = &mut om_v;",
            "    let mut om_t = (om_v, { om_r.clear(); 0 });",
            "    om_t.0.push(8);",
            "    if om_t.0[0] != 7 { std::process::exit(92); }",
            "}" } },

    -- A view into a local collection's buffer outlives the buffer. The generator always built
    -- arena collections and never a view that escapes the frame that owns the buffer, which is why
    -- 600,000 programs missed the safe-code hole review round 4 found (probes 278-283). The fixed
    -- state is `rejected`: the return/drop of a collection whose buffer the view reads is refused.
    { id = "local_buffer_view_drop", tags = { "local-buffer-return", "buffer-view", "drop-while-borrowed" },
      setup = function(p) p.needs_arena = true end,
      z = { "{",
            "    let mut hv_v: Vec<i32> = Vec::<i32>.new();",
            "    hv_v.push(7);",
            "    let hv_r: &i32 = hv_v.get(0).unwrap();",
            "    @drop(hv_v);",
            "    if *hv_r != 7 { return 92; }",
            "}" },
      r = { "{",
            "    let mut hv_v: Vec<i32> = Vec::new();",
            "    hv_v.push(7);",
            "    let hv_r: &i32 = &hv_v[0];",
            "    drop(hv_v);",
            "    if *hv_r != 7 { std::process::exit(92); }",
            "}" } },

    -- A call through a `fn` value stores a stack reference into the caller's struct: the direct
    -- call would be refused, the indirect one was not (probes 293-296). The fixed state is
    -- `rejected` - the coercion of a stashing callee, which is where the check lives. The Rust
    -- twin is refused too, by its fn-pointer coercion (a struct holding a reference needs the
    -- lifetime Zoril leaves implicit).
    { id = "fn_value_store_stack", tags = { "fn-value", "store-through-parameter", "stack-pointer-store" },
      setup = function(p) p.needs_fn_store = true end,
      z = { "{",
            "    let hx: i32 = 7;",
            "    let mut hh = FnStoreH { p: &hx };",
            "    let hf: fn(&mut FnStoreH, &i32) = fn_store_put;",
            "    let hn: i32 = 9;",
            "    hf(&mut hh, &hn);",
            "    if *hh.p != 9 { return 92; }",
            "}" },
      r = { "{",
            "    let hx: i32 = 7;",
            "    let mut hh = FnStoreH { p: &hx };",
            "    let hf: fn(&mut FnStoreH, &i32) = fn_store_put;",
            "    let hn: i32 = 9;",
            "    hf(&mut hh, &hn);",
            "    if *hh.p != 9 { std::process::exit(92); }",
            "}" } },
}

--- The same holes, as compositional builders --------------------------------------------------------
-- Every hole above is also an ordinary builder: the construct with random values, indices and loop
-- counts, sampled by the grammar and placed among whatever else the program generated. That is what
-- makes `--mode grammar` reach these routes at all - the fixed `z`/`r` pair on the HOLES entry stays
-- what `--mode calibration` emits, so the calibration table does not move, while the random stream
-- reaches the same shapes in contexts nobody wrote down. `calibration(id)` keeps each program out of
-- the search: the driver reports its fault under the hole's row instead of filing it as a finding.
local function hole(id)
    for _, h in ipairs(HOLES) do if h.id == id then return h end end
    error("gen.lua: unknown hole " .. tostring(id))
end

-- The driver controls this switch with an extra argv entry. Every hole snippet is self-contained (its
-- locals are fresh and nothing outside it refers to them), so guarding the whole snippet is enough:
-- with the switch off the hazardous read/write/drop does not execute at all, and a fault that remains
-- is unrelated to the hole. That is what lets the driver attribute a marked program's fault.
local function guard_hole(lines)
    local out = { "if hole_switch {" }
    for _, l in ipairs(lines) do table.insert(out, "    " .. l) end
    table.insert(out, "}")
    return out
end

local function hole_node(id, z, r)
    local h = hole(id)
    if h.setup then h.setup(P) end
    calibration(id)
    for _, t in ipairs(h.tags) do tag(t) end
    return { k = "Raw", z = guard_hole(z), r = guard_hole(r), no_rustc = h.no_rustc }
end

-- The canary's two spellings in the tail of a snippet.
local function exit92(lang) return (lang == "rust") and "std::process::exit(92)" or "return 92" end

local function hole_index_mut_borrow()
    local a, p = fresh("ha"), fresh("hp")
    local i = rnd(4) - 1
    local v = 7 + i
    local function body(lang)
        return { "{",
            "    let " .. a .. ": [i32; 4] = [7, 8, 9, 10];",
            "    let " .. p .. ": &mut i32 = &mut " .. a .. "[" .. i .. "];",
            "    *" .. p .. " = 99;",
            "    if " .. a .. "[" .. i .. "] != " .. v .. " { " .. exit92(lang) .. "; }",
            "}" }
    end
    return hole_node("index_mut_borrow", body("zoril"), body("rust"))
end

local function hole_slice_index_mut_borrow()
    local a = fresh("hs")
    local v = 7 + rnd(20)
    local function body(lang)
        return { "{",
            "    let " .. a .. ": [i32; 2] = [" .. v .. ", " .. (v + 1) .. "];",
            "    mutate_slice(&" .. a .. ");",
            "    if " .. a .. "[0] != " .. v .. " { " .. exit92(lang) .. "; }",
            "}" }
    end
    return hole_node("slice_index_mut_borrow", body("zoril"), body("rust"))
end

local function hole_index_compound_assign()
    local a = fresh("ha")
    local i = rnd(4) - 1
    local v, d = 7 + i, 1 + rnd(9)
    local function body(lang)
        return { "{",
            "    let " .. a .. ": [i32; 4] = [7, 8, 9, 10];",
            "    " .. a .. "[" .. i .. "] += " .. d .. ";",
            "    if " .. a .. "[" .. i .. "] != " .. (v + d) .. " { " .. exit92(lang) .. "; }",
            "}" }
    end
    return hole_node("index_compound_assign", body("zoril"), body("rust"))
end

local function hole_arena_index_reset()
    local a, v, s, r, z2 = fresh("ha"), fresh("hv"), fresh("hs"), fresh("hr"), fresh("hz")
    local i, j = fresh("hi"), fresh("hj")
    local val, n = 7 + rnd(20), 64
    local z = { "{",
        "    let mut " .. a .. " = Arena.new(65536 as u64).unwrap();",
        "    let mut " .. v .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. i .. " = 0 as u64;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(" .. val .. " as u64); " .. i .. " = " .. i .. " + 1; }",
        "    let " .. s .. ": [u64] = " .. v .. ".as_slice();",
        "    let " .. r .. ": &u64 = &" .. s .. "[0];",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. j .. " = 0 as u64;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99 as u64); " .. j .. " = " .. j .. " + 1; }",
        "    if *" .. r .. " != " .. val .. " as u64 { return 92; }",
        "}" }
    local rr = { "{",
        "    let mut " .. a .. " = Arena::new(65536).unwrap();",
        "    let mut " .. v .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. i .. ": u64 = 0;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(" .. val .. "); " .. i .. " += 1; }",
        "    let " .. s .. ": &[u64] = " .. v .. ".as_slice();",
        "    let " .. r .. ": &u64 = &" .. s .. "[0];",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. j .. ": u64 = 0;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99); " .. j .. " += 1; }",
        "    if *" .. r .. " != " .. val .. " { std::process::exit(92); }",
        "}" }
    return hole_node("arena_index_reset", z, rr)
end

local function hole_arena_branch_reset()
    local a, v, i, o, z2, j, s = fresh("ha"), fresh("hv"), fresh("hi"), fresh("ho"),
        fresh("hz"), fresh("hj"), fresh("hs")
    local val, n = 7 + rnd(20), 64
    local z = { "{",
        "    let mut " .. a .. " = Arena.new(65536 as u64).unwrap();",
        "    let mut " .. v .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. i .. " = 0 as u64;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(" .. val .. " as u64); " .. i .. " = " .. i .. " + 1; }",
        "    let cond = " .. v .. ".len() > 0;",
        "    let mut " .. o .. ": OptSlice = OptSlice.None;",
        "    if cond { " .. o .. " = OptSlice.Some(" .. v .. ".as_slice()); }",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. j .. " = 0 as u64;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99 as u64); " .. j .. " = " .. j .. " + 1; }",
        "    match " .. o .. " {",
        "        OptSlice.Some(" .. s .. ") => { if " .. s .. "[0] != " .. val .. " as u64 { return 92; } },",
        "        OptSlice.None => {},",
        "    }",
        "}" }
    local rr = { "{",
        "    let mut " .. a .. " = Arena::new(65536).unwrap();",
        "    let mut " .. v .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. i .. ": u64 = 0;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(" .. val .. "); " .. i .. " += 1; }",
        "    let cond = " .. v .. ".len() > 0;",
        "    let mut " .. o .. ": OptSlice<'_> = OptSlice::None;",
        "    if cond { " .. o .. " = OptSlice::Some(" .. v .. ".as_slice()); }",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. j .. ": u64 = 0;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99); " .. j .. " += 1; }",
        "    match " .. o .. " {",
        "        OptSlice::Some(" .. s .. ") => { if " .. s .. "[0] != " .. val .. " { std::process::exit(92); } },",
        "        OptSlice::None => {},",
        "    }",
        "}" }
    return hole_node("arena_branch_reset", z, rr)
end

local function hole_arena_loop_mark_reset_to()
    local a, v, m, i, z2, j = fresh("ha"), fresh("hv"), fresh("hm"), fresh("hi"), fresh("hz"), fresh("hj")
    local n = 64
    local z = { "{",
        "    let mut " .. a .. " = Arena.new(65536 as u64).unwrap();",
        "    let mut " .. v .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    " .. v .. ".push(7 as u64);",
        "    let " .. m .. " = " .. a .. ".mark();",
        "    let mut " .. i .. " = 0 as u64;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(7 as u64); " .. i .. " = " .. i .. " + 1; }",
        "    " .. a .. ".reset_to(" .. m .. ");",
        "    let mut " .. z2 .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. j .. " = 0 as u64;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99 as u64); " .. j .. " = " .. j .. " + 1; }",
        "    if " .. v .. ".as_slice()[1] != 7 as u64 { return 92; }",
        "}" }
    local rr = { "{",
        "    let mut " .. a .. " = Arena::new(65536).unwrap();",
        "    let mut " .. v .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    " .. v .. ".push(7);",
        "    let " .. m .. " = " .. a .. ".mark();",
        "    let mut " .. i .. ": u64 = 0;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(7); " .. i .. " += 1; }",
        "    " .. a .. ".reset_to(" .. m .. ");",
        "    let mut " .. z2 .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. j .. ": u64 = 0;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99); " .. j .. " += 1; }",
        "    if " .. v .. ".as_slice()[1] != 7 { std::process::exit(92); }",
        "}" }
    return hole_node("arena_loop_mark_reset_to", z, rr)
end

local function hole_branch_reassign_loop()
    local keep, r, i, x = fresh("hk"), fresh("hr"), fresh("hi"), fresh("hx")
    local rounds = 2 + rnd(2)
    local z = { "{",
        "    let " .. keep .. ": i32 = 1;",
        "    let mut " .. r .. ": &i32 = &" .. keep .. ";",
        "    let mut " .. i .. ": i32 = 0;",
        "    while " .. i .. " < " .. rounds .. " {",
        "        let " .. x .. ": i32 = 7 + " .. i .. " * 92;",
        "        if " .. i .. " != 0 {} else { " .. r .. " = &" .. x .. "; }",
        "        " .. i .. " = " .. i .. " + 1;",
        "    }",
        "    if *" .. r .. " != 7 { return 92; }",
        "}" }
    local rr = { "{",
        "    let " .. keep .. ": i32 = 1;",
        "    let mut " .. r .. ": &i32 = &" .. keep .. ";",
        "    let mut " .. i .. ": i32 = 0;",
        "    while " .. i .. " < " .. rounds .. " {",
        "        let " .. x .. ": i32 = 7 + " .. i .. " * 92;",
        "        if " .. i .. " != 0 {} else { " .. r .. " = &" .. x .. "; }",
        "        " .. i .. " += 1;",
        "    }",
        "    if *" .. r .. " != 7 { std::process::exit(92); }",
        "}" }
    return hole_node("branch_reassign_loop", z, rr)
end

local function hole_arena_box_slice_reset()
    local a, v, i, b, z2, j = fresh("ha"), fresh("hv"), fresh("hi"), fresh("hb"), fresh("hz"), fresh("hj")
    local n = 64
    local z = { "{",
        "    let mut " .. a .. " = Arena.new(65536 as u64).unwrap();",
        "    let mut " .. v .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. i .. " = 0 as u64;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(7 as u64); " .. i .. " = " .. i .. " + 1; }",
        "    let " .. b .. ": Box<[u64]> = box " .. v .. ".as_slice();",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. j .. " = 0 as u64;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99 as u64); " .. j .. " = " .. j .. " + 1; }",
        "    if (*" .. b .. ")[0] != 7 as u64 { return 92; }",
        "}" }
    local rr = { "{",
        "    let mut " .. a .. " = Arena::new(65536).unwrap();",
        "    let mut " .. v .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. i .. ": u64 = 0;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(7); " .. i .. " += 1; }",
        "    let " .. b .. ": Box<&[u64]> = Box::new(" .. v .. ".as_slice());",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. j .. ": u64 = 0;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99); " .. j .. " += 1; }",
        "    if (*" .. b .. ")[0] != 7 { std::process::exit(92); }",
        "}" }
    return hole_node("arena_box_slice_reset", z, rr)
end

local function hole_arena_callptr_reset_to()
    local a, v, f, vm, m, z2, j = fresh("ha"), fresh("hv"), fresh("hf"), fresh("hvm"),
        fresh("hm"), fresh("hz"), fresh("hj")
    local n = 64
    local z = { "{",
        "    let mut " .. a .. " = Arena.new(65536 as u64).unwrap();",
        "    let mut " .. v .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let " .. f .. ": fn(&mut Vec<u64>) = grow_vec;",
        "    let " .. vm .. " = &mut " .. v .. ";",
        "    let " .. m .. " = " .. a .. ".mark();",
        "    " .. f .. "(" .. vm .. ");",
        "    " .. a .. ".reset_to(" .. m .. ");",
        "    let mut " .. z2 .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. j .. " = 0 as u64;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99 as u64); " .. j .. " = " .. j .. " + 1; }",
        "    if " .. v .. ".as_slice()[0] != 7 as u64 { return 92; }",
        "}" }
    local rr = { "{",
        "    let mut " .. a .. " = Arena::new(65536).unwrap();",
        "    let mut " .. v .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let " .. f .. ": fn(&mut ArenaVec<u64>) = grow_vec;",
        "    let " .. vm .. " = &mut " .. v .. ";",
        "    let " .. m .. " = " .. a .. ".mark();",
        "    " .. f .. "(" .. vm .. ");",
        "    " .. a .. ".reset_to(" .. m .. ");",
        "    let mut " .. z2 .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. j .. ": u64 = 0;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99); " .. j .. " += 1; }",
        "    if " .. v .. ".as_slice()[0] != 7 { std::process::exit(92); }",
        "}" }
    return hole_node("arena_callptr_reset_to", z, rr)
end

local function hole_arena_closure_ret_reset()
    local a, v, i, r, z2, j = fresh("ha"), fresh("hv"), fresh("hi"), fresh("hr"), fresh("hz"), fresh("hj")
    local s, f = fresh("hs"), fresh("hf")
    local n = 64
    local z = { "{",
        "    let mut " .. a .. " = Arena.new(65536 as u64).unwrap();",
        "    let mut " .. v .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. i .. " = 0 as u64;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(7 as u64); " .. i .. " = " .. i .. " + 1; }",
        "    let " .. r .. ": [u64] = {",
        "        let " .. s .. " = " .. v .. ".as_slice();",
        "        let " .. f .. " = || -> [u64] { return " .. s .. "; };",
        "        " .. f .. "()",
        "    };",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. j .. " = 0 as u64;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99 as u64); " .. j .. " = " .. j .. " + 1; }",
        "    if " .. r .. "[0] != 7 as u64 { return 92; }",
        "}" }
    local rr = { "{",
        "    let mut " .. a .. " = Arena::new(65536).unwrap();",
        "    let mut " .. v .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. i .. ": u64 = 0;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(7); " .. i .. " += 1; }",
        "    let " .. r .. ": &[u64] = {",
        "        let " .. s .. ": &[u64] = " .. v .. ".as_slice();",
        "        let " .. f .. " = || -> &[u64] { return " .. s .. "; };",
        "        " .. f .. "()",
        "    };",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. j .. ": u64 = 0;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99); " .. j .. " += 1; }",
        "    if " .. r .. "[0] != 7 { std::process::exit(92); }",
        "}" }
    return hole_node("arena_closure_ret_reset", z, rr)
end

local function hole_enum_payload_block_escape()
    local zero, out, i, e = fresh("hz"), fresh("ho"), fresh("hi"), fresh("he")
    local x = fresh("hx")
    local rounds = 2 + rnd(2)
    local function body(lang)
        local some = (lang == "rust") and "Some" or "E.Some"
        local none = (lang == "rust") and "None" or "E.None"
        local inc = (lang == "rust") and " += 1;" or " = " .. i .. " + 1;"
        local exit = exit92(lang)
        return { "{",
            "    let " .. zero .. ": i32 = 0;",
            "    let mut " .. out .. ": &i32 = &" .. zero .. ";",
            "    let mut " .. i .. ": i32 = 0;",
            "    while " .. i .. " < " .. rounds .. " {",
            "        let " .. e .. " = " .. some .. "(7 + " .. i .. " * 92);",
            "        match &" .. e .. " {",
            "            " .. some .. "(" .. x .. ") => { if " .. i .. " == 0 { " .. out .. " = " .. x .. "; } },",
            "            " .. none .. " => {},",
            "        }",
            "        " .. i .. inc,
            "    }",
            "    if *" .. out .. " != 7 { " .. exit .. "; }",
            "}" }
    end
    return hole_node("enum_payload_block_escape", body("zoril"), body("rust"))
end

local function hole_arena_repeat_reset()
    local a, v, i, arr, z2, j = fresh("ha"), fresh("hv"), fresh("hi"), fresh("har"),
        fresh("hz"), fresh("hj")
    local n = 64
    local z = { "{",
        "    let mut " .. a .. " = Arena.new(65536 as u64).unwrap();",
        "    let mut " .. v .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. i .. " = 0 as u64;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(7 as u64); " .. i .. " = " .. i .. " + 1; }",
        "    let " .. arr .. ": [[u64]; 65] = [" .. v .. ".as_slice(); 65];",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. j .. " = 0 as u64;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99 as u64); " .. j .. " = " .. j .. " + 1; }",
        "    if " .. arr .. "[0][0] != 7 as u64 { return 92; }",
        "}" }
    local rr = { "{",
        "    let mut " .. a .. " = Arena::new(65536).unwrap();",
        "    let mut " .. v .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. i .. ": u64 = 0;",
        "    while " .. i .. " < " .. n .. " { " .. v .. ".push(7); " .. i .. " += 1; }",
        "    let " .. arr .. ": [&[u64]; 65] = [" .. v .. ".as_slice(); 65];",
        "    " .. a .. ".reset();",
        "    let mut " .. z2 .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. j .. ": u64 = 0;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99); " .. j .. " += 1; }",
        "    if " .. arr .. "[0][0] != 7 { std::process::exit(92); }",
        "}" }
    return hole_node("arena_repeat_reset", z, rr)
end

-- The three return-storage loop shapes share their frame; only the borrowed expression differs.
local function hole_ret_storage_local_alias()
    local zero, out, i, x = fresh("hz"), fresh("ho"), fresh("hi"), fresh("hx")
    local function body(lang)
        local exit = exit92(lang)
        local inc = (lang == "rust") and " += 1;" or " = " .. i .. " + 1;"
        return { "{",
            "    let " .. zero .. ": i32 = 0;",
            "    let mut " .. out .. ": &i32 = &" .. zero .. ";",
            "    let mut " .. i .. ": i32 = 0;",
            "    while " .. i .. " < 2 {",
            "        let " .. x .. ": i32 = 7 + " .. i .. " * 92;",
            "        if " .. i .. " == 0 { " .. out .. " = id_alias(&" .. x .. "); }",
            "        " .. i .. inc,
            "    }",
            "    if *" .. out .. " != 7 { " .. exit .. "; }",
            "}" }
    end
    return hole_node("ret_storage_local_alias", body("zoril"), body("rust"))
end

local function hole_ret_storage_struct_wrap()
    local zero, out, i, x = fresh("hz"), fresh("ho"), fresh("hi"), fresh("hx")
    local function body(lang)
        local exit = exit92(lang)
        local inc = (lang == "rust") and " += 1;" or " = " .. i .. " + 1;"
        return { "{",
            "    let " .. zero .. ": i32 = 0;",
            "    let mut " .. out .. ": &i32 = &" .. zero .. ";",
            "    let mut " .. i .. ": i32 = 0;",
            "    while " .. i .. " < 2 {",
            "        let " .. x .. ": i32 = 7 + " .. i .. " * 92;",
            "        if " .. i .. " == 0 { " .. out .. " = wrap(&" .. x .. ").r; }",
            "        " .. i .. inc,
            "    }",
            "    if *" .. out .. " != 7 { " .. exit .. "; }",
            "}" }
    end
    return hole_node("ret_storage_struct_wrap", body("zoril"), body("rust"))
end

local function hole_ret_storage_index_ref()
    local zero, out, i, x = fresh("hz"), fresh("ho"), fresh("hi"), fresh("hx")
    local function body(lang)
        local exit = exit92(lang)
        local inc = (lang == "rust") and " += 1;" or " = " .. i .. " + 1;"
        return { "{",
            "    let " .. zero .. ": i32 = 0;",
            "    let mut " .. out .. ": &i32 = &" .. zero .. ";",
            "    let mut " .. i .. ": i32 = 0;",
            "    while " .. i .. " < 2 {",
            "        let " .. x .. ": [i32; 4] = [7 + " .. i .. " * 92, 0, 0, 0];",
            "        if " .. i .. " == 0 { " .. out .. " = first(&" .. x .. "); }",
            "        " .. i .. inc,
            "    }",
            "    if *" .. out .. " != 7 { " .. exit .. "; }",
            "}" }
    end
    return hole_node("ret_storage_index_ref", body("zoril"), body("rust"))
end

local function hole_ret_storage_tuple_field_ref()
    local zero, out, i, x = fresh("hz"), fresh("ho"), fresh("hi"), fresh("hx")
    local function body(lang)
        local exit = exit92(lang)
        local inc = (lang == "rust") and " += 1;" or " = " .. i .. " + 1;"
        return { "{",
            "    let " .. zero .. ": i32 = 0;",
            "    let mut " .. out .. ": &i32 = &" .. zero .. ";",
            "    let mut " .. i .. ": i32 = 0;",
            "    while " .. i .. " < 2 {",
            "        let " .. x .. ": (i32, i32) = (7 + " .. i .. " * 92, 0);",
            "        if " .. i .. " == 0 { " .. out .. " = fst(&" .. x .. "); }",
            "        " .. i .. inc,
            "    }",
            "    if *" .. out .. " != 7 { " .. exit .. "; }",
            "}" }
    end
    return hole_node("ret_storage_tuple_field_ref", body("zoril"), body("rust"))
end

local function hole_same_type_borrow_loop_escape()
    local root, out, i, inner, outer = fresh("hr"), fresh("ho"), fresh("hi"), fresh("hn"), fresh("ht")
    local function body(lang)
        local link = (lang == "rust") and "Link<'_>" or "Link"
        local none = (lang == "rust") and "None" or "OptLink.None"
        local some = (lang == "rust") and "Some" or "OptLink.Some"
        local exit = exit92(lang)
        local inc = (lang == "rust") and " += 1;" or " = " .. i .. " + 1;"
        return { "{",
            "    let " .. root .. ": " .. ((lang == "rust") and "Link<'_>" or "Link") ..
                " = Link { v: 1, prev: " .. none .. " };",
            "    let mut " .. out .. ": &" .. link .. " = &" .. root .. ";",
            "    let mut " .. i .. ": i32 = 0;",
            "    while " .. i .. " < 2 {",
            "        let " .. inner .. ": " .. link .. " = Link { v: 7 + " .. i .. " * 92, prev: " .. none .. " };",
            "        let " .. outer .. ": " .. link .. " = Link { v: 2, prev: " .. some .. "(&" .. inner .. ") };",
            "        if " .. i .. " == 0 { " .. out .. " = get_prev(&" .. outer .. "); }",
            "        " .. i .. inc,
            "    }",
            "    if " .. out .. ".v != 7 { " .. exit .. "; }",
            "}" }
    end
    return hole_node("same_type_borrow_loop_escape", body("zoril"), body("rust"))
end

local function hole_closure_capture_multiple_drop()
    local d, f, a, b = fresh("hd"), fresh("hf"), fresh("hda"), fresh("hdb")
    local val = 7 + rnd(20)
    local z = { "{",
        "    let " .. d .. " = D { x: " .. val .. " };",
        "    CONSTRUCTED = CONSTRUCTED + 1;",
        "    let " .. f .. " = || -> i32 { return " .. d .. ".x; };",
        "    let " .. a .. " = " .. f .. "();",
        "    let " .. b .. " = " .. f .. "();",
        "}" }
    local rr = { "{",
        "    let " .. d .. " = D { x: " .. val .. " };",
        "    let " .. f .. " = || -> i32 { return " .. d .. ".x; };",
        "    let " .. a .. " = " .. f .. "();",
        "    let " .. b .. " = " .. f .. "();",
        "}" }
    return hole_node("closure_capture_multiple_drop", z, rr)
end

local function hole_loop_closure_env_escape()
    local zero, f, i, x, cur = fresh("hz"), fresh("hf"), fresh("hi"), fresh("hx"), fresh("hc")
    local function body(lang)
        local exit = exit92(lang)
        local inc = (lang == "rust") and " += 1;" or " = " .. i .. " + 1;"
        return { "{",
            "    let " .. zero .. ": i32 = 0;",
            "    let mut " .. f .. " = || -> i32 { return " .. zero .. "; };",
            "    let mut " .. i .. ": i32 = 0;",
            "    while " .. i .. " < 2 {",
            "        let " .. x .. ": i32 = 7 + " .. i .. " * 92;",
            "        let " .. cur .. " = || -> i32 { return " .. x .. "; };",
            "        if " .. i .. " == 0 { " .. f .. " = " .. cur .. "; }",
            "        " .. i .. inc,
            "    }",
            "    if " .. f .. "() != 7 { " .. exit .. "; }",
            "}" }
    end
    return hole_node("loop_closure_env_escape", body("zoril"), body("rust"))
end

local function hole_let_destructure_double_drop()
    local pair, d2 = fresh("hp"), fresh("hd")
    local val = 7 + rnd(20)
    local z = { "{",
        "    let " .. pair .. ": (D, i32) = (D { x: " .. val .. " }, 2);",
        "    CONSTRUCTED = CONSTRUCTED + 1;",
        "    let (" .. d2 .. ", _) = " .. pair .. ";",
        "    if " .. d2 .. ".x != " .. val .. " { return 92; }",
        "}" }
    local rr = { "{",
        "    let " .. pair .. ": (D, i32) = (D { x: " .. val .. " }, 2);",
        "    let (" .. d2 .. ", _) = " .. pair .. ";",
        "    if " .. d2 .. ".x != " .. val .. " { std::process::exit(92); }",
        "}" }
    return hole_node("let_destructure_double_drop", z, rr)
end

local function hole_premark_byvalue_reset_to()
    local a, vpre, m, w, z2, j = fresh("ha"), fresh("hv"), fresh("hm"), fresh("hw"), fresh("hz"), fresh("hj")
    local n = 64
    local z = { "{",
        "    let mut " .. a .. " = Arena.new(65536 as u64).unwrap();",
        "    let " .. vpre .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let " .. m .. " = " .. a .. ".mark();",
        "    let " .. w .. " = grow_by_value(" .. vpre .. ");",
        "    " .. a .. ".reset_to(" .. m .. ");",
        "    let mut " .. z2 .. " = Vec::<u64>.new_in(&" .. a .. ");",
        "    let mut " .. j .. " = 0 as u64;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99 as u64); " .. j .. " = " .. j .. " + 1; }",
        "    if " .. w .. ".as_slice()[0] != 7 as u64 { return 92; }",
        "}" }
    local rr = { "{",
        "    let mut " .. a .. " = Arena::new(65536).unwrap();",
        "    let " .. vpre .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let " .. m .. " = " .. a .. ".mark();",
        "    let " .. w .. " = grow_by_value(" .. vpre .. ");",
        "    " .. a .. ".reset_to(" .. m .. ");",
        "    let mut " .. z2 .. " = ArenaVec::<u64>::new_in(&" .. a .. ");",
        "    let mut " .. j .. ": u64 = 0;",
        "    while " .. j .. " < " .. n .. " { " .. z2 .. ".push(99); " .. j .. " += 1; }",
        "    if " .. w .. ".as_slice()[0] != 7 { std::process::exit(92); }",
        "}" }
    return hole_node("premark_byvalue_reset_to", z, rr)
end

local function hole_raw_tuple_pattern_deref()
    return hole_node("raw_tuple_pattern_deref",
        { "{", "    return forge_tuple(3735928559) as i32;", "}" },
        { "{", "    return forge_tuple(3735928559) as i32;", "}" })
end

local function hole_raw_enum_pattern_deref()
    return hole_node("raw_enum_pattern_deref",
        { "{", "    return forge_enum(3735928559) as i32;", "}" },
        { "{", "    return forge_enum(3735928559) as i32;", "}" })
end

local function hole_local_buffer_view_drop()
    local v, r, n = fresh("hv"), fresh("hr"), 7 + rnd(20)
    -- The rule reads the borrow graph, not a list of view spellings, so the builder writes the
    -- shapes a list would miss: a `with_capacity` buffer, one a helper returned, one behind a
    -- struct field, and a `String` view (probes 284-292).
    local shape = rnd(5)
    if shape == 2 then P.needs_mk_vec = true end
    if shape == 3 then P.needs_holder = true end
    if shape == 4 then P.needs_string_view = true end
    local function body(lang)
        local exit = exit92(lang)
        if shape == 1 then
            if lang == "rust" then
                return { "{",
                    "    let mut " .. v .. ": Vec<i32> = Vec::with_capacity(4);",
                    "    " .. v .. ".push(" .. n .. ");",
                    "    let " .. r .. ": &i32 = &" .. v .. "[0];",
                    "    drop(" .. v .. ");",
                    "    if *" .. r .. " != " .. n .. " { " .. exit .. "; }",
                    "}" }
            end
            return { "{",
                "    let mut " .. v .. ": Vec<i32> = Vec::<i32>.with_capacity(4);",
                "    " .. v .. ".push(" .. n .. ");",
                "    let " .. r .. ": &i32 = " .. v .. ".get(0).unwrap();",
                "    @drop(" .. v .. ");",
                "    if *" .. r .. " != " .. n .. " { " .. exit .. "; }",
                "}" }
        elseif shape == 2 then
            if lang == "rust" then
                return { "{",
                    "    let " .. v .. ": Vec<i32> = mk_vec(" .. n .. ");",
                    "    let " .. r .. ": &i32 = &" .. v .. "[0];",
                    "    drop(" .. v .. ");",
                    "    if *" .. r .. " != " .. n .. " { " .. exit .. "; }",
                    "}" }
            end
            return { "{",
                "    let " .. v .. ": Vec<i32> = mk_vec(" .. n .. ");",
                "    let " .. r .. ": &i32 = " .. v .. ".get(0).unwrap();",
                "    @drop(" .. v .. ");",
                "    if *" .. r .. " != " .. n .. " { " .. exit .. "; }",
                "}" }
        elseif shape == 3 then
            if lang == "rust" then
                return { "{",
                    "    let mut " .. v .. " = VecHolder { v: Vec::new() };",
                    "    " .. v .. ".v.push(" .. n .. ");",
                    "    let " .. r .. ": &i32 = &" .. v .. ".v[0];",
                    "    drop(" .. v .. ");",
                    "    if *" .. r .. " != " .. n .. " { " .. exit .. "; }",
                    "}" }
            end
            return { "{",
                "    let mut " .. v .. " = VecHolder { v: Vec::<i32>.new() };",
                "    " .. v .. ".v.push(" .. n .. ");",
                "    let " .. r .. ": &i32 = " .. v .. ".v.get(0).unwrap();",
                "    @drop(" .. v .. ");",
                "    if *" .. r .. " != " .. n .. " { " .. exit .. "; }",
                "}" }
        elseif shape == 4 then
            if lang == "rust" then
                return { "{",
                    "    let mut " .. v .. " = String::new();",
                    "    " .. v .. ".push_str(\"hello world, a longer text\");",
                    "    let " .. r .. " = " .. v .. ".as_bytes();",
                    "    drop(" .. v .. ");",
                    "    if " .. r .. "[0] != 'h' as u8 { " .. exit .. "; }",
                    "}" }
            end
            return { "{",
                "    let mut " .. v .. " = String.new();",
                "    " .. v .. ".push_str(\"hello world, a longer text\");",
                "    let " .. r .. " = " .. v .. ".as_slice();",
                "    @drop(" .. v .. ");",
                "    if " .. r .. "[0] != 'h' as u8 { " .. exit .. "; }",
                "}" }
        end
        if lang == "rust" then
            return { "{",
                "    let mut " .. v .. ": Vec<i32> = Vec::new();",
                "    " .. v .. ".push(" .. n .. ");",
                "    let " .. r .. ": &i32 = &" .. v .. "[0];",
                "    drop(" .. v .. ");",
                "    if *" .. r .. " != " .. n .. " { " .. exit .. "; }",
                "}" }
        end
        return { "{",
            "    let mut " .. v .. ": Vec<i32> = Vec::<i32>.new();",
            "    " .. v .. ".push(" .. n .. ");",
            "    let " .. r .. ": &i32 = " .. v .. ".get(0).unwrap();",
            "    @drop(" .. v .. ");",
            "    if *" .. r .. " != " .. n .. " { " .. exit .. "; }",
            "}" }
    end
    return hole_node("local_buffer_view_drop", body("zoril"), body("rust"))
end

local function hole_fn_value_store_stack()
    local h, f, n, m = fresh("hfs"), fresh("hff"), 7 + rnd(20), 30 + rnd(20)
    local function body(lang)
        local exit = exit92(lang)
        if lang == "rust" then
            return { "{",
                "    let " .. h .. "_x: i32 = " .. n .. ";",
                "    let mut " .. h .. " = FnStoreH { p: &" .. h .. "_x };",
                "    let " .. f .. ": fn(&mut FnStoreH, &i32) = fn_store_put;",
                "    let " .. h .. "_n: i32 = " .. m .. ";",
                "    " .. f .. "(&mut " .. h .. ", &" .. h .. "_n);",
                "    if *" .. h .. ".p != " .. m .. " { " .. exit .. "; }",
                "}" }
        end
        return { "{",
            "    let " .. h .. "_x: i32 = " .. n .. ";",
            "    let mut " .. h .. " = FnStoreH { p: &" .. h .. "_x };",
            "    let " .. f .. ": fn(&mut FnStoreH, &i32) = fn_store_put;",
            "    let " .. h .. "_n: i32 = " .. m .. ";",
            "    " .. f .. "(&mut " .. h .. ", &" .. h .. "_n);",
            "    if *" .. h .. ".p != " .. m .. " { " .. exit .. "; }",
            "}" }
    end
    return hole_node("fn_value_store_stack", body("zoril"), body("rust"))
end

-- Weight 1 each: the hole constructs should be reachable at random, not take over the stream. A
-- `--seeds 1-30 --count 8` grammar run samples ~1,200 statements, so each of these is drawn about
-- five times; the calibration stream stays what measures each one exactly.
local HOLE_BUILDERS = {
    { "hole_index_mut_borrow", hole_index_mut_borrow, 1 },
    { "hole_slice_index_mut_borrow", hole_slice_index_mut_borrow, 1 },
    { "hole_index_compound_assign", hole_index_compound_assign, 1 },
    { "hole_arena_index_reset", hole_arena_index_reset, 1 },
    { "hole_arena_branch_reset", hole_arena_branch_reset, 1 },
    { "hole_arena_loop_mark_reset_to", hole_arena_loop_mark_reset_to, 1 },
    { "hole_branch_reassign_loop", hole_branch_reassign_loop, 1 },
    { "hole_arena_box_slice_reset", hole_arena_box_slice_reset, 1 },
    { "hole_arena_callptr_reset_to", hole_arena_callptr_reset_to, 1 },
    { "hole_arena_closure_ret_reset", hole_arena_closure_ret_reset, 1 },
    { "hole_enum_payload_block_escape", hole_enum_payload_block_escape, 1 },
    { "hole_arena_repeat_reset", hole_arena_repeat_reset, 1 },
    { "hole_ret_storage_local_alias", hole_ret_storage_local_alias, 1 },
    { "hole_ret_storage_struct_wrap", hole_ret_storage_struct_wrap, 1 },
    { "hole_same_type_borrow_loop_escape", hole_same_type_borrow_loop_escape, 1 },
    { "hole_closure_capture_multiple_drop", hole_closure_capture_multiple_drop, 1 },
    { "hole_loop_closure_env_escape", hole_loop_closure_env_escape, 1 },
    { "hole_let_destructure_double_drop", hole_let_destructure_double_drop, 1 },
    { "hole_premark_byvalue_reset_to", hole_premark_byvalue_reset_to, 1 },
    { "hole_raw_tuple_pattern_deref", hole_raw_tuple_pattern_deref, 1 },
    { "hole_raw_enum_pattern_deref", hole_raw_enum_pattern_deref, 1 },
    { "hole_local_buffer_view_drop", hole_local_buffer_view_drop, 1 },
    { "hole_fn_value_store_stack", hole_fn_value_store_stack, 1 },
    { "hole_ret_storage_index_ref", hole_ret_storage_index_ref, 1 },
    { "hole_ret_storage_tuple_field_ref", hole_ret_storage_tuple_field_ref, 1 },
}
for _, b in ipairs(HOLE_BUILDERS) do table.insert(BUILDERS, b) end

-- The two box shapes the first finding's fix pins. They are ordinary grammar now rather than
-- templates-only: Zoril refuses both, and `rustc` refuses the twin for the same type reason, so a
-- random program carries the check that the refusal stays. They are not known holes. The two shapes
-- are emitted as fixed source over the seed local `x` (`main`'s mutable i32) rather than as an
-- expression tree, because `print_expr` is only defined below.
STMT.borrow_passed_as_owned_box = function()
    P.needs_take_box = true
    tag("borrow-passed-as-owned-box")
    return { k = "Raw", z = { "{", "    let hb_v: i32 = take_box(&x);", "}" },
        r = { "{", "    let hb_v: i32 = take_box(&x);", "}" } }
end

STMT.owned_box_passed_as_borrow = function()
    P.needs_bump_box = true
    tag("owned-box-passed-as-borrow")
    return { k = "Raw", z = { "{", "    let hb_b: Box<i32> = box 41;", "    let hb_v: i32 = bump_box(hb_b);", "}" },
        r = { "{", "    let hb_b: Box<i32> = Box::new(41);", "    let hb_v: i32 = bump_box(hb_b);", "}" } }
end

-- Two capability-mismatch families as grammar builders: they are refused by both compilers, so they
-- do not add a finding, and they make the mismatch tags part of the random stream's coverage too.
STMT.capability_mismatch_grammar = function()
    local shapes = cap_shapes()
    local shape = shapes[rnd(#shapes)]
    return STMT.capability_mismatch(shape.fam, shape.pos, shape.free)
end

table.insert(BUILDERS, { "borrow_passed_as_owned_box", STMT.borrow_passed_as_owned_box, 1 })
table.insert(BUILDERS, { "owned_box_passed_as_borrow", STMT.owned_box_passed_as_borrow, 1 })
table.insert(BUILDERS, { "capability_mismatch_grammar", STMT.capability_mismatch_grammar, 2 })

local function make_helpers()
    P.helpers = {}
    local n = 1 + rnd(3)
    local generic = chance(50)
    if generic then P.generic_id = true end
    for i = 1, n do
        table.insert(P.helpers, "fwd" .. i)
        tag("reference-forwarding-helper")
    end
    P.helper_count = n
    P.helper_generic = generic
end

-- A whole-program shape rather than a one-statement one: the GAP row of 2026-10-12 was about a raw
-- pointer laundered through a container and then *dereferenced*, and the point of keeping it in the
-- generator is that the refusal stays exercised. An accepted one here is a finding again.
local RAW_DEREF_Z = "fn main() -> i32 {\n    let mut x: u32 = 7;\n    let p: *mut u32 = &mut x as *mut u32;\n    let t = (p, 1);\n    let q = t.0;\n    *q = 9;\n    if x != 9 { return 1; }\n    return 0;\n}\n"
-- The twin stops at the store: reading `x` afterwards would be a borrow conflict of its own (E0503), and
-- a twin that fails for a second reason makes the pair say less than it should.
local RAW_DEREF_R = "fn main() {\n    let mut x: u32 = 7;\n    let p: *mut u32 = &mut x as *mut u32;\n    let t: (*mut u32, i32) = (p, 1);\n    let q = t.0;\n    unsafe { *q = 9; }\n}\n"

local function build_program()
    P = { n = 0, locals = {}, tags = {}, helpers = {}, has_holders = false, has_tup = false, calibration = {} }
    make_helpers()
    local body = {}
    -- The seed local every borrow can hang off.
    local root = { name = "x", ty = "I32", mutable = true }
    table.insert(P.locals, root)
    body.root = { k = "LetMutInt", name = "x", e = { k = "Int", v = int_literal(), ty = "I32" } }
    P.ints_mutable = true
    -- Swarm testing: each program enables a random subset of the builders instead of drawing from
    -- all of them. Drawn uniformly, a rare combination (no arena, no borrows, only owning values and
    -- control flow) is vanishingly rare; with a subset it is common, and the subset is a pure function
    -- of the seed, so a program reproduces. The manifest records what was switched off.
    -- The hole builders are a separate pool with the share they always had: a program that carries one is
    -- judged by the hole logic, not by the search, and subsetting only the others would let the holes
    -- take over the stream (measured: 5% of programs became 51%).
    local builders, holes_pool, off = {}, {}, {}
    local normal_total, hole_total = 0, 0
    for _, b in ipairs(BUILDERS) do
        if string.sub(b[1], 1, 5) == "hole_" then
            table.insert(holes_pool, b); hole_total = hole_total + b[3]
        else
            normal_total = normal_total + b[3]
            if swarm == 1 and not chance(50) then
                table.insert(off, b[1])
            else
                table.insert(builders, b)
            end
        end
    end
    if #builders < 3 then                              -- never a program with nothing to build from
        builders, off = {}, {}
        for _, b in ipairs(BUILDERS) do
            if string.sub(b[1], 1, 5) ~= "hole_" then table.insert(builders, b) end
        end
    end
    local hole_share = math.floor(hole_total * 100 / (hole_total + normal_total))
    P.swarm_off = off
    P.swarm_arena = false
    for _, b in ipairs(builders) do if b[1] == "let_arena" then P.swarm_arena = true end end
    local stmts = {}
    local total = 0
    for _, b in ipairs(builders) do total = total + b[3] end
    local want = 3 + rnd(5)
    local guard = 0
    while #stmts < want and guard < 40 do
        -- The pool is chosen once per statement and retried inside it: a normal builder that cannot
        -- build (no integer local to point at yet) returns nothing, and re-drawing the pool on every
        -- failure handed those slots to the hole builders, which never fail.
        local pool, pool_total = builders, total
        if chance(hole_share) then
            pool, pool_total = holes_pool, hole_total
        end
        for _ = 1, 8 do
            guard = guard + 1
            local pick, acc, node = rnd(pool_total), 0, nil
            for _, b in ipairs(pool) do
                acc = acc + b[3]
                if pick <= acc then node = b[2](); break end
            end
            if node then table.insert(stmts, node); break end
        end
    end
    -- At least half of a program's values own something, by construction: the point of the mix is the
    -- owning cases, and a share that only held on average would leave programs where none of the
    -- ownership paths (drop glue, arena ties, box moves) is exercised at all.
    local guard_mix = 0
    while P.swarm_arena and owns_count() * 2 < #P.locals and guard_mix < 12 do
        guard_mix = guard_mix + 1
        local node = STMT.let_arena()
        if node then table.insert(stmts, node) end
    end
    body.stmts = stmts
    return body
end

--- Expected values --------------------------------------------------------------------------------
-- The generator holds the tree it printed, so it can also *run* it: a small interpreter over the
-- statement kinds whose effect on `i32` values it understands. The program then folds those values
-- into a checksum (`chk = chk * 31 + v`, Zoril's wrapping `i32`) and exits 93 when the checksum is not
-- the one computed here - a miscompile (a lost write, a wrong load, a wrong field offset) that produces
-- a wrong value but no fault, which neither the crash oracle nor the canaries can see.
--
-- Where the interpreter cannot follow a statement it says so: the program carries no check, and its
-- manifest line says `unchecked:<why>` so a run can report how many programs were and were not checked.
-- A `Raw` statement is a self-contained block that reads and writes only its own locals (and checks them
-- against constants itself), so it does not touch the values tracked here.
local function wrap32(v)
    v = v % 4294967296
    if v >= 2147483648 then v = v - 4294967296 end
    return v
end

local Unknown = {}   -- raised (as an error value) when a statement cannot be followed

local function ev_expr(env, e)
    local function need(v)
        if v == nil then error({ unknown = Unknown, why = "no value for " .. tostring(e.k) }) end
        return v
    end
    if e.k == "Int" then return tonumber(e.v) end
    if e.k == "Local" then return need(env.val[e.name]) end
    if e.k == "Deref" or e.k == "DerefMutLocal" then
        local name = (e.k == "Deref") and e.e.name or e.name
        local r = need(env.ref[name])
        if r.const ~= nil then return r.const end
        return need(env.val[r.target])
    end
    if e.k == "HolderRead" then return need(env.val[need(env.holder[e.name]).target]) end
    if e.k == "TupElem" then return need(env.val[need(env.tup[e.name]).target]) end
    if e.k == "IndexRead" then return 8 end           -- the only array is [7, 8, 9, 10] and index 1
    error({ unknown = Unknown, why = "expression " .. tostring(e.k) })
end

-- Evaluates one statement into `env`. `acc(v)` folds a value into the checksum, in the order the
-- printed program does.
local function ev_stmt(env, s, acc)
    local function int_local(name, v)
        env.val[name] = v
        table.insert(env.order, name)
    end
    local k = s.k
    if k == "Raw" or k == "CapMismatch" or k == "RawInStruct" or k == "LetArena" or k == "DropStruct" then
        return
    elseif k == "LetInt" or k == "LetMutInt" then
        int_local(s.name, ev_expr(env, s.e))
    elseif k == "LetBorrow" or k == "LetMutBorrow" then
        env.ref[s.name] = { target = s.target }
    elseif k == "LetBox" then
        env.val[s.name] = ev_expr(env, s.e)
    elseif k == "LetOptRef" then
        env.opt[s.name] = { none = s.none, target = s.target }
    elseif k == "LetHolder" then
        env.holder[s.name] = { a = ev_expr(env, s.e), target = s.target }
    elseif k == "LetTuple" then
        env.tup[s.name] = { a = ev_expr(env, s.e), target = s.target }
    elseif k == "BoxPoint" then
        -- set_boxpt: p.b = c; p.a = p.a + 1.  The checksum folds read_boxpt (a + b) and then the two fields.
        local a, b, c = ev_expr(env, s.a), ev_expr(env, s.b), ev_expr(env, s.c)
        b = c
        a = wrap32(a + 1)
        acc(wrap32(a + b))
        acc(a)
        acc(b)
    elseif k == "LetArray" then
        acc(8)                                     -- name_v = ar[1]
    elseif k == "ReadBorrow" then
        acc(ev_expr(env, s.e))
    elseif k == "AssignThroughRef" or k == "AssignThroughRefAfterBorrow" then
        if k == "AssignThroughRefAfterBorrow" then ev_stmt(env, s.borrow, acc) end
        local v = ev_expr(env, s.e)
        local r = env.ref[s.dst.name]
        if not r or not r.target then error({ unknown = Unknown, why = "assignment through an unknown reference" }) end
        env.val[r.target] = v
    elseif k == "CallStmt" then
        local a = s.arg
        local r = env.ref[a.name]
        if a.ty ~= "REF_I32" and a.ty ~= "REFMUT_I32" then
            error({ unknown = Unknown, why = "a helper called with a " .. tostring(a.ty) })
        end
        if not r then error({ unknown = Unknown, why = "a helper called with an unknown reference" }) end
        local base = (r.const ~= nil) and r.const or env.val[r.target]
        local n = tonumber(string.match(s.helper, "%d+$")) or 1
        acc(wrap32(base + (n - 1)))
    elseif k == "BlockInner" then
        acc(env.val[s.target])
    elseif k == "BlockEscape" then
        env.ref[s.name] = { const = 9 }
        acc(9)
    elseif k == "WhileBorrow" then
        for _ = 1, s.rounds do acc(env.val[s.target]) end
    elseif k == "MatchOpt" then
        local o = env.opt[s.src]
        if not o then error({ unknown = Unknown, why = "match on an unknown option" }) end
        int_local(s.name, o.none and 0 or env.val[o.target])
    elseif k == "IfLetOpt" then
        local o = env.opt[s.src]
        if not o then error({ unknown = Unknown, why = "if-let on an unknown option" }) end
        if not o.none then acc(env.val[o.target]) end
    elseif k == "ClosureInner" then
        acc(3)                                     -- *cp + 1 with cp -> 2
    elseif k == "ClosureEscape" then
        acc(8)                                     -- *p + 1 with p -> 7
    else
        error({ unknown = Unknown, why = "statement " .. tostring(k) })
    end
end

-- Returns { chk = <expected checksum>, final = <names folded in at the end of the block> } or
-- nil, why. The seed local `x` is `main`'s `3`, declared outside the generated block.
local function evaluate(body)
    local env = { val = { x = 3 }, ref = {}, opt = {}, holder = {}, tup = {}, order = { "x" } }
    local chk = 0
    local function acc(v)
        if v == nil then error({ unknown = Unknown, why = "a value that is not tracked" }) end
        chk = wrap32(chk * 31 + v)
    end
    local ok, err = pcall(function()
        for _, s in ipairs(body.stmts or {}) do ev_stmt(env, s, acc) end
        for _, name in ipairs(env.order) do acc(env.val[name]) end
    end)
    if not ok then
        if type(err) == "table" and err.unknown == Unknown then return nil, err.why end
        error(err)
    end
    return { chk = chk, final = env.order, vals = env.val }
end

-- Runtime checks reached by a value computed at run time. Every index in the grammar used to be a
-- constant in range, so no generated program ever reached a bounds check, a division trap or a shift
-- check (`traps=0` in every run). Here the operand is derived from `x`, whose final value the
-- interpreter knows, so the generator knows whether the program must trap and with which exit code:
-- 134 for an index out of range and a shift count outside the width, 136 (SIGFPE) for division or
-- remainder by zero and `INT_MIN / -1`. The manifest says so, and the driver treats a program that
-- should have trapped and exited 0, or trapped with the other code, as a fault. One check per program,
-- after the block and the checksum and drop-count checks, so nothing it skips could have been a check.
local function trunc_rem(a, b)
    local q = a / b
    q = (q < 0) and math.ceil(q) or math.floor(q)
    return a - q * b
end

local TRAP_KINDS = {
    { name = "array-index", tag = "dynamic-array-index" },
    { name = "slice-index", tag = "dynamic-slice-index" },
    { name = "divide", tag = "dynamic-divisor" },
    { name = "remainder", tag = "dynamic-divisor" },
    { name = "shift", tag = "dynamic-shift-count" },
}

local function add_dynamic_check(body, ex)
    if not ex or not chance(60) then return end
    if next(P.calibration or {}) then return end            -- a marked program is judged by its hole
    local kind = TRAP_KINDS[rnd(#TRAP_KINDS)]
    -- Any integer local whose value the interpreter knows: `x` alone is `3` in nearly every program, which
    -- never reaches an out-of-range index.
    local terms, x = {}, 5
    for i = 1, math.min(#ex.final, 4) do
        local name = ex.final[rnd(#ex.final)]
        local coef = ({ 1, 5, 7, 11 })[i]
        table.insert(terms, name .. " * " .. coef)
        x = x + ex.vals[name] * coef
    end
    x = wrap32(x)
    local src = "(" .. table.concat(terms, " + ") .. " + 5)"      -- the operand, spread over the residues
    local code = nil
    if kind.name == "array-index" or kind.name == "slice-index" then
        if (x % 8) >= 4 then code = 134 end
    elseif kind.name == "divide" or kind.name == "remainder" then
        local den = math.tointeger(trunc_rem(x, 3)) - 1
        if den == 0 or den == -1 then code = 136 end
    else
        local s = (x % 4294967296) % 40
        if s >= 32 then code = 134 end
    end
    body.dynamic = { kind = kind.name, code = code, src = src }
    P.trap_code = code
    tag(kind.tag)
    if code then tag("expected-trap") end
end

local function print_dynamic(d, lang, add)
    local rs = (lang == "rust")
    if d.kind == "array-index" or d.kind == "slice-index" then
        add("    let t_arr: [i32; 4] = [11, 22, 33, 44];")
        add("    let t_i: usize = (" .. d.src .. " as usize) % 8;")
        if d.kind == "array-index" then
            add("    let t_v: i32 = t_arr[t_i];")
        else
            add("    let t_s: " .. (rs and "&[i32]" or "[i32]") .. " = &t_arr;")
            add("    let t_v: i32 = t_s[t_i];")
        end
    elseif d.kind == "divide" or d.kind == "remainder" then
        local op = (d.kind == "divide") and "/" or "%"
        add("    let t_den: i32 = (" .. d.src .. " % 3) - 1;")
        add("    let t_v: i32 = " .. (rs and "i32::MIN" or "(-2147483647 - 1)") .. " " .. op .. " t_den;")
    else
        add("    let t_s: u32 = (" .. d.src .. " as u32) % 40;")
        add("    let t_v: i32 = " .. (rs and "1i32" or "1") .. " << t_s;")
    end
    -- The result is read: QBE drops a pure division whose value nobody uses, and with it the trap.
    add("    if t_v == 1234567 { " .. (rs and "std::process::exit(94);" or "return 94;") .. " }")
end

--- Printing ---------------------------------------------------------------------------------------

local function print_expr(e, lang)
    if e.k == "Int" then return e.v end
    if e.k == "Local" then return e.name end
    if e.k == "Deref" then return "*" .. e.e.name end
    if e.k == "DerefMutLocal" then return "*" .. e.name end
    if e.k == "RawNull" then return "0 as *mut i32" end
    if e.k == "HolderRead" then return "*" .. e.name .. ".r" end
    if e.k == "TupElem" then return "*" .. e.name .. ".1" end
    if e.k == "IndexRead" then return e.name .. "[" .. tostring(e.idx) .. "]" end
    error("gen.lua: no printer for expression " .. tostring(e.k))
end

local function print_stmts(stmts, lang, indent)
    local out = {}
    -- Folds a value the program just computed into the checksum (Zoril only: the twin is type-checked,
    -- never run, and stays as it was). Only when the evaluator could follow the whole program.
    local function fold(var, ind)
        if lang ~= "rust" and P and P.expect then
            table.insert(out, (ind or indent) .. "chk = chk * 31 + " .. var .. ";")
        end
    end
    for _, s in ipairs(stmts) do
        if s.k == "Raw" then
            local lines = (lang == "rust") and s.r or s.z
            for _, line in ipairs(lines) do table.insert(out, indent .. line) end
        elseif s.k == "LetInt" then
            table.insert(out, indent .. "let " .. s.name .. ": i32 = " .. print_expr(s.e, lang) .. ";")
        elseif s.k == "LetMutInt" then
            table.insert(out, indent .. "let mut " .. s.name .. ": i32 = " .. print_expr(s.e, lang) .. ";")
        elseif s.k == "LetBorrow" or s.k == "LetMutBorrow" then
            local mut = (s.k == "LetMutBorrow") and "mut " or ""
            table.insert(out, indent .. "let " .. s.name .. ": &" .. mut .. "i32 = &" .. mut .. s.target .. ";")
        elseif s.k == "LetBox" then
            local rhs = (lang == "rust") and ("Box::new(" .. print_expr(s.e, lang) .. ")") or ("box " .. print_expr(s.e, lang))
            table.insert(out, indent .. "let " .. s.name .. ": Box<i32> = " .. rhs .. ";")
        elseif s.k == "LetArena" then
            if lang == "rust" then
                -- The twin models the arena as a lifetime: `ArenaVec<'a, T>` holds `&'a Arena`, so
                -- `rustc` rejects using the collection after `a.reset()`.
                table.insert(out, indent .. "let " .. s.arena .. " = Arena::new(65536).unwrap();")
                table.insert(out, indent .. "let mut " .. s.vec .. " = ArenaVec::<i32>::new_in(&" .. s.arena .. ");")
                table.insert(out, indent .. "    " .. s.vec .. ".push(7);")
                table.insert(out, indent .. "    let s: &[i32] = " .. s.vec .. ".as_slice();")
                table.insert(out, indent .. "    if s[0] != 7 { std::process::exit(92); }")
            else
                table.insert(out, indent .. "let " .. s.arena .. " = Arena.new(65536).unwrap();")
                -- The element type goes on the path, as the stdlib writes it (`Vec::<u64>.new_in(&a)` in
                -- `tests/language/memory/borrow_named_local_ends_at_last_use.zrl`): annotating the
                -- binding instead is refused with "unknown type `T`" from inside `vec.zrl`, which is a
                -- generator bug - and was one of the six type errors item 3 counts.
                table.insert(out, indent .. "let mut " .. s.vec .. " = Vec::<i32>.new_in(&" .. s.arena .. ");")
                table.insert(out, indent .. s.vec .. ".push(7);")
                table.insert(out, indent .. "let s: [i32] = " .. s.vec .. ".as_slice();")
                table.insert(out, indent .. "if s[0] != 7 { return 92; }")
            end
        elseif s.k == "LetOptRef" then
            local rhs
            if s.none then
                rhs = (lang == "rust") and "None" or "Option.None"
            else
                rhs = (lang == "rust") and ("Some(&" .. s.target .. ")") or ("Option.Some(&" .. s.target .. ")")
            end
            table.insert(out, indent .. "let " .. s.name .. ": Option<&i32> = " .. rhs .. ";")
        elseif s.k == "LetHolder" then
            local ann = (lang == "rust") and (s.name .. ": Holder<'_>") or (s.name .. ": Holder")
            table.insert(out, indent .. "let " .. ann ..
                " = Holder { a: " .. print_expr(s.e, lang) .. ", r: &" .. s.target .. " };")
        elseif s.k == "LetTuple" then
            table.insert(out, indent .. "let " .. s.name .. " = (" .. print_expr(s.e, lang) .. ", &" .. s.target .. ");")
        elseif s.k == "BoxPoint" then
            local n = s.name
            if lang == "rust" then
                table.insert(out, indent .. "let mut " .. n .. ": Box<BoxPt> = Box::new(BoxPt { a: " .. print_expr(s.a, lang) .. ", b: " .. print_expr(s.b, lang) .. " });")
                table.insert(out, indent .. "set_boxpt(&mut " .. n .. ", " .. print_expr(s.c, lang) .. ");")
                table.insert(out, indent .. "let " .. n .. "_v: i32 = read_boxpt(&" .. n .. ");")
            else
                table.insert(out, indent .. "let mut " .. n .. ": Box<BoxPt> = box BoxPt { a: " .. print_expr(s.a, lang) .. ", b: " .. print_expr(s.b, lang) .. " };")
                table.insert(out, indent .. "set_boxpt(&mut " .. n .. ", " .. print_expr(s.c, lang) .. ");")
                table.insert(out, indent .. "let " .. n .. "_v: i32 = read_boxpt(&" .. n .. ");")
            end
            fold(n .. "_v")
            fold(n .. ".a")
            fold(n .. ".b")
        elseif s.k == "LetArray" then
            table.insert(out, indent .. "let " .. s.name .. ": [i32; 4] = [7, 8, 9, 10];")
            table.insert(out, indent .. "let " .. s.name .. "_v: i32 = " .. s.name .. "[1];")
            table.insert(out, indent .. "if " .. s.name .. "_v != 8 { " .. ((lang == "rust") and 'std::process::exit(92)' or 'return 92') .. "; }")
            fold(s.name .. "_v")
        elseif s.k == "ReadBorrow" then
            table.insert(out, indent .. "let " .. s.name .. "_v: i32 = " .. print_expr(s.e, lang) .. ";")
            fold(s.name .. "_v")
        elseif s.k == "AssignThroughRefAfterBorrow" then
            local bs = print_stmts({ s.borrow }, lang, indent)
            for _, b in ipairs(bs) do table.insert(out, b) end
            table.insert(out, indent .. print_expr(s.dst, lang) .. " = " .. print_expr(s.e, lang) .. ";")
        elseif s.k == "AssignThroughRef" then
            table.insert(out, indent .. print_expr(s.dst, lang) .. " = " .. print_expr(s.e, lang) .. ";")
        elseif s.k == "CallStmt" then
            table.insert(out, indent .. "let " .. s.helper .. "_v: i32 = " .. s.helper .. "(" .. print_expr(s.arg, lang) .. ");")
            fold(s.helper .. "_v")
        elseif s.k == "BlockInner" then
            tag("borrow-inside-a-block")
            table.insert(out, indent .. "{")
            table.insert(out, indent .. "    let q: &i32 = &" .. s.target .. ";")
            table.insert(out, indent .. "    let q_v: i32 = *q;")
            fold("q_v", indent .. "    ")
            table.insert(out, indent .. "}")
        elseif s.k == "BlockEscape" then
            table.insert(out, indent .. "let mut " .. s.name .. ": &i32 = &" .. s.target .. ";")
            table.insert(out, indent .. "{")
            table.insert(out, indent .. "    let z: i32 = " .. "9" .. ";")
            table.insert(out, indent .. "    " .. s.name .. " = &z;")
            table.insert(out, indent .. "}")
            table.insert(out, indent .. "let " .. s.name .. "_v: i32 = *" .. s.name .. ";")
            fold(s.name .. "_v")
        elseif s.k == "WhileBorrow" then
            table.insert(out, indent .. "let mut wc: i32 = 0;")
            table.insert(out, indent .. "while wc < " .. tostring(s.rounds) .. " {")
            table.insert(out, indent .. "    let " .. s.name .. ": &i32 = &" .. s.target .. ";")
            table.insert(out, indent .. "    let " .. s.name .. "_v: i32 = *" .. s.name .. ";")
            fold(s.name .. "_v", indent .. "    ")
            table.insert(out, indent .. "    wc = wc + 1;")
            table.insert(out, indent .. "}")
        elseif s.k == "MatchOpt" then
            local some = (lang == "rust") and "Some" or "Option.Some"
            local none = (lang == "rust") and "None" or "Option.None"
            table.insert(out, indent .. "let " .. s.name .. ": i32 = match " .. s.src .. " { " .. some ..
                "(r) => *r, " .. none .. " => 0 };")
        elseif s.k == "IfLetOpt" then
            local some = (lang == "rust") and "Some" or "Option.Some"
            table.insert(out, indent .. "if let " .. some .. "(r) = " .. s.src .. " {")
            table.insert(out, indent .. "    let il_v: i32 = *r;")
            fold("il_v", indent .. "    ")
            table.insert(out, indent .. "}")
        elseif s.k == "ClosureInner" then
            table.insert(out, indent .. "let cp_t: i32 = " .. "2" .. ";")
            table.insert(out, indent .. "let cp: &i32 = &cp_t;")
            table.insert(out, indent .. "let " .. s.name .. " = |q: i32| -> i32 { *cp + q };")
            table.insert(out, indent .. "let " .. s.name .. "_v: i32 = " .. s.name .. "(1);")
            fold(s.name .. "_v")
        elseif s.k == "ClosureEscape" then
            table.insert(out, indent .. "let mut " .. s.name .. ": fn(i32) -> i32 = plain;")
            table.insert(out, indent .. "{")
            table.insert(out, indent .. "    let z: i32 = " .. "7" .. ";")
            table.insert(out, indent .. "    let p: &i32 = &z;")
            table.insert(out, indent .. "    " .. s.name .. " = |q: i32| -> i32 { *p + q };")
            table.insert(out, indent .. "}")
            table.insert(out, indent .. "let " .. s.name .. "_v: i32 = " .. s.name .. "(1);")
            fold(s.name .. "_v")
        elseif s.k == "DropStruct" then
            local ann = (lang == "rust") and (s.name .. ": DHolder<'_>") or s.name
            if P.needs_drop_counter and lang ~= "rust" then
                table.insert(out, indent .. "CONSTRUCTED = CONSTRUCTED + 1;")
            end
            table.insert(out, indent .. "let " .. ann .. " = DHolder { r: &" .. s.target .. " };")
        elseif s.k == "CapMismatch" then
            local have = (s.free and ((lang == "rust") and s.fam.r_free or s.fam.z_free))
                or ((lang == "rust") and s.fam.r or s.fam.z)
            if s.pos == "as-argument" then
                table.insert(out, indent .. "let " .. s.n .. "_v: i32 = " .. s.n .. "_f(" .. have .. ");")
            elseif s.pos == "as-let" then
                table.insert(out, indent .. "let " .. s.n .. "_q: " .. s.fam.want .. " = " .. have .. ";")
            elseif s.pos == "as-return" then
                table.insert(out, indent .. "// capability mismatch: " .. s.fam.t .. " returned as another")
            else
                -- A reference-typed field needs a lifetime in the Rust twin, and the struct is declared
                -- with one, so the annotation says it too.
                local st = "CapStruct" .. s.n .. (((lang == "rust") and string.find(s.fam.want, "&")) and "<'_>" or "")
                local lit = "CapStruct" .. s.n
                table.insert(out, indent .. "let " .. s.n .. "_s: " .. st .. " = " .. lit .. " { p: " .. have .. " };")
            end
        elseif s.k == "RawInStruct" then
            table.insert(out, indent .. "let " .. s.name .. " = PRaw { p: 0 as *mut i32, tag: 1 };")
        else
            error("gen.lua: no printer for statement " .. tostring(s.k))
        end
    end
    return out
end

local function print_decls(lang)
    local out = {}
    local function add(s) table.insert(out, s) end
    if P.needs_arena then
        if lang ~= "rust" then
            add("import \"mem.zrl\";")
            add("import \"vec.zrl\";")
            add("use mem::Arena;")
            add("use vec::Vec;")
            add("")
        else
            -- A tiny lifetime shim: `ArenaVec<'a, T>` borrows the arena for as long as the value is
            -- used, and `reset`/`reset_to` take `&mut Arena`, so `rustc` rejects any use of arena
            -- memory after either. `reset_to` cannot be twinned faithfully (Zoril deliberately
            -- accepts an untouched pre-mark container across it), which is why those programs are
            -- marked `no-rustc-diff`.
            add("struct Arena(i32);")
            add("struct ArenaMark(usize);")
            add("struct ArenaVec<'a, T>(&'a Arena, Vec<T>);")
            add("impl Arena {")
            add("    fn new(_n: u64) -> Option<Arena> { Some(Arena(0)) }")
            add("    fn reset(&mut self) {}")
            add("    fn mark(&self) -> ArenaMark { ArenaMark(0) }")
            add("    fn reset_to(&mut self, _m: ArenaMark) {}")
            add("}")
            add("impl<'a, T: Copy> ArenaVec<'a, T> {")
            add("    fn new_in(a: &'a Arena) -> Self { ArenaVec(a, Vec::new()) }")
            add("    fn push(&mut self, v: T) { self.1.push(v); }")
            add("    fn len(&self) -> usize { self.1.len() }")
            add("    fn as_slice(&self) -> &'a [T] { &[] }")
            add("}")
            add("")
        end
    end
    if P.uses_option and lang ~= "rust" then
        add("enum Option<T> { Some(T), None }")
        add("")
    end
    if P.needs_optslice then
        if lang == "rust" then
            add("enum OptSlice<'a> { Some(&'a [u64]), None }")
        else
            add("enum OptSlice { Some([u64]), None }")
        end
        add("")
    end
    if P.needs_enum then
        add("enum E { Some(i32), None }")
        add("")
    end
    if P.needs_link then
        if lang == "rust" then
            add("struct Link<'a> { v: i32, prev: Option<&'a Link<'a>> }")
        else
            add("enum OptLink { Some(&Link), None }")
            add("struct Link { v: i32, prev: OptLink }")
        end
        add("")
    end
    if P.needs_drop_counter then
        if lang == "rust" then
            -- The counter is Zoril-only: it is a runtime oracle, and the Rust twin is only asked
            -- whether the program is borrow-checkable. A plain struct keeps the twin's ownership
            -- shape (the closure still captures an owning value).
            add("struct D { x: i32 }")
        else
            add("static mut CONSTRUCTED: i32 = 0;")
            add("static mut DROPS: i32 = 0;")
            add("")
            add("struct D { x: i32 }")
            add("impl Drop for D {")
            add("    fn drop(self: &mut D) { DROPS = DROPS + 1; }")
            add("}")
        end
        add("")
    end
    if P.generic_id then
        add("fn id<T>(t: T) -> T { return t; }")
        add("")
    end
    for i = 1, (P.helper_count or 0) do
        local src = "&i32"
        local call = P.helper_generic and ("*id(r)") or "*r"
        add("fn fwd" .. i .. "(r: " .. src .. ") -> i32 { return " .. call .. " + " .. tostring(i - 1) .. "; }")
    end
    if (P.helper_count or 0) > 0 then add("") end
    add("fn plain(q: i32) -> i32 { return q + 1; }")
    if P.needs_take_box then
        add("")
        add("fn take_box(b: Box<i32>) -> i32 { return *b; }")
    end
    if P.needs_bump_box then
        add("")
        add("fn bump_box(r: &i32) -> i32 { return *r + 1; }")
    end
    if P.needs_bump_i32 then
        add("")
        add("fn bump_i32(p: &mut i32) { *p = *p + 1; }")
    end
    if P.needs_mutate_slice then
        add("")
        if lang == "rust" then
            add("fn mutate_slice(s: &[i32]) { let p: &mut i32 = &mut s[0]; *p = 99; }")
        else
            add("fn mutate_slice(s: [i32]) { let p: &mut i32 = &mut s[0]; *p = 99; }")
        end
    end
    if P.needs_id_alias then
        add("")
        add("fn id_alias(r: &i32) -> &i32 { let p = r; return p; }")
    end
    if P.needs_same_ref then
        add("")
        add("fn same_ref(r: &i32) -> &i32 { return r; }")
    end
    if P.needs_choose_ref then
        add("")
        add("fn choose_ref(r: &i32) -> &i32 { if *r > 0 { return r; } else { return r; } }")
    end
    if P.needs_first_index then
        add("")
        add("fn first(a: &[i32; 4]) -> &i32 { return &a[0]; }")
    end
    if P.needs_fst_tuple then
        add("")
        add("fn fst(t: &(i32, i32)) -> &i32 { return &t.0; }")
    end
    if P.needs_mk_vec then
        add("")
        if lang == "rust" then
            add("fn mk_vec(n: i32) -> Vec<i32> { let mut v: Vec<i32> = Vec::new(); v.push(n); return v; }")
        else
            add("fn mk_vec(n: i32) -> Vec<i32> { let mut v: Vec<i32> = Vec::<i32>.new(); v.push(n); return v; }")
        end
    end
    if P.needs_holder then
        add("")
        add("struct VecHolder { v: Vec<i32> }")
    end
    if P.needs_string_view then
        add("")
        if lang ~= "rust" then
            add("import \"string.zrl\";")
            add("use string::String;")
            add("")
        end
    end
    if P.needs_fn_store then
        add("")
        if lang == "rust" then
            add("struct FnStoreH<'a> { p: &'a i32 }")
            add("fn fn_store_put<'a>(h: &mut FnStoreH<'a>, p: &'a i32) { h.p = p; }")
        else
            add("struct FnStoreH { p: &i32 }")
            add("fn fn_store_put(h: &mut FnStoreH, p: &i32) { h.p = p; }")
        end
    end
    if P.needs_grow_vec then
        add("")
        if lang == "rust" then
            add("fn grow_vec(w: &mut ArenaVec<u64>) { let mut i: u64 = 0; while i < 64 { w.push(7); i += 1; } }")
        else
            add("fn grow_vec(w: &mut Vec<u64>) { let mut i = 0 as u64; while i < 64 { w.push(7 as u64); i = i + 1; } }")
        end
    end
    if P.needs_grow_by_value then
        add("")
        if lang == "rust" then
            add("fn grow_by_value(v: ArenaVec<u64>) -> ArenaVec<u64> { let mut w = v; let mut i: u64 = 0; while i < 64 { w.push(7); i += 1; } return w; }")
        else
            add("fn grow_by_value(v: Vec<u64>) -> Vec<u64> { let mut w = v; let mut i = 0 as u64; while i < 64 { w.push(7 as u64); i = i + 1; } return w; }")
        end
    end
    if P.needs_forge_tuple then
        add("")
        if lang == "rust" then
            add("fn forge_tuple(p: u64) -> u64 { let raw: *const (u64, u64) = p as *const (u64, u64); unsafe { let (a, _) = *raw; return a; } }")
        else
            add("fn forge_tuple(p: u64) -> u64 { let raw: *(u64, u64) = p as *(u64, u64); let (a, _) = raw; return *a; }")
        end
    end
    if P.needs_boxpt then
        add("")
        if lang == "rust" then
            add("struct BoxPt { a: i32, b: i32 }")
            add("fn set_boxpt(p: &mut Box<BoxPt>, v: i32) { p.b = v; p.a = p.a.wrapping_add(1); }")
            add("fn read_boxpt(p: &Box<BoxPt>) -> i32 { return p.a.wrapping_add(p.b); }")
        else
            add("struct BoxPt { a: i32, b: i32 }")
            add("fn set_boxpt(p: &mut Box<BoxPt>, v: i32) { p.b = v; p.a = p.a + 1; }")
            add("fn read_boxpt(p: &Box<BoxPt>) -> i32 { return p.a + p.b; }")
        end
    end
    if P.needs_forge_enum then
        add("")
        if lang == "rust" then
            add("enum OptU64 { Some(u64), None }")
            add("fn forge_enum(p: u64) -> u64 { let raw = p as *const OptU64; unsafe { match *raw { OptU64::Some(x) => { return x; }, OptU64::None => { return 0; } } } }")
        else
            add("enum OptU64 { Some(u64), None }")
            add("fn forge_enum(p: u64) -> u64 { let raw: *OptU64 = p as *OptU64; match raw { OptU64.Some(x) => { return *x; }, OptU64.None => { return 0; } } }")
        end
    end
    if P.has_holders or P.needs_wrap then
        add("")
        if lang == "rust" then
            add("struct Holder<'a> { a: i32, r: &'a i32 }")
        else
            add("struct Holder { a: i32, r: &i32 }")
        end
        if P.needs_wrap then
            add("")
            if lang == "rust" then
                add("fn wrap<'a>(r: &'a i32) -> Holder<'a> { return Holder { a: 0, r: r }; }")
            else
                add("fn wrap(r: &i32) -> Holder { return Holder { a: 0, r: r }; }")
            end
        end
    end
    if P.needs_link then
        add("")
        if lang == "rust" then
            add("fn get_prev<'a>(l: &'a Link<'a>) -> &'a Link<'a> { match l.prev { Some(p) => p, None => l } }")
        else
            add("fn get_prev(l: &Link) -> &Link { match l.prev { OptLink.Some(p) => { return p; }, OptLink.None => { return l; } } }")
        end
    end
    if P.drop_seen then
        add("")
        if lang == "rust" then
            add("struct DHolder<'a> { r: &'a i32 }")
            add("impl<'a> Drop for DHolder<'a> { fn drop(&mut self) { let _v = *self.r; } }")
        else
            add("struct DHolder { r: &i32 }")
            if P.needs_drop_counter then
                -- `DropStruct` increments CONSTRUCTED under the same condition: the drop counter is
                -- balanced only if the Drop impl counts its own drop. Without this the builder left
                -- an unmatched construction, so every program carrying it exited 91 even with no hole.
                add("impl Drop for DHolder { pub fn drop(self: DHolder) { DROPS = DROPS + 1; let v = *self.r; } }")
            else
                add("impl Drop for DHolder { pub fn drop(self: DHolder) { let v = *self.r; } }")
            end
        end
    end
    for _, d in ipairs(P.cap_decls or {}) do
        add("")
        if d.k == "struct" then
            if lang == "rust" and string.find(d.want, "&") then
                add("struct " .. d.name .. "<'a> { p: " .. string.gsub(d.want, "&", "&'a ", 1) .. " }")
            else
                add("struct " .. d.name .. " { p: " .. d.want .. " }")
            end
        elseif d.ret then
            local have = ((lang == "rust") and "0 as *const i32") or "0 as *i32"
            add("fn " .. d.name .. "() -> " .. d.want .. " { return " .. have .. "; }")
        else
            add("fn " .. d.name .. "(p: " .. d.want .. ") -> i32 { return 0; }")
        end
    end
    add("")
    add("struct PRaw { p: *mut i32, tag: i32 }")
    return out
end

-- Z2: move a program's declarations into a library module. The Zoril side only: the Rust twin stays one file,
-- because a module boundary changes nothing `rustc` says about borrows (an inline `mod` would need every field
-- and method made `pub` for no added signal). `decls` is what `print_decls` wrote: imports stay in both files, and
-- every struct, enum, fn and static - with the `impl` blocks after them - becomes a `pub` item of the library,
-- imported by name into the module with `main`. Generic bodies, summaries and statics then cross a `.zri`.
-- Z3: the module names the generator draws from: every legal shape, and the names of standard-library modules.
local LIB_NAMES = { "lib", "_lib", "Lib", "lib2", "l_9", "_x", "io", "fmt", "hashmap", "args", "clone", "mem", "vec", "string" }
-- "3_trait_" is the shape A1 fixed: a digit-led name that holds the word `trait` (the corpus program `34_drop_trait`), which zilc read as a number and a declaration.
local ROOT_PREFIXES = { "p", "P", "_p", "7p", "p", "pP", "3_trait_" }
local CONTRACTS = {
    id_alias = "#[borrows(r)]", same_ref = "#[borrows(r)]", choose_ref = "#[borrows(r)]",
    first = "#[borrows(a)]", fst = "#[borrows(t)]", wrap = "#[borrows(r)]", get_prev = "#[borrows(l)]",
    fn_store_put = "#[stores(p -> h)]",
}
-- What a library module of Z2.1 adds to every split program: a private helper and a private `static` that public items
-- use, a public generic function and a public generic method that use them, and a user trait with a required and a
-- default method (the default calls the private helper), implemented here (`LxS`) and in `main` (`LxM`) and called
-- through a trait bound in `main`. These are the shapes whose bodies an importer instantiates, so everything they name
-- of the library has to be in its interface and linkable (the defects A7.3 and the Drop-linkage fix were).
local LX_LIB = {
    "fn lx_priv() -> i32 { return 3; }",
    "static mut LX_HITS: i32 = 0;",
    "pub fn lx_generic<T>(t: T) -> T { LX_HITS = LX_HITS + lx_priv(); return t; }",
    "pub fn lx_hits() -> i32 { return LX_HITS; }",
    -- Only the default methods name these two: a generic body that named them would carry them across the interface on
    -- its own, and the shape would not need the default method's bodies to be counted (A7.3).
    "fn lx_dpriv() -> i32 { return 3; }",
    "static mut LX_DHITS: i32 = 0;",
    "pub trait LxTrait {",
    "    fn lx_req(self: &Self) -> i32;",
    "    fn lx_def(self: &Self) -> i32 { return lx_dpriv() + self.lx_req(); }",
    "    fn lx_dhit(self: &Self) -> i32 { LX_DHITS = LX_DHITS + 1; return LX_DHITS; }",
    "}",
    "pub struct LxS { pub v: i32 }",
    "impl LxTrait for LxS { fn lx_req(self: &LxS) -> i32 { return self.v; } }",
    "pub struct LxBox<T> { pub v: T }",
    "impl<T> LxBox<T> { pub fn lx_pick<U>(self: &LxBox<T>, u: U) -> U { LX_HITS = LX_HITS + 1; return u; } }",
    -- A private trait implemented here for a public type: the interface carries the impl, so it must carry the
    -- trait (A7.4), and its default method is instantiated in `main` through the public generic `lx_priv_gen`.
    "fn lx_tpriv() -> i32 { return 2; }",
    "trait LxPriv { fn lx_p(self: &Self) -> i32; fn lx_pd(self: &Self) -> i32 { return lx_tpriv() + self.lx_p(); } }",
    "impl LxPriv for LxS { fn lx_p(self: &LxS) -> i32 { return self.v + 1; } }",
    "pub fn lx_priv_use(s: &LxS) -> i32 { return s.lx_pd(); }",
    "pub fn lx_priv_gen<T>(s: &LxS, t: T) -> i32 { return s.lx_pd(); }",
    -- The routes of A7.5-A7.11: each body below is instantiated by the importer and names a private item of this
    -- module, or is written into the interface in a form the importer has to parse.
    -- A7.5: a generic impl for a slice.
    "static mut LX_SK: i32 = 4;",
    "fn lx_sk() -> i32 { return LX_SK; }",
    "trait LxSl { fn lx_sl(self: &Self) -> i32; }",
    "impl<T> LxSl for [T] { fn lx_sl(self: &[T]) -> i32 { LX_SK = LX_SK + 0; return lx_sk() + (self.len as i32); } }",
    "pub fn lx_sl_use<T>(s: &[T]) -> i32 { return s.lx_sl(); }",
    -- A7.6: a generic `Drop` impl.
    "static mut LX_GD: i32 = 0;",
    "fn lx_gd_bump() { LX_GD = LX_GD + 1; }",
    "pub struct LxGuard<T> { pub v: T }",
    "impl<T> Drop for LxGuard<T> { fn drop(self: &mut LxGuard<T>) { LX_GD = LX_GD + 0; lx_gd_bump(); } }",
    "pub fn lx_gd_count() -> i32 { return LX_GD; }",
    -- A7.7: a public generic body reaching private items through a private generic helper, as a function and as a method.
    "static mut LX_CH: i32 = 10;",
    "fn lx_ch_leaf() -> i32 { return LX_CH; }",
    "fn lx_ch_mid<T>(x: T) -> i32 { LX_CH = LX_CH + 0; return lx_ch_leaf(); }",
    "pub fn lx_ch_pub<T>(x: T) -> i32 { return lx_ch_mid::<T>(x); }",
    "static mut LX_CM: i32 = 20;",
    "fn lx_cm_leaf() -> i32 { return LX_CM; }",
    "pub struct LxCh<T> { pub v: T }",
    "impl<T> LxCh<T> { fn lx_priv_get(self: &LxCh<T>) -> i32 { LX_CM = LX_CM + 0; return lx_cm_leaf(); } pub fn lx_pub_get(self: &LxCh<T>) -> i32 { return self.lx_priv_get(); } }",
    -- A7.8: impls on a specialization of a generic type (inherent, trait, `Drop`); A7.9: one written without `<T>`.
    "fn lx_sp_help() -> i32 { return 5; }",
    "pub struct LxSp<T> { pub v: T }",
    "impl LxSp<i32> { pub fn lx_sp_inh(self: &LxSp<i32>) -> i32 { return self.v + lx_sp_help(); } }",
    "pub trait LxSpT { fn lx_sp_f(self: &Self) -> i32; }",
    "impl LxSpT for LxSp<i32> { fn lx_sp_f(self: &LxSp<i32>) -> i32 { return self.v + 1; } }",
    "static mut LX_SPD: i32 = 0;",
    "pub struct LxSd<T> { pub v: T }",
    "impl Drop for LxSd<i32> { fn drop(self: &mut LxSd<i32>) { LX_SPD = LX_SPD + 1; } }",
    "pub fn lx_spd() -> i32 { return LX_SPD; }",
    "pub struct LxIm<T> { pub x: T }",
    "impl LxIm<T> { pub fn lx_im_get(self: &LxIm<T>) -> T { return self.x; } pub fn lx_im_five(self: &LxIm<T>) -> i32 { return lx_sp_help(); } }",
    -- A7.11: struct literals in the heads of `while`, `if`, `match` and `if let` of a generic body.
    "pub struct LxHp { pub x: i32 }",
    "pub fn lx_hd<T>(_t: T, y: i32) -> i32 { let mut n = 0; while (LxHp { x: n }).x < y { n = n + 1; } if (LxHp { x: n }).x == y { match (LxHp { x: y }).x { 0 => { return 0; }, _ => { return n; }, } } return 0 - 1; }",
    "pub enum LxHe { A(i32), B }",
    "pub struct LxHq { pub o: LxHe }",
    "pub fn lx_hd_let<T>(_t: T, y: i32) -> i32 { if let LxHe.A(v) = (LxHq { o: LxHe.A(y) }).o { return v; } return 0 - 1; }",
}
local LX_USE = "LxTrait, LxS, LxBox, lx_generic, lx_hits, lx_priv_use, lx_priv_gen, lx_sl_use, LxGuard, lx_gd_count, lx_ch_pub, LxCh, LxSp, LxSpT, LxSd, lx_spd, LxIm, lx_hd, lx_hd_let, LxHq"
local LX_MAIN_DECLS = {
    "struct LxM { v: i32 }",
    "impl LxTrait for LxM { fn lx_req(self: &LxM) -> i32 { return self.v; } }",
    "fn lx_via<X: LxTrait>(x: &X) -> i32 { return x.lx_def(); }",
}
local LX_MAIN_BODY = {
    "    {",
    "        let lx_s = LxS { v: 2 };",
    "        let lx_m = LxM { v: 4 };",
    "        let lx_b = LxBox { v: 1 };",
    "        let lx_1 = lx_via(&lx_s);",
    "        let lx_2 = lx_via(&lx_m);",
    "        let lx_3 = lx_generic::<i32>(9);",
    "        let lx_4 = lx_b.lx_pick(5);",
    "        let lx_5 = lx_m.lx_dhit();",
    "        let lx_6 = lx_s.lx_dhit();",
    "        let lx_7 = lx_priv_use(&lx_s);",
    "        let lx_8 = lx_priv_gen(&lx_s, 1);",
    "        let lx_a = [1, 2, 3];",
    "        let lx_9 = lx_sl_use::<i32>(&lx_a);",
    "        { let lx_g = LxGuard::<i32> { v: 1 }; }",
    "        let lx_10 = lx_ch_pub::<i32>(1);",
    "        let lx_cg = LxCh::<i32> { v: 1 };",
    "        let lx_11 = lx_cg.lx_pub_get();",
    "        let lx_sp = LxSp::<i32> { v: 40 };",
    "        let lx_12 = lx_sp.lx_sp_inh();",
    "        let lx_13 = lx_sp.lx_sp_f();",
    "        { let lx_d = LxSd::<i32> { v: 0 }; }",
    "        let lx_im = LxIm::<i32> { x: 42 };",
    "        let lx_14 = lx_im.lx_im_get();",
    "        let lx_15 = lx_im.lx_im_five();",
    "        let lx_16 = lx_hd::<i32>(0, 5);",
    "        let lx_17 = lx_hd_let::<i32>(0, 6);",
    "        if lx_9 != 7 || lx_gd_count() != 1 || lx_10 != 10 || lx_11 != 20 || lx_12 != 45 || lx_13 != 41 || lx_spd() != 1 || lx_14 != 42 || lx_15 != 5 || lx_16 != 5 || lx_17 != 6 { return 94; }",
    "        if lx_1 != 5 || lx_2 != 7 || lx_3 != 9 || lx_4 != 5 || lx_hits() != 4 || lx_5 != 1 || lx_6 != 2 || lx_7 != 5 || lx_8 != 5 { return 94; }",
    "    }",
}

-- True when TEXT names NAME as a word.
local function names_word(text, name)
    return text:find("%f[%w_]" .. name .. "%f[^%w_]") ~= nil
end

-- Z2: move a program's declarations into a library module. The Zoril side only: the Rust twin stays one file,
-- because a module boundary changes nothing `rustc` says about borrows (an inline `mod` would need every field
-- and method made `pub` for no added signal). `decls` is what `print_decls` wrote and `main_text` is the program's
-- `main`. Imports stay in both files. A struct, enum, fn or static that `main` names becomes a `pub` item of the
-- library, imported by name; one that only other library items name stays private (Z2.1), so a public body that
-- uses it is what carries it across the interface; one nothing names stays `pub` so it is not an unused private.
-- An `impl` block goes with the library.
local function split_decls(decls, libname, importpath, main_text)
    local main, lib = {}, {}
    local items = {}                      -- { name, lines = {...}, kind }
    local rest = {}                       -- library lines that are not items: impl blocks
    local block_end = nil
    local cur = nil                       -- an impl block being read: its lines go to REST
    local order = {}                      -- the library's lines in source order: { item = idx } or { text = line }
    for _, line in ipairs(decls) do
        if block_end then
            table.insert(order, { text = line }); table.insert(rest, line)
            if line == block_end then block_end = nil end
        elseif line:match("^import ") or line:match("^use ") or line == "" then
            table.insert(main, line); table.insert(order, { text = line })
        elseif line:match("^static mut ") or line:match("^struct ") or line:match("^enum ") or line:match("^fn ") then
            local name = line:match("^static mut ([%w_]+)") or line:match("^%a+ ([%w_]+)")
            local fname = line:match("^fn ([%w_]+)")
            table.insert(items, { name = name, line = line, contract = fname and CONTRACTS[fname], is_struct = line:match("^struct ") ~= nil })
            table.insert(order, { item = #items })
        else
            table.insert(order, { text = line }); table.insert(rest, line)
            if line:match("^impl ") and line:sub(-1) == "{" then block_end = "}" end
        end
    end
    for _, l in ipairs(LX_LIB) do table.insert(rest, l) end
    local names = {}
    for idx, it in ipairs(items) do
        local in_lib = false
        for _, r in ipairs(rest) do if names_word(r, it.name) then in_lib = true end end
        for jdx, other in ipairs(items) do
            if jdx ~= idx and names_word(other.line, it.name) then in_lib = true end
        end
        local in_main = names_word(main_text, it.name)
        -- Private when only the library names it; `main` reaches it through a public item.
        it.pub = in_main or not in_lib
        if it.pub then table.insert(names, it.name) end
    end
    for _, o in ipairs(order) do
        if o.text then
            table.insert(lib, o.text)
        else
            local it = items[o.item]
            local line = it.line
            if it.contract and it.pub then
                table.insert(lib, it.contract)
                P.tags["module-contract-attribute"] = true
            end
            if it.pub then
                -- Fields are private to their module unless marked `pub`: `main` builds and reads these structs.
                local head, fields, tail = line:match("^(struct [^{]*{ )(.*)( })$")
                if head then
                    local out_f, depth, start = {}, 0, 1
                    for pos = 1, #fields + 1 do
                        local c = fields:sub(pos, pos)
                        if c == "<" or c == "(" or c == "[" then depth = depth + 1
                        elseif c == ">" or c == ")" or c == "]" then depth = depth - 1
                        elseif pos == #fields + 1 or (c == "," and depth == 0) then
                            local f = fields:sub(start, pos - 1):gsub("^%s+", "")
                            if f ~= "" then table.insert(out_f, "pub " .. f) end
                            start = pos + 1
                        end
                    end
                    line = head .. table.concat(out_f, ", ") .. tail
                end
                table.insert(lib, "pub " .. line)
            else
                table.insert(lib, line)
                P.tags["library-private-item"] = true
            end
        end
    end
    for _, l in ipairs(LX_LIB) do table.insert(lib, l) end
    P.tags["user-trait-default-method"] = true
    P.tags["private-trait-impl"] = true
    P.tags["library-generic-impl-shapes"] = true
    P.tags["library-private-item"] = true
    table.insert(main, "import \"" .. importpath .. "\";")
    table.insert(main, "use " .. libname .. "::{" .. table.concat(names, ", ") .. (#names > 0 and ", " or "") .. LX_USE .. "};")
    for _, l in ipairs(LX_MAIN_DECLS) do table.insert(main, l) end
    return main, lib
end

local function print_program(body, lang)
    local out = {}
    local function add(s) table.insert(out, s) end
    add("// fuzz program: " .. tostring(P.features_hint))
    if P.calibration and next(P.calibration) then
        local ids = {}
        for id in pairs(P.calibration) do table.insert(ids, id) end
        table.sort(ids)
        add("// fuzz: calibration " .. table.concat(ids, ","))
    end
    if P.no_rustc_diff then add("// fuzz: no-rustc-diff") end
    -- `main` first, into its own list: whether a library item stays private depends on whether `main` names it.
    local mainl = {}
    local function addm(s2) table.insert(mainl, s2) end
    if lang == "rust" then
        addm("fn main() {")
        addm("    let hole_switch: bool = std::env::args().count() > 1;")
    else
        addm("fn main(argc: i32, _argv: **u8) -> i32 {")
        addm("    let hole_switch: bool = argc > 1;")
    end
    addm("    let mut x: i32 = " .. "3" .. ";")
    if lang ~= "rust" and P.expect then addm("    let mut chk: i32 = 0;") end
    -- Every generated local lives in this block, so it is dropped before the drop-count oracle at the
    -- end of `main` reads DROPS. The seed local `x` stays outside it for the reference builders.
    addm("    {")
    local stmts = print_stmts(body.stmts or {}, lang, "        ")
    for _, s2 in ipairs(stmts) do addm(s2) end
    if lang ~= "rust" and P.expect then
        for _, name in ipairs(P.expect.final) do addm("        chk = chk * 31 + " .. name .. ";") end
    end
    addm("    }")
    if lang ~= "rust" and P.split_lib then
        for _, l in ipairs(LX_MAIN_BODY) do addm(l) end
    end
    if lang ~= "rust" and P.expect then
        addm("    if chk != " .. tostring(P.expect.chk) .. " { return 93; }")
    end
    if P.needs_drop_counter and lang ~= "rust" then
        addm("    if DROPS != CONSTRUCTED { return 91; }")
    end
    if body.dynamic then print_dynamic(body.dynamic, lang, addm) end
    if lang ~= "rust" then addm("    return 0;") end
    addm("}")
    local decls = print_decls(lang)
    local lib_lines = nil
    if lang ~= "rust" and P.split_lib then
        decls, lib_lines = split_decls(decls, P.split_lib, P.split_import, table.concat(mainl, "\n"))
    end
    for _, d in ipairs(decls) do add(d) end
    add("")
    for _, l in ipairs(mainl) do add(l) end
    local lib_text = nil
    if lib_lines then lib_text = "// fuzz library module of " .. P.split_lib .. "\n" .. table.concat(lib_lines, "\n") .. "\n" end
    return table.concat(out, "\n") .. "\n", lib_text
end

--- Templates (the first version's fixed seed set) -------------------------------------------------

local TEMPLATES = {}
TEMPLATES["struct_ref"] = function()
    return "fn main() -> i32 {\n    let x: i32 = 5;\n    let h = Holder { a: 1, r: &x };\n    let v: i32 = read(&h);\n    return 0;\n}\n",
        "fn main() {\n    let x: i32 = 5;\n    let h = Holder { a: 1, r: &x };\n    let v: i32 = read(&h);\n    let _ = v;\n}\n", { "reference-in-struct-field" }
end
-- `raw_deref_through_container` used to live here. It was added when the shape was a hole - Zoril
-- used to accept the dereference - and it moved to the mismatch stream when the dereference
-- check landed: Zoril refuses that shape now, which is the mismatch stream's
-- expected outcome, while its Rust twin is a valid program. In the main stream it read as
-- "zoril rejects, rustc accepts", which the driver counts as a generator bug.

TEMPLATES["box_borrow"] = function()
    return "fn take(b: Box<i32>) -> i32 { return *b; }\n\nfn main() -> i32 {\n    let x: i32 = 7;\n    let v: i32 = take(&x);\n    return 0;\n}\n",
        "fn take(b: Box<i32>) -> i32 { return *b; }\n\nfn main() {\n    let x: i32 = 7;\n    let v: i32 = take(&x);\n    let _ = v;\n}\n", { "borrow-passed-as-owned-box" }
end
TEMPLATES["tuple_ref"] = function()
    return "fn main() -> i32 {\n    let x: i32 = 5;\n    let t = (1, &x);\n    let v: i32 = *t.1;\n    return 0;\n}\n",
        "fn main() {\n    let x: i32 = 5;\n    let t = (1, &x);\n    let v: i32 = *t.1;\n    let _ = v;\n}\n", { "reference-in-tuple" }
end
TEMPLATES["block_borrow"] = function()
    return "fn main() -> i32 {\n    let mut out: &i32 = &0;\n    {\n        let z: i32 = 9;\n        out = &z;\n    }\n    let v: i32 = *out;\n    return 0;\n}\n",
        "fn main() {\n    let mut out: &i32 = &0;\n    {\n        let z: i32 = 9;\n        out = &z;\n    }\n    let v: i32 = *out;\n    let _ = v;\n}\n", { "borrow-of-an-inner-local-kept-outside" }
end
TEMPLATES["call_forward"] = function()
    local z = "fn id<T>(t: T) -> T { return t; }\n\nfn fwd0(r: &i32) -> i32 { return *id(r); }\n\nfn fwd1(r: &i32) -> i32 { return *id(r) + 1; }\n\n"
    local m = "fn id<T>(t: T) -> T { return t; }\n\nfn fwd0(r: &i32) -> i32 { return *id(r); }\n\nfn fwd1(r: &i32) -> i32 { return *id(r) + 1; }\n\n"
    return z .. "fn main() -> i32 {\n    let x: i32 = 11;\n    let v: i32 = fwd1(&x);\n    return 0;\n}\n",
        m .. "fn main() {\n    let x: i32 = 11;\n    let v: i32 = fwd1(&x);\n    let _ = v;\n}\n", { "reference-forwarding-helper" }
end
TEMPLATES["match_bind"] = function()
    local decl_z = "enum Option<T> { Some(T), None }\n\n"
    return decl_z .. "fn main() -> i32 {\n    let x: i32 = 13;\n    let o: Option<&i32> = Option.Some(&x);\n    let v: i32 = match o { Option.Some(r) => *r, Option.None => 0 };\n    return 0;\n}\n",
        "fn main() {\n    let x: i32 = 13;\n    let o: Option<&i32> = Some(&x);\n    let v: i32 = match o { Some(r) => *r, None => 0 };\n    let _ = v;\n}\n", { "match-binding-through-reference", "option-of-reference" }
end
TEMPLATES["drop_struct"] = function()
    local pre_z = "struct DHolder { r: &i32 }\nimpl Drop for DHolder { pub fn drop(self: DHolder) { let v = *self.r; } }\n\n"
    local pre_r = "struct DHolder<'a> { r: &'a i32 }\nimpl<'a> Drop for DHolder<'a> { fn drop(&mut self) { let _v = *self.r; } }\n\n"
    return pre_z .. "fn main() -> i32 {\n    let x: i32 = 17;\n    let h: DHolder = DHolder { r: &x };\n    return 0;\n}\n",
        pre_r .. "fn main() {\n    let x: i32 = 17;\n    let h: DHolder<'_> = DHolder { r: &x };\n    let _ = h;\n}\n", { "drop-type-holding-a-reference" }
end
TEMPLATES["raw_container"] = function()
    local pre = "struct PRaw { p: *mut i32, tag: i32 }\n\nfn fst(s: &PRaw) -> *mut i32 { return s.p; }\n\n"
    return pre .. "fn main() -> i32 {\n    let p = 0 as *mut i32;\n    let s: PRaw = PRaw { p: p, tag: 1 };\n    let q = fst(&s);\n    return 0;\n}\n",
        pre .. "fn main() {\n    let p = 0 as *mut i32;\n    let s: PRaw = PRaw { p: p, tag: 1 };\n    let q = fst(&s);\n    let _ = q;\n}\n", { "raw-pointer-value-in-a-struct" }
end
TEMPLATES["loop_borrow"] = function()
    return "fn main() -> i32 {\n    let x: i32 = 23;\n    let mut total: i32 = 0;\n    let mut i: i32 = 0;\n    while i < 3 {\n        let r: &i32 = &x;\n        total = total + *r;\n        i = i + 1;\n    }\n    return 0;\n}\n",
        "fn main() {\n    let x: i32 = 23;\n    let mut total: i32 = 0;\n    let mut i: i32 = 0;\n    while i < 3 {\n        let r: &i32 = &x;\n        total = total + *r;\n        i = i + 1;\n    }\n    let _ = total;\n}\n", { "borrow-inside-a-loop" }
end
TEMPLATES["box_into_borrow"] = function()
    return "fn bump(r: &i32) -> i32 { return *r + 1; }\n\nfn main() -> i32 {\n    let b = box 41;\n    let v: i32 = bump(b);\n    return 0;\n}\n",
        "fn bump(r: &i32) -> i32 { return *r + 1; }\n\nfn main() {\n    let b = Box::new(41);\n    let v: i32 = bump(b);\n    let _ = v;\n}\n", { "owned-box-passed-as-borrow" }
end

-- Z2: a type in one module, an `impl` for it in a second, a generic standard-library method instantiated in the
-- first, all used from `main`. The Rust twin is one file: the module split is Zoril's, and what `rustc` says
-- about the program does not depend on it.
TEMPLATES["xmod_impl"] = function(base)
    local lib, ext = "pt_types", "pt_impl"
    local libs = {
        [lib .. ".zrl"] = "// fuzz library module of " .. base .. "\nimport \"vec.zrl\";\nuse vec::Vec;\n\npub struct Pt { pub x: i32, pub y: i32 }\n\n"
            .. "pub fn mk(n: i32) -> Vec<i32> { let mut v: Vec<i32> = Vec::<i32>.new(); v.push(n); return v; }\n",
        [ext .. ".zrl"] = "// fuzz library module of " .. base .. "\nimport \"" .. lib .. ".zrl\";\nuse " .. lib .. "::{Pt};\n\n"
            .. "impl Pt { pub fn sum(self: &Pt) -> i32 { return self.x + self.y; } }\n",
    }
    local z = "import \"vec.zrl\";\nuse vec::Vec;\nimport \"" .. base .. ".d/" .. lib .. ".zrl\";\nimport \"" .. base .. ".d/" .. ext .. ".zrl\";\nuse " .. lib .. "::{Pt, mk};\n\n"
        .. "fn main() -> i32 {\n    let p: Pt = Pt { x: 1, y: 2 };\n    let s: i32 = p.sum();\n    let v: Vec<i32> = mk(s);\n    if v.len() != 1 as usize { return 1; }\n    return 0;\n}\n"
    local r = "struct Pt { x: i32, y: i32 }\nimpl Pt { fn sum(&self) -> i32 { self.x + self.y } }\nfn mk(n: i32) -> Vec<i32> { let mut v: Vec<i32> = Vec::new(); v.push(n); v }\n\n"
        .. "fn main() {\n    let p: Pt = Pt { x: 1, y: 2 };\n    let s: i32 = p.sum();\n    let v: Vec<i32> = mk(s);\n    let _ = v.len();\n}\n"
    return z, r, { "multi-module", "impl-in-another-module" }, libs
end

--- Main ------------------------------------------------------------------------------------------

parse_args()
rng_seed(seed)
os.execute("mkdir -p '" .. outdir .. "'")

local function write(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
end

local made = {}
local function emit(stem, zrl, rs, tags, lib)
    write(stem .. ".zrl", zrl)
    -- Library modules sit in `<stem>.d/`, one directory per program, so a module may take any name (`io`, `Lib`)
    -- without two programs of one seed directory colliding on it. `lib` maps a path under that directory to its text.
    for rel, text in pairs(lib or {}) do
        local path = stem .. ".d/" .. rel
        os.execute("mkdir -p '" .. string.match(path, "^(.*)/[^/]*$") .. "'")
        write(path, text)
    end
    write(stem .. ".rs", rs)
    table.insert(made, { stem = stem, tags = tags })
end

-- The mismatch stream: one shape per program and nothing else, so a reader can see the construct that
-- was refused without reading past it. Emitted into its own directory (`<out>/mismatch/`), which is how
-- the driver tells the two streams apart, and every shape appears exactly once - it is a fixed
-- checklist rather than a sample, because the point is that each capability mismatch is *exercised*.
local function print_mismatch_program(fam, pos, free, lang, node)
    local out = {}
    local function add(s) table.insert(out, s) end
    local have = (lang == "rust") and (fam.r_free or fam.r) or (fam.z_free or fam.z)
    if free then have = (lang == "rust") and fam.r_free or fam.z_free end
    if not free then have = (lang == "rust") and fam.r or fam.z end
    add("// fuzz program: capability mismatch, " .. fam.t .. " " .. pos)
    for _, d in ipairs(P.cap_decls or {}) do
        if d.k == "struct" then
            if lang == "rust" and string.find(d.want, "&") then
                add("struct " .. d.name .. "<'a> { p: " .. string.gsub(d.want, "&", "&'a ", 1) .. " }")
            else
                add("struct " .. d.name .. " { p: " .. d.want .. " }")
            end
        elseif d.ret then
            add("fn " .. d.name .. "() -> " .. d.want .. " { return " .. have .. "; }")
        else
            add("fn " .. d.name .. "(p: " .. d.want .. ") -> i32 { return 0; }")
        end
        add("")
    end
    if lang == "rust" then add("fn main() {") else add("fn main() -> i32 {") end
    add("    let mut x: i32 = 3;")
    for _, s in ipairs(print_stmts({ node }, lang, "    ")) do
        add(s)
    end
    if lang ~= "rust" then add("    return 0;") end
    add("}")
    return table.concat(out, "\n") .. "\n"
end

-- The calibration stream: one program per known hole, in its own directory so a run of it is a
-- measurement rather than a sample. Every program is expected to exit 91, 92 or 139 today, and to be
-- refused by a fixed compiler; `scripts/fuzz_calibrate.sh` checks the first half.
local function emit_calibration()
    os.execute("mkdir -p " .. outdir .. "/calibration")
    for i, h in ipairs(HOLES) do
        P = { n = 0, locals = {}, tags = {}, helpers = {}, has_holders = false, has_tup = false, calibration = {} }
        if h.setup then h.setup(P) end
        calibration(h.id)
        for _, t in ipairs(h.tags) do P.tags[t] = true end
        P.features_hint = "calibration, " .. h.id
        P.no_rustc_diff = h.no_rustc
        local body = { stmts = { { k = "Raw", z = guard_hole(h.z), r = guard_hole(h.r) } } }
        local stem = string.format("%s/calibration/c%02d_%s", outdir, i, h.id)
        local tags = {}
        for t in pairs(P.tags) do table.insert(tags, t) end
        table.sort(tags)
        emit(stem, print_program(body, "zoril"), print_program(body, "rust"), tags)
        local m = made[#made]
        print(table.concat(m.tags, ",") .. " " .. m.stem .. " 0 0")
    end
end

if mode == "mix" or mode == "mismatch" then
    os.execute("mkdir -p " .. outdir .. "/mismatch")
    for si, shape in ipairs(cap_shapes()) do
        P = { n = 0, locals = {}, tags = {}, helpers = {}, cap_decls = {} }
        local node = STMT.capability_mismatch(shape.fam, shape.pos, shape.free)
        local tags = {}
        for t in pairs(P.tags) do table.insert(tags, t) end
        table.sort(tags)
        emit(string.format("%s/mismatch/p%d_%d_mismatch_%s_%s", outdir, seed, si, shape.fam.t, shape.pos),
            print_mismatch_program(shape.fam, shape.pos, shape.free, "zoril", node),
            print_mismatch_program(shape.fam, shape.pos, shape.free, "rust", node), tags)
        local m = made[#made]
        print(table.concat(m.tags, ",") .. " " .. m.stem)
    end
    emit(outdir .. "/mismatch/p" .. seed .. "_raw-deref-through-a-container",
        "// fuzz program: raw-pointer-dereferenced-through-a-container\n" .. RAW_DEREF_Z,
        "// fuzz twin of raw-pointer-dereferenced-through-a-container\n" .. RAW_DEREF_R,
        { "capability-mismatch", "capability-mismatch-raw-deref-through-a-container",
          "raw-pointer-dereferenced-through-a-container" })
    local mr = made[#made]
    print(table.concat(mr.tags, ",") .. " " .. mr.stem .. " 0 0")
    -- Z2: a private item named from another module is refused, in the whole-program build and under `zbuild`
    -- alike (the mode-diff reading compares the two diagnostics). The twin is one file, where the item is simply
    -- in scope: a valid program, as every mismatch twin is.
    do
        local base = "p" .. seed .. "_private_item_across_modules"
        local lib = "private_lib"
        local libs = { [lib .. ".zrl"] = "// fuzz library module of " .. base .. "\nfn hidden() -> i32 { return 1; }\n" }
        local z = "// fuzz program: a private function of another module\nimport \"" .. base .. ".d/" .. lib .. ".zrl\";\nuse " .. lib .. "::{hidden};\n\n"
            .. "fn main() -> i32 {\n    let v: i32 = hidden();\n    return 0;\n}\n"
        local r = "// fuzz twin of a private function of another module\nfn hidden() -> i32 { return 1; }\n\nfn main() {\n    let v: i32 = hidden();\n    let _ = v;\n}\n"
        emit(outdir .. "/mismatch/" .. base, z, r, { "multi-module", "private-item-across-modules" }, libs)
        local mp = made[#made]
        print(table.concat(mp.tags, ",") .. " " .. mp.stem .. " 0 0")
    end
    -- A7.10: `box(allocator) expr` is refused where it is instantiated, and an interface that dropped the allocator
    -- would let `zbuild` allocate on the heap what the whole-program build refuses. Both builds must refuse it, with
    -- the same first diagnostic (the mode-diff reading).
    do
        local base = "p" .. seed .. "_box_allocator_in_interface"
        local lib = "box_lib"
        local libs = { [lib .. ".zrl"] = "// fuzz library module of " .. base .. "\npub fn make_in<T>(alloc: i32, v: T) -> Box<T> { return box(alloc) v; }\n" }
        local z = "// fuzz program: box(allocator) in an imported generic function\nimport \"" .. base .. ".d/" .. lib .. ".zrl\";\n\n"
            .. "fn main() -> i32 {\n    let b = " .. lib .. "::make_in::<i32>(0, 42);\n    return *b - 42;\n}\n"
        local r = "// fuzz twin of box(allocator) in an imported generic function\nfn main() {\n}\n"
        emit(outdir .. "/mismatch/" .. base, z, r, { "multi-module", "box-allocator-in-interface" }, libs)
        local mb = made[#made]
        print(table.concat(mb.tags, ",") .. " " .. mb.stem .. " 0 0")
    end
    -- Z5: the contract of a generic standard-library method crosses a `.zri`. `Vec::clone_in`'s result is tied to its
    -- target arena, so it cannot live across that arena's `reset`; under `zbuild` the standard library is an imported
    -- interface, and an interface that loses a generic body's `#[borrows]` accepts this (the defect A2 fixed, probe
    -- 194). Every run therefore carries it, and the mode-diff reading compares the two builds' refusals.
    do
        local base = "p" .. seed .. "_stdlib_contract_clone_in"
        local z = "// fuzz program: a generic standard-library method's contract across an interface\n"
            .. "import \"mem.zrl\";\nimport \"vec.zrl\";\nuse mem::Arena;\nuse vec::Vec;\n\n"
            .. "fn main() -> i32 {\n    let mut a1 = Arena.new(4096 as u64).unwrap();\n    let mut a2 = Arena.new(4096 as u64).unwrap();\n"
            .. "    let mut v = Vec::<i32>.new_in(&a1);\n    v.push(42);\n    let v2 = v.clone_in(&a2);\n    a2.reset();\n    return v2.len() as i32;\n}\n"
        local r = "// fuzz twin of a generic standard-library method's contract\nfn main() {\n}\n"
        emit(outdir .. "/mismatch/" .. base, z, r, { "stdlib-generic-contract" }, nil)
        local ms = made[#made]
        print(table.concat(ms.tags, ",") .. " " .. ms.stem .. " 0 0")
    end
    -- Z3: a module whose file name is not an identifier is refused at the `import`, `as` or not (A4), by both
    -- builds with the same diagnostic: a leading digit, a `-`, a keyword. The twin has no such module.
    for _, bad in ipairs({ "9lib", "my-mod", "while" }) do
        local base = "p" .. seed .. "_bad_module_name_" .. (bad:gsub("[^%w]", "_"))
        local libs = { [bad .. ".zrl"] = "// fuzz library module of " .. base .. "\npub fn f() -> i32 { return 1; }\n" }
        local z = "// fuzz program: an import whose module name is not an identifier\nimport \"" .. base .. ".d/" .. bad .. ".zrl\";\n\nfn main() -> i32 {\n    return 0;\n}\n"
        local r = "// fuzz twin of a bad module name\nfn main() {\n}\n"
        emit(outdir .. "/mismatch/" .. base, z, r, { "multi-module", "module-name-not-an-identifier" }, libs)
        local mb = made[#made]
        print(table.concat(mb.tags, ",") .. " " .. mb.stem .. " 0 0")
    end
    -- The raw-pointer *pattern* holes ride the mismatch stream too: each is a shape the compiler must
    -- refuse, and one that is accepted is a finding on its own (probe 216/217). They are also in the
    -- calibration stream, where the crash oracle is what observes them.
    for _, id in ipairs({ "raw_tuple_pattern_deref", "raw_enum_pattern_deref", "owning_move_before_borrow_use" }) do
        local h
        for _, cand in ipairs(HOLES) do if cand.id == id then h = cand end end
        P = { n = 0, locals = {}, tags = {}, helpers = {}, has_holders = false, has_tup = false, calibration = {} }
        if h.setup then h.setup(P) end
        calibration(h.id)
        for _, t in ipairs(h.tags) do P.tags[t] = true end
        P.features_hint = "mismatch, " .. h.id
        local body = { stmts = { { k = "Raw", z = guard_hole(h.z), r = guard_hole(h.r) } } }
        emit(string.format("%s/mismatch/p%d_%s", outdir, seed, id),
            print_program(body, "zoril"), print_program(body, "rust"), (function()
                local tags = {}
                for t in pairs(P.tags) do table.insert(tags, t) end
                table.sort(tags)
                return tags
            end)())
        local mm = made[#made]
        print(table.concat(mm.tags, ",") .. " " .. mm.stem .. " 0 0")
    end
end

-- `mix` carries the fixed calibration stream once, in its own directory, instead of appending a hole
-- to every generated program: a program that carries a hole has to be told apart from the search, and
-- appending one to every program made every generated fault look like a known hole. The random hole
-- builders below reach the same constructs in the ordinary grammar.
if mode == "calibration" or (mode == "mix" and holes == 1) then emit_calibration() end

if mode ~= "mismatch" and mode ~= "calibration" then
    for i = 0, count - 1 do
        local expect_field = "none"
        local trap_field = "trap=none"
        local swarm_field = "swarm=none"
        local use_template = false
        if mode == "templates" then use_template = true
        elseif (mode == "both" or mode == "mix") and rnd(4) == 1 then use_template = true end
        local stem_full = string.format("%s/p%d_%d", outdir, seed, i)
        if use_template then
            local names = {}
            for k in pairs(TEMPLATES) do table.insert(names, k) end
            table.sort(names)
            local nm = names[rnd(#names)]
            -- The struct template needs its declarations.
            local zpre = ""
            local rpre = ""
            if nm == "struct_ref" then
                zpre = "struct Holder { a: i32, r: &i32 }\nfn read(h: &Holder) -> i32 { return h.a + *h.r; }\n\n"
                rpre = "struct Holder<'a> { a: i32, r: &'a i32 }\nfn read(h: &Holder) -> i32 { return h.a + *h.r; }\n\n"
            end
            local base = string.match(stem_full, "([^/]+)$") .. "_tpl_" .. nm
            local z, r, tags, libs = TEMPLATES[nm](base)
            emit(stem_full .. "_tpl_" .. nm, "// fuzz template: " .. nm .. "\n" .. zpre .. z,
                "// fuzz twin of " .. nm .. "\n" .. rpre .. r, tags, libs)
        else
            local body = build_program()
            P.features_hint = "compositional, seed " .. seed .. ", program " .. i
            P.no_rustc_diff = false
            for _, s in ipairs(body.stmts) do
                if s.k == "Raw" and s.no_rustc then P.no_rustc_diff = true end
            end
            -- What the program should compute, from the tree. Decided before printing: the printer adds
            -- the checksum only when the interpreter could follow every statement.
            local ex, why = evaluate(body)
            P.expect = ex
            P.trap_code = nil
            add_dynamic_check(body, ex)
            expect_field = ex and "checked" or ("unchecked:" .. string.gsub(tostring(why), "[^%w_]+", "_"))
            trap_field = P.trap_code and ("trap=" .. P.trap_code) or "trap=none"
            swarm_field = (P.swarm_off and #P.swarm_off > 0) and ("swarm=off:" .. table.concat(P.swarm_off, ",")) or "swarm=all"
            P.split_lib = nil
            -- The root program may be named anything - a leading digit too, which nothing names - so every compositional
            -- program takes its stem from ROOT_PREFIXES. A digit-led root with helpers and types of its own is what A1
            -- fixed under `zbuild` (the ZIL names a function by the module stem); the split programs keep theirs in a
            -- library, so the unsplit ones are where it matters. The driver reads the stem from the manifest.
            local root = ROOT_PREFIXES[((seed * 5 + i * 11) % #ROOT_PREFIXES) + 1]
            local stem = string.format("%s/%s%d_%d_gen", outdir, root, seed, i)
            if root:match("^%d") then tag("root-name-leading-digit") end
            if split_pct > 0 and ((seed * 31 + i * 17) % 100) < split_pct then
                -- Names (Z3). The library takes any identifier the importer accepts: a leading underscore, capitals,
                -- digits after the first character, and the name of a standard-library module the program does not
                -- itself import (it would import itself). The root program may be named anything - a leading digit
                -- too, which nothing names - so its stem is varied as well; the driver reads the stem from the manifest.
                local taken = {}
                if P.needs_arena then taken.mem = true; taken.vec = true end
                if P.needs_string_view then taken.string = true end
                local lib_names = {}
                for _, nm in ipairs(LIB_NAMES) do if not taken[nm] then table.insert(lib_names, nm) end end
                local pick = ((seed * 7 + i * 13) % #lib_names) + 1
                P.split_lib = lib_names[pick]
                P.split_import = string.match(stem, "([^/]+)$") .. ".d/" .. P.split_lib .. ".zrl"
                tag("multi-module")
                if P.split_lib:match("^_") or P.split_lib:match("%u") or P.split_lib:match("%d") then tag("module-name-shape") end
            end
            local z, zlib = print_program(body, "zoril")
            local r = print_program(body, "rust")
            local tags = {}
            for t in pairs(P.tags) do table.insert(tags, t) end
            table.sort(tags)
            emit(stem, z, r, tags, zlib and { [P.split_lib .. ".zrl"] = zlib } or nil)
        end
        local m = made[#made]
        local taglist = {}
        for _, t in ipairs(m.tags) do table.insert(taglist, t) end
        print(table.concat(taglist, ",") .. " " .. m.stem .. " " .. owns_count() .. " " .. ((P and P.locals) and #P.locals or 0) .. " " .. expect_field .. " " .. trap_field .. " " .. swarm_field)
    end
end
