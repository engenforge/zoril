-- Procedural multi-file code generator for cross-language benchmarking
-- Generates per-language algorithmic multi-file projects for Zoril, Zig, Rust, and Hare.
--
-- Every language gets the same program shape: the same number of modules, each with the same
-- number of functions, so clean build, rebuild times and peak memory are comparable across
-- compilers. LOC still differs by about 1.3x, because a generated function is 9-12 lines
-- depending on the language (measured 2026-10-10: 11.7 Zoril, 10.7 Zig, 9.2 Rust, 9.1 Hare).
--
-- Default size (equal for every language, ~30k LOC):
--   Zoril / Zig / Rust / Hare: 100 modules x 30 funcs (3000 fns)
--
-- Override every language with --modules / --funcs, or one with --<lang>-modules /
-- --<lang>-funcs. The regression gate in scripts/bench_cross_lang.sh pins a smaller Zoril size
-- of its own (bench/cross_lang/thresholds.cfg records it, and why), and the size sweep in
-- scripts/bench_cross_lang.sh varies this one.

local default_modules = nil
local default_funcs   = nil

local cfg = {
    zoril = { modules = 100, funcs = 30 },
    zig   = { modules = 100, funcs = 30 },
    rust  = { modules = 100, funcs = 30 },
    hare  = { modules = 100, funcs = 30 },
}

local out_base = "build/bench/multifile"

local action = nil
local action_target = nil

-- Program shape. "flat" is what this generator has always emitted: main calls every generated
-- function in one straight line, which is what makes a clean build of it hostile to whole-module
-- optimization (Zig ReleaseFast and ReleaseSafe run past 30 minutes at 30k LOC; rustc's release
-- profile aborts in LLVM). "tree" is the realistic shape: each module's driver calls its own
-- functions and main calls the drivers, so an optimizer works on a call tree. The optimized
-- comparison in scripts/bench_cross_lang.sh uses "tree"; the unoptimized one uses "flat", which
-- every compiler handles quickly. --shape tree|flat selects it.
local shape = "flat"

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--out-dir" and arg[i+1] then
        out_base = arg[i+1]; i = i + 2
    elseif a == "--modules" and arg[i+1] then
        default_modules = tonumber(arg[i+1]); i = i + 2
    elseif a == "--funcs" and arg[i+1] then
        default_funcs = tonumber(arg[i+1]); i = i + 2
    elseif a == "--zoril-modules" and arg[i+1] then
        cfg.zoril.modules = tonumber(arg[i+1]); i = i + 2
    elseif a == "--zoril-funcs" and arg[i+1] then
        cfg.zoril.funcs = tonumber(arg[i+1]); i = i + 2
    elseif a == "--zig-modules" and arg[i+1] then
        cfg.zig.modules = tonumber(arg[i+1]); i = i + 2
    elseif a == "--zig-funcs" and arg[i+1] then
        cfg.zig.funcs = tonumber(arg[i+1]); i = i + 2
    elseif a == "--rust-modules" and arg[i+1] then
        cfg.rust.modules = tonumber(arg[i+1]); i = i + 2
    elseif a == "--rust-funcs" and arg[i+1] then
        cfg.rust.funcs = tonumber(arg[i+1]); i = i + 2
    elseif a == "--hare-modules" and arg[i+1] then
        cfg.hare.modules = tonumber(arg[i+1]); i = i + 2
    elseif a == "--hare-funcs" and arg[i+1] then
        cfg.hare.funcs = tonumber(arg[i+1]); i = i + 2
    elseif a == "--shape" and arg[i+1] then
        if arg[i+1] ~= "flat" and arg[i+1] ~= "tree" then
            error("--shape takes flat or tree, not " .. tostring(arg[i+1]))
        end
        shape = arg[i+1]; i = i + 2
    elseif (a == "--toggle-body" or a == "--edit-body") and arg[i+1] then
        action = "toggle-body"; action_target = arg[i+1]; i = i + 2
    elseif (a == "--toggle-sig" or a == "--edit-sig") and arg[i+1] then
        action = "toggle-sig"; action_target = arg[i+1]; i = i + 2
    elseif a == "--revert" and arg[i+1] then
        action = "revert"; action_target = arg[i+1]; i = i + 2
    else
        i = i + 1
    end
end

local function read_file(path)
    local f, err = io.open(path, "r")
    if not f then error(string.format("failed to open %s for reading: %s", path, tostring(err))) end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then error(string.format("failed to open %s for writing: %s", path, tostring(err))) end
    f:write(content)
    f:close()
end

local function toggle_body(lang)
    if lang == "all" then
        toggle_body("zoril")
        toggle_body("zig")
        toggle_body("rust")
        toggle_body("hare")
        return
    end
    if lang == "zoril" then
        local p = out_base .. "/zoril/mod0.zrl"
        local s = read_file(p)
        if s:find("val %+ 100 as i64") then
            s = s:gsub("val %+ 100 as i64", "val + 101 as i64", 1)
        elseif s:find("val %+ 101 as i64") then
            s = s:gsub("val %+ 101 as i64", "val + 100 as i64", 1)
        else
            error("toggle_body: target pattern not found in " .. p)
        end
        write_file(p, s)
    elseif lang == "zig" then
        local p = out_base .. "/zig/mod0.zig"
        local s = read_file(p)
        if s:find("val %+ 100;") then
            s = s:gsub("val %+ 100;", "val + 101;", 1)
        elseif s:find("val %+ 101;") then
            s = s:gsub("val %+ 101;", "val + 100;", 1)
        else
            error("toggle_body: target pattern not found in " .. p)
        end
        write_file(p, s)
    elseif lang == "rust" then
        local p = out_base .. "/rust/src/mod0.rs"
        local s = read_file(p)
        if s:find("wrapping_add%(100%)") then
            s = s:gsub("wrapping_add%(100%)", "wrapping_add(101)", 1)
        elseif s:find("wrapping_add%(101%)") then
            s = s:gsub("wrapping_add%(101%)", "wrapping_add(100)", 1)
        else
            error("toggle_body: target pattern not found in " .. p)
        end
        write_file(p, s)
    elseif lang == "hare" then
        local p = out_base .. "/hare/mod0/mod0.ha"
        local s = read_file(p)
        if s:find("val %+ 100;") then
            s = s:gsub("val %+ 100;", "val + 101;", 1)
        elseif s:find("val %+ 101;") then
            s = s:gsub("val %+ 101;", "val + 100;", 1)
        else
            error("toggle_body: target pattern not found in " .. p)
        end
        write_file(p, s)
    else
        error("unknown language for toggle-body: " .. tostring(lang))
    end
end

local function toggle_sig(lang)
    if lang == "all" or lang == "zoril" then
        local p_m0 = out_base .. "/zoril/mod0.zrl"
        local p_main = out_base .. "/zoril/main.zrl"
        local s_m0 = read_file(p_m0)
        local s_main = read_file(p_main)
        if s_m0:find("pub fn calc_m0_f0%(val: i64%) %-> i64") then
            s_m0 = s_m0:gsub("pub fn calc_m0_f0%(val: i64%) %-> i64", "pub fn calc_m0_f0(val: i64, extra: i64) -> i64", 1)
            s_main = s_main:gsub("calc_m0_f0%(sum %% 100 as i64%)", "calc_m0_f0(sum %% 100 as i64, 1 as i64)", 1)
        elseif s_m0:find("pub fn calc_m0_f0%(val: i64, extra: i64%) %-> i64") then
            s_m0 = s_m0:gsub("pub fn calc_m0_f0%(val: i64, extra: i64%) %-> i64", "pub fn calc_m0_f0(val: i64) -> i64", 1)
            s_main = s_main:gsub("calc_m0_f0%(sum %% 100 as i64, 1 as i64%)", "calc_m0_f0(sum %% 100 as i64)", 1)
        else
            error("toggle_sig: target pattern not found in " .. p_m0)
        end
        write_file(p_m0, s_m0)
        write_file(p_main, s_main)
    else
        error("toggle-sig not supported for language: " .. tostring(lang))
    end
end

local function revert(lang)
    if lang == "all" then
        revert("zoril")
        revert("zig")
        revert("rust")
        revert("hare")
        return
    end
    if lang == "zoril" then
        local p_m0 = out_base .. "/zoril/mod0.zrl"
        local p_main = out_base .. "/zoril/main.zrl"
        local s_m0 = read_file(p_m0)
        local s_main = read_file(p_main)
        s_m0 = s_m0:gsub("val %+ 101 as i64", "val + 100 as i64")
        s_m0 = s_m0:gsub("pub fn calc_m0_f0%(val: i64, extra: i64%) %-> i64", "pub fn calc_m0_f0(val: i64) -> i64")
        s_main = s_main:gsub("calc_m0_f0%(sum %% 100 as i64, 1 as i64%)", "calc_m0_f0(sum %% 100 as i64)")
        write_file(p_m0, s_m0)
        write_file(p_main, s_main)
    elseif lang == "zig" then
        local p = out_base .. "/zig/mod0.zig"
        local s = read_file(p)
        s = s:gsub("val %+ 101;", "val + 100;")
        write_file(p, s)
    elseif lang == "rust" then
        local p = out_base .. "/rust/src/mod0.rs"
        local s = read_file(p)
        s = s:gsub("wrapping_add%(101%)", "wrapping_add(100)")
        write_file(p, s)
    elseif lang == "hare" then
        local p = out_base .. "/hare/mod0/mod0.ha"
        local s = read_file(p)
        s = s:gsub("val %+ 101;", "val + 100;")
        write_file(p, s)
    end
end

if action == "toggle-body" then
    toggle_body(action_target)
    os.exit(0)
elseif action == "toggle-sig" then
    toggle_sig(action_target)
    os.exit(0)
elseif action == "revert" then
    revert(action_target)
    os.exit(0)
end

-- Apply shared overrides if provided
if default_modules then
    for _, c in pairs(cfg) do c.modules = default_modules end
end
if default_funcs then
    for _, c in pairs(cfg) do c.funcs = default_funcs end
end

local function ensure_dir(d)
    os.execute("mkdir -p " .. d)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Generator: Zoril
-- ──────────────────────────────────────────────────────────────────────────────
local zoril_dir = out_base .. "/zoril"
ensure_dir(zoril_dir)
local zoril_loc = 0
local znm = cfg.zoril.modules
local znf = cfg.zoril.funcs

for m = 0, znm - 1 do
    local f = assert(io.open(zoril_dir .. string.format("/mod%d.zrl", m), "w"))
    f:write(string.format("pub struct State_m%d {\n    pub x: i64,\n    pub y: i64,\n    pub z: i64,\n}\n\n", m)); zoril_loc = zoril_loc + 6
    for fn_idx = 0, znf - 1 do
        local fn_name = string.format("calc_m%d_f%d", m, fn_idx)
        local base_add = (m + 1) * 100 + fn_idx * 7
        f:write(string.format("pub fn %s(val: i64) -> i64 {\n", fn_name)); zoril_loc = zoril_loc + 1
        f:write(string.format("    let mut acc: i64 = val + %d as i64;\n", base_add)); zoril_loc = zoril_loc + 1
        f:write("    let mut i: i64 = 0 as i64;\n"); zoril_loc = zoril_loc + 1
        f:write("    while i < 20 as i64 {\n"); zoril_loc = zoril_loc + 1
        f:write(string.format("        acc = (acc * 31 as i64 + i + %d as i64) %% 1000000007 as i64;\n", fn_idx + 1)); zoril_loc = zoril_loc + 1
        f:write("        i = i + 1 as i64;\n"); zoril_loc = zoril_loc + 1
        f:write("    }\n"); zoril_loc = zoril_loc + 1
        f:write("    return acc;\n"); zoril_loc = zoril_loc + 1
        f:write("}\n\n"); zoril_loc = zoril_loc + 2
    end
    if shape == "tree" then
        -- The module's driver calls its own functions, so main calls M drivers rather than M*N
        -- leaves and an optimizing compiler sees a call tree (see --shape above).
        f:write(string.format("pub fn run_m%d(val: i64) -> i64 {\n", m)); zoril_loc = zoril_loc + 1
        f:write("    let mut acc: i64 = val;\n"); zoril_loc = zoril_loc + 1
        for fn_idx = 0, znf - 1 do
            f:write(string.format("    acc = calc_m%d_f%d(acc);\n", m, fn_idx)); zoril_loc = zoril_loc + 1
        end
        f:write("    return acc;\n}\n\n"); zoril_loc = zoril_loc + 3
    end
    f:close()
end

local f_zm = assert(io.open(zoril_dir .. "/main.zrl", "w"))
for m = 0, znm - 1 do f_zm:write(string.format('import "mod%d.zrl";\n', m)) end
zoril_loc = zoril_loc + znm
-- Zoril's seed stays a constant: its QBE backend has no optimizer, so there is nothing to fold, and
-- a generated Zoril project that imported the stdlib would not build in the incremental scenario's
-- 25-module case (that project is built without a stdlib include). The other three languages, whose
-- backends do optimize, read the seed from the process or use their compiler barrier: see the Zig
-- note below, which is also where the measured cost of folding is.
f_zm:write("\nfn main() -> i32 {\n    let mut sum: i64 = 0 as i64;\n")
zoril_loc = zoril_loc + 3
if shape == "tree" then
    for m = 0, znm - 1 do
        f_zm:write(string.format("    sum = mod%d::run_m%d(sum);\n", m, m))
        zoril_loc = zoril_loc + 1
    end
else
    for m = 0, znm - 1 do
        for fn_idx = 0, znf - 1 do
            f_zm:write(string.format("    sum = sum + mod%d::calc_m%d_f%d(sum %% 100 as i64);\n", m, m, fn_idx))
            zoril_loc = zoril_loc + 1
        end
    end
end
f_zm:write("    if sum == 0 as i64 { return 1; }\n    return 0;\n}\n")
zoril_loc = zoril_loc + 3
f_zm:close()

-- ──────────────────────────────────────────────────────────────────────────────
-- Generator: Zig (with build.zig modular compilation)
-- ──────────────────────────────────────────────────────────────────────────────
local zig_dir = out_base .. "/zig"
ensure_dir(zig_dir)
local zig_loc = 0
local zgnm = cfg.zig.modules
local zgnf = cfg.zig.funcs

for m = 0, zgnm - 1 do
    local f = assert(io.open(zig_dir .. string.format("/mod%d.zig", m), "w"))
    f:write(string.format("pub const State_m%d = struct {\n    x: i64,\n    y: i64,\n    z: i64,\n};\n\n", m)); zig_loc = zig_loc + 6
    for fn_idx = 0, zgnf - 1 do
        local fn_name = string.format("calc_m%d_f%d", m, fn_idx)
        local base_add = (m + 1) * 100 + fn_idx * 7
        f:write(string.format("pub fn %s(val: i64) i64 {\n", fn_name)); zig_loc = zig_loc + 1
        f:write(string.format("    var acc: i64 = val + %d;\n", base_add)); zig_loc = zig_loc + 1
        f:write("    var i: i64 = 0;\n"); zig_loc = zig_loc + 1
        f:write("    while (i < 20) : (i += 1) {\n"); zig_loc = zig_loc + 1
        f:write(string.format("        acc = @mod((acc *%% 31 +%% i +%% %d), 1000000007);\n", fn_idx + 1)); zig_loc = zig_loc + 1
        f:write("    }\n"); zig_loc = zig_loc + 1
        f:write("    return acc;\n"); zig_loc = zig_loc + 1
        f:write("}\n\n"); zig_loc = zig_loc + 2
    end
    if shape == "tree" then
        -- The module's driver calls its own functions (see --shape above).
        f:write(string.format("pub fn run_m%d(val: i64) i64 {\n", m)); zig_loc = zig_loc + 1
        f:write("    var acc: i64 = val;\n"); zig_loc = zig_loc + 1
        for fn_idx = 0, zgnf - 1 do
            f:write(string.format("    acc = calc_m%d_f%d(acc);\n", m, fn_idx)); zig_loc = zig_loc + 1
        end
        f:write("    return acc;\n}\n\n"); zig_loc = zig_loc + 3
    end
    f:close()
end

local f_zgm = assert(io.open(zig_dir .. "/main.zig", "w"))
for m = 0, zgnm - 1 do
    f_zgm:write(string.format('const mod%d = @import("mod%d");\n', m, m))
end
zig_loc = zig_loc + zgnm
-- Using pub fn main() u8 avoids pulling in Zig's entire runtime DWARF unwinder and std.debug printer
-- The seed must be opaque to the optimizer, or a clean build of a program this shape measures a
-- pathological case of each compiler's optimizer instead of the work of compiling a program this
-- size: with a constant seed Zig's ReleaseFast folded the whole call graph and still took 259,925 ms
-- at 30k LOC (118 LOC/s against 1,296 at 3k), and with the opaque seed below its optimizing modes do
-- not finish in half an hour at all, which is why the bench builds this workload in ReleaseSmall
-- (see MF_ZIG_MODE in scripts/bench_cross_lang.sh; Debug is 2,147 ms on the same program). Zoril and
-- Hare read the seed from the process (environment, argument count), Rust from its argument count,
-- and Zig uses the compiler barrier: Zig 0.16 has no argv/env access that does not pull in an
-- allocator (std.os.argv and std.posix.getenv are both gone). Every program does the same work.
f_zgm:write("\nconst std = @import(\"std\");\n\npub fn main() u8 {\n    var sum: i64 = 0;\n    std.mem.doNotOptimizeAway(&sum);\n")
zig_loc = zig_loc + 6
if shape == "tree" then
    for m = 0, zgnm - 1 do
        f_zgm:write(string.format("    sum +%%= mod%d.run_m%d(@mod(sum, 100));\n", m, m))
        zig_loc = zig_loc + 1
    end
else
    for m = 0, zgnm - 1 do
        for fn_idx = 0, zgnf - 1 do
            f_zgm:write(string.format("    sum +%%= mod%d.calc_m%d_f%d(@mod(sum, 100));\n", m, m, fn_idx))
            zig_loc = zig_loc + 1
        end
    end
end
f_zgm:write("    if (sum == 0) return 1;\n    return 0;\n}\n")
zig_loc = zig_loc + 3
f_zgm:close()

-- Generate build.zig for modular incremental compilation
local f_zgb = assert(io.open(zig_dir .. "/build.zig", "w"))
f_zgb:write(string.format([=[const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "mf_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    inline for (0..%d) |m| {
        var name_buf: [16]u8 = undefined;
        const mod_name = std.fmt.bufPrint(&name_buf, "mod{d}", .{m}) catch unreachable;
        var file_buf: [20]u8 = undefined;
        const file_name = std.fmt.bufPrint(&file_buf, "mod{d}.zig", .{m}) catch unreachable;
        const mod = b.createModule(.{ .root_source_file = b.path(file_name) });
        exe.root_module.addImport(b.dupe(mod_name), mod);
    }

    b.installArtifact(exe);
}
]=], zgnm))
f_zgb:close()

-- ──────────────────────────────────────────────────────────────────────────────
-- Generator: Rust
-- ──────────────────────────────────────────────────────────────────────────────
local rust_dir = out_base .. "/rust/src"
ensure_dir(rust_dir)
local rust_loc = 0
local rnm = cfg.rust.modules
local rnf = cfg.rust.funcs

local f_cargo = assert(io.open(out_base .. "/rust/Cargo.toml", "w"))
f_cargo:write([=[[package]
name = "multifile_bench"
version = "0.1.0"
edition = "2021"

[dependencies]

[profile.release]
incremental = true
]=])
f_cargo:close()

for m = 0, rnm - 1 do
    local f = assert(io.open(rust_dir .. string.format("/mod%d.rs", m), "w"))
    f:write("#![allow(dead_code, non_camel_case_types)]\n"); rust_loc = rust_loc + 1
    f:write(string.format("#[derive(Copy, Clone)]\npub struct State_m%d {\n    pub x: i64,\n    pub y: i64,\n    pub z: i64,\n}\n\n", m)); rust_loc = rust_loc + 7
    for fn_idx = 0, rnf - 1 do
        local fn_name = string.format("calc_m%d_f%d", m, fn_idx)
        local base_add = (m + 1) * 100 + fn_idx * 7
        f:write(string.format("pub fn %s(val: i64) -> i64 {\n", fn_name)); rust_loc = rust_loc + 1
        f:write(string.format("    let mut acc: i64 = val.wrapping_add(%d);\n", base_add)); rust_loc = rust_loc + 1
        f:write("    for i in 0..20i64 {\n"); rust_loc = rust_loc + 1
        f:write(string.format("        acc = (acc.wrapping_mul(31).wrapping_add(i).wrapping_add(%d)).rem_euclid(1000000007);\n", fn_idx + 1)); rust_loc = rust_loc + 1
        f:write("    }\n"); rust_loc = rust_loc + 1
        f:write("    acc\n"); rust_loc = rust_loc + 1
        f:write("}\n\n"); rust_loc = rust_loc + 2
    end
    if shape == "tree" then
        -- The module's driver calls its own functions (see --shape above).
        f:write(string.format("pub fn run_m%d(val: i64) -> i64 {\n", m)); rust_loc = rust_loc + 1
        f:write("    let mut acc: i64 = val;\n"); rust_loc = rust_loc + 1
        for fn_idx = 0, rnf - 1 do
            f:write(string.format("    acc = calc_m%d_f%d(acc);\n", m, fn_idx)); rust_loc = rust_loc + 1
        end
        f:write("    acc\n}\n\n"); rust_loc = rust_loc + 3
    end
    f:close()
end

local f_rsm = assert(io.open(rust_dir .. "/main.rs", "w"))
for m = 0, rnm - 1 do
    f_rsm:write(string.format("mod mod%d;\n", m))
end
rust_loc = rust_loc + rnm
f_rsm:write("\nfn main() {\n    let mut sum: i64 = std::env::args().len() as i64;\n")
rust_loc = rust_loc + 3
if shape == "tree" then
    for m = 0, rnm - 1 do
        f_rsm:write(string.format("    sum = sum.wrapping_add(mod%d::run_m%d(sum.rem_euclid(100)));\n", m, m))
        rust_loc = rust_loc + 1
    end
else
    for m = 0, rnm - 1 do
        for fn_idx = 0, rnf - 1 do
            f_rsm:write(string.format("    sum = sum.wrapping_add(mod%d::calc_m%d_f%d(sum.rem_euclid(100)));\n", m, m, fn_idx))
            rust_loc = rust_loc + 1
        end
    end
end
f_rsm:write("    if sum == 0 { std::process::exit(1); }\n}\n")
rust_loc = rust_loc + 2
f_rsm:close()

-- ──────────────────────────────────────────────────────────────────────────────
-- Generator: Hare
-- ──────────────────────────────────────────────────────────────────────────────
local hare_dir = out_base .. "/hare"
ensure_dir(hare_dir)
local hare_loc = 0
local hnm = cfg.hare.modules
local hnf = cfg.hare.funcs

for m = 0, hnm - 1 do
    local mod_dir = hare_dir .. string.format("/mod%d", m)
    ensure_dir(mod_dir)
    local f = assert(io.open(mod_dir .. string.format("/mod%d.ha", m), "w"))
    f:write(string.format("export type State_m%d = struct {\n    x: i64,\n    y: i64,\n    z: i64,\n};\n\n", m)); hare_loc = hare_loc + 6
    for fn_idx = 0, hnf - 1 do
        local fn_name = string.format("calc_m%d_f%d", m, fn_idx)
        local base_add = (m + 1) * 100 + fn_idx * 7
        f:write(string.format("export fn %s(val: i64) i64 = {\n", fn_name)); hare_loc = hare_loc + 1
        f:write(string.format("    let acc: i64 = val + %d;\n", base_add)); hare_loc = hare_loc + 1
        f:write("    for (let i: i64 = 0; i < 20; i += 1) {\n"); hare_loc = hare_loc + 1
        f:write(string.format("        acc = (acc * 31 + i + %d) %% 1000000007;\n", fn_idx + 1)); hare_loc = hare_loc + 1
        f:write("    };\n"); hare_loc = hare_loc + 1
        f:write("    return acc;\n"); hare_loc = hare_loc + 1
        f:write("};\n\n"); hare_loc = hare_loc + 2
    end
    if shape == "tree" then
        -- The module's driver calls its own functions (see --shape above).
        f:write(string.format("export fn run_m%d(val: i64) i64 = {\n", m)); hare_loc = hare_loc + 1
        f:write("    let acc: i64 = val;\n"); hare_loc = hare_loc + 1
        for fn_idx = 0, hnf - 1 do
            f:write(string.format("    acc = calc_m%d_f%d(acc);\n", m, fn_idx)); hare_loc = hare_loc + 1
        end
        f:write("    return acc;\n};\n\n"); hare_loc = hare_loc + 3
    end
    f:close()
end

local f_ham = assert(io.open(hare_dir .. "/main.ha", "w"))
for m = 0, hnm - 1 do
    f_ham:write(string.format("use mod%d;\n", m))
end
hare_loc = hare_loc + hnm
f_ham:write("\nuse os;\n\nexport fn main() void = {\n    let sum: i64 = len(os::args): i64;\n")
hare_loc = hare_loc + 5
if shape == "tree" then
    for m = 0, hnm - 1 do
        f_ham:write(string.format("    sum += mod%d::run_m%d(sum %% 100);\n", m, m))
        hare_loc = hare_loc + 1
    end
else
    for m = 0, hnm - 1 do
        for fn_idx = 0, hnf - 1 do
            f_ham:write(string.format("    sum += mod%d::calc_m%d_f%d(sum %% 100);\n", m, m, fn_idx))
            hare_loc = hare_loc + 1
        end
    end
end
f_ham:write("    if (sum == 0) {\n        return;\n    };\n};\n")
hare_loc = hare_loc + 4
f_ham:close()

-- ──────────────────────────────────────────────────────────────────────────────
-- Summary
-- ──────────────────────────────────────────────────────────────────────────────
print(string.format("Generated into %s:", out_base))
print(string.format("  zoril: %d modules × %d funcs = %d fns, ~%d LOC",
    znm, znf, znm * znf, zoril_loc))
print(string.format("  zig:   %d modules × %d funcs = %d fns, ~%d LOC",
    zgnm, zgnf, zgnm * zgnf, zig_loc))
print(string.format("  rust:  %d modules × %d funcs = %d fns, ~%d LOC",
    rnm, rnf, rnm * rnf, rust_loc))
print(string.format("  hare:  %d modules × %d funcs = %d fns, ~%d LOC",
    hnm, hnf, hnm * hnf, hare_loc))
