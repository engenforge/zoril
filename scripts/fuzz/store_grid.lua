-- scripts/fuzz/store_grid.lua — deterministic store-rule grid generator
-- Enumerates source x carrier x path x destination x invalidation,
-- skipping combinations that are not well-typed with explicit reasons.

local sources = {"arena_vec", "local_vec", "string", "ref_local", "elem_ref", "closure_local"}
local carriers = {"direct", "struct_field", "tuple_slot", "enum_payload", "box", "array_slot", "struct_val", "struct_scalar", "arena_struct_bundle", "arena_tuple_bundle", "call_local", "call_method", "call_identity", "call_closure", "ref_direct", "ref_let", "ref_identity", "ref_phi"}
local paths = {"direct", "helper", "two_level_helper", "method", "self_method", "trait_method", "closure", "fn_val", "mutual_rec", "param_65", "same_param", "store_mutual_rec", "store_param_65"}
-- Note: 'global' destination was removed per S1.1 spec because non-scalar static mut
-- requires 'unsafe' in Zoril, and cells must not use 'unsafe'.
local destinations = {"deref_out", "field_out", "call_mut", "call_struct_mut", "closure_capture_mut", "closure_owned_capture", "local_field_assigned_out", "ten_copies", "return_val", "closure_call_mut"}
local invalidations = {"frame_ends", "arena_reset", "vec_free", "push_growth", "drop", "move_owner"}

-- Two-module mode (--generate-modular): the path's functions go into a module of their own,
-- pathmod.zrl, which the cell imports, so the call crosses a module boundary and its summary comes
-- from pathmod's interface (.zri), as under zbuild. Only paths whose callee is a free function qualify.
local modular = false
local modular_paths = {helper = true, two_level_helper = true, fn_val = true, mutual_rec = true,
    param_65 = true, same_param = true, store_mutual_rec = true, store_param_65 = true}

-- Check why a combination should be skipped
local function get_skip_reason(s, c, p, d, inv)
    -- Invalidation vs source constraints
    if inv == "arena_reset" and s ~= "arena_vec" then
        return "arena_reset requires an arena-allocated source"
    end
    if inv == "vec_free" and s ~= "arena_vec" and s ~= "local_vec" then
        return "vec_free requires a Vec source"
    end
    if inv == "push_growth" and s ~= "arena_vec" and s ~= "local_vec" and s ~= "string" then
        return "push_growth requires a resizable collection source"
    end
    if inv == "move_owner" and (s == "ref_local" or s == "elem_ref") then
        return "move_owner requires a non-Copy owning local"
    end
    if inv == "drop" and (s == "ref_local" or s == "elem_ref") then
        return "drop requires a droppable resource"
    end

    -- Carrier constraints
    if (c == "arena_struct_bundle" or c == "arena_tuple_bundle") and s ~= "arena_vec" then
        return "an arena-bundling carrier needs an arena source"
    end
    if c == "box" and (s == "ref_local" or s == "elem_ref") then
        return "box carrier of stack reference rejected at box creation"
    end

    -- Path constraints
    if p == "same_param" and d ~= "deref_out" and d ~= "field_out" then
        return "same_param path requires an in-parameter destination (deref_out or field_out)"
    end
    if (p == "store_mutual_rec" or p == "store_param_65") and d ~= "deref_out" then
        return "a storing path writes through the in-parameter itself (deref_out)"
    end

    return nil
end

local function cell_id(s, c, p, d, inv)
    return s .. "__" .. c .. "__" .. p .. "__" .. d .. "__" .. inv
end

local function parse_cell_id(id)
    -- delimiter is "__"
    local s, c, p, d, inv = id:match("^(.-)__(.-)__(.-)__(.-)__(.-)$")
    return s, c, p, d, inv
end

-- Generate Zoril code for a cell
local function generate_code(s, c, p, d, inv, is_safe_twin)
    local out = {}
    local function emit(line) table.insert(out, line) end
    local mod_out = {}
    local function emit_path(line)
        if modular then table.insert(mod_out, "pub " .. line) else emit(line) end
    end

    -- Determine payload type and imports
    local payload_type = "[i32]"
    local elem_type = "i32"
    local is_slice = true
    local is_ref = false
    local is_fn = false
    local is_str = false

    if s == "string" then
        payload_type = "[u8]"
        elem_type = "u8"
        is_str = true
    elseif s == "ref_local" or s == "elem_ref" then
        payload_type = "&i32"
        is_slice = false
        is_ref = true
    elseif s == "closure_local" then
        payload_type = "fn() -> i32"
        is_slice = false
        is_fn = true
    end

    -- Imports
    if s == "arena_vec" or is_safe_twin then
        emit('import "mem.zrl";')
        emit('use mem::Arena;')
    end
    if s == "arena_vec" or s == "local_vec" or d == "closure_owned_capture" then
        emit('import "vec.zrl";')
        emit('use vec::Vec;')
    end
    if s == "string" then
        emit('import "string.zrl";')
        emit('use string::String;')
    end
    if c == "enum_payload" then
        emit('import "core.zrl";')
        emit('use core::Option;')
    end

    -- Carrier struct definitions
    -- The arena-bundling carriers (gap_31's shape): the arena moves into a struct literal or a tuple
    -- beside a field that comes from a parameter, and the view is taken from the bundled arena. The
    -- twin bundles a reference to the caller's arena instead.
    if c == "arena_struct_bundle" then
        if is_safe_twin then
            emit('struct ArenaBundle { ext_tag: i32, a: &Arena }')
        else
            emit('struct ArenaBundle { ext_tag: i32, a: Arena }')
        end
    end
    -- A carrier a call produced (call_*), or a reference to a carrier that a callee reads (ref_*).
    local is_call_carrier = (c == "call_local" or c == "call_method" or c == "call_identity" or c == "call_closure")
    local is_ref_carrier = (c == "ref_direct" or c == "ref_let" or c == "ref_identity" or c == "ref_phi")
    if c == "struct_field" or c == "struct_val" or is_call_carrier or is_ref_carrier then
        emit('struct Carrier { v: ' .. payload_type .. ' }')
        if c == "call_local" then
            emit('fn make_carrier(v: ' .. payload_type .. ') -> Carrier { return Carrier { v: v }; }')
        elseif c == "call_method" then
            emit('struct CarrierMaker { x: i32 }')
            emit('impl CarrierMaker { fn make(self: &CarrierMaker, v: ' .. payload_type .. ') -> Carrier { return Carrier { v: v }; } }')
        elseif c == "call_identity" then
            emit('fn id_carrier(c: Carrier) -> Carrier { return c; }')
        elseif is_ref_carrier then
            emit('fn take_ref(c: &Carrier) -> ' .. payload_type .. ' { return c.v; }')
            if c == "ref_identity" then
                emit('fn id_ref(c: &Carrier) -> &Carrier { return c; }')
            end
        end
        if c == "struct_val" then
            emit('fn extract_carrier_val(co: Carrier) -> ' .. payload_type .. ' { return co.v; }')
        end
    elseif c == "struct_scalar" then
        emit('struct CarrierScalar { v: ' .. payload_type .. ', tag: i32 }')
    end

    -- Destination struct definitions
    if d == "field_out" or d == "closure_call_mut" then
        emit('struct FieldDest { s: ' .. payload_type .. ' }')
    elseif d == "call_struct_mut" then
        emit('struct SlotMut { r: &mut ' .. payload_type .. ' }')
    elseif d == "local_field_assigned_out" then
        emit('struct LocalSlot { r: &mut ' .. payload_type .. ' }')
    elseif d == "closure_owned_capture" then
        emit('struct OwnedHolder { s: ' .. payload_type .. ', keep_non_copy: Vec<i32> }')
    end

    -- Default fn helper if needed
    if is_fn then
        emit('fn default_fn() -> i32 { return 0; }')
    end

    -- Stack clobber helper
    emit('fn clobber_stack() -> i32 { let arr = [77; 16]; return arr[0]; }')

    -- Helpers for safe twins
    if is_safe_twin and is_fn then
        emit('fn twin_fn() -> i32 { return 42; }')
    end

    -- Helper functions for paths
    if p == "helper" then
        emit_path('fn forward_helper(v: ' .. payload_type .. ') -> ' .. payload_type .. ' { return v; }')
    elseif p == "two_level_helper" then
        emit_path('fn helper_inner(v: ' .. payload_type .. ') -> ' .. payload_type .. ' { return v; }')
        emit_path('fn helper_outer(v: ' .. payload_type .. ') -> ' .. payload_type .. ' { return helper_inner(v); }')
    elseif p == "method" then
        emit('struct MethodPass { x: i32 }')
        emit('impl MethodPass { fn forward(self: &MethodPass, v: ' .. payload_type .. ') -> ' .. payload_type .. ' { return v; } }')
    elseif p == "self_method" then
        emit('struct DummySelf { x: i32 }')
        emit('impl DummySelf { fn pass(self: &DummySelf, v: ' .. payload_type .. ') -> ' .. payload_type .. ' { return v; } }')
    elseif p == "trait_method" then
        emit('trait StorerTrait { fn forward(self: &Self, v: ' .. payload_type .. ') -> ' .. payload_type .. '; }')
        emit('struct TraitImpl { x: i32 }')
        emit('impl StorerTrait for TraitImpl { fn forward(self: &TraitImpl, v: ' .. payload_type .. ') -> ' .. payload_type .. ' { return v; } }')
    elseif p == "fn_val" then
        emit_path('fn forward_fn_target(v: ' .. payload_type .. ') -> ' .. payload_type .. ' { return v; }')
    elseif p == "mutual_rec" then
        emit_path('fn rec_a(depth: i32, v: ' .. payload_type .. ') -> ' .. payload_type .. ' { if depth > 0 { return rec_b(depth - 1, v); } return v; }')
        emit_path('fn rec_b(depth: i32, v: ' .. payload_type .. ') -> ' .. payload_type .. ' { return rec_a(depth, v); }')
    elseif p == "param_65" then
        local p_args = ""
        for i = 1, 63 do p_args = p_args .. "_p" .. i .. ": i32, " end
        p_args = p_args .. "v: " .. payload_type
        emit_path('fn pass_param65(' .. p_args .. ') -> ' .. payload_type .. ' { return v; }')
    elseif p == "store_mutual_rec" then
        -- The callee stores: the value reaches `*out` only after the recursion bottoms out.
        emit_path('fn stash_a(out: &mut ' .. payload_type .. ', depth: i32, v: ' .. payload_type .. ') { if depth > 0 { stash_b(out, depth - 1, v); return; } *out = v; }')
        emit_path('fn stash_b(out: &mut ' .. payload_type .. ', depth: i32, v: ' .. payload_type .. ') { stash_a(out, depth, v); }')
    elseif p == "store_param_65" then
        -- The callee stores, and the value is its 65th parameter, past the 64-bit summary masks.
        local s_args = "out: &mut " .. payload_type .. ", "
        for i = 1, 63 do s_args = s_args .. "_p" .. i .. ": i32, " end
        s_args = s_args .. "v: " .. payload_type
        emit_path('fn stash65(' .. s_args .. ') { *out = v; }')
    elseif p == "same_param" then
        if d == "field_out" then
            emit_path('fn stash_pair(p: (&mut FieldDest, ' .. payload_type .. ')) { p.0.s = p.1; }')
        else
            emit_path('fn stash_pair(p: (&mut ' .. payload_type .. ', ' .. payload_type .. ')) { *p.0 = p.1; }')
        end
    end

    -- Helpers for destinations
    if d == "call_mut" then
        emit('fn get_mut_slot(dst: &mut ' .. payload_type .. ') -> &mut ' .. payload_type .. ' { return dst; }')
    elseif d == "call_struct_mut" then
        emit('fn get_struct_slot(dst: &mut ' .. payload_type .. ') -> SlotMut { return SlotMut { r: dst }; }')
    end

    -- Helper for sink (used in move_owner)
    if inv == "move_owner" then
        emit('fn sink<T>(t: T) {}')
    end

    -- Function containing the store
    local func_args = ""
    local ret_type = "void"
    if d == "return_val" then
        ret_type = payload_type
    elseif d == "closure_owned_capture" then
        ret_type = "i32"
    elseif d == "field_out" or d == "closure_call_mut" then
        func_args = "out: &mut FieldDest"
    elseif d == "deref_out" or d == "call_mut" or d == "call_struct_mut" or d == "ten_copies" or d == "local_field_assigned_out" or p == "same_param" or d == "closure_capture_mut" then
        func_args = "out: &mut " .. payload_type
    end
    if is_safe_twin then
        if s == "arena_vec" or s == "local_vec" then
            if #func_args > 0 then func_args = func_args .. ", " end
            func_args = func_args .. "arena_param: &Arena"
        elseif s == "ref_local" or s == "elem_ref" then
            if #func_args > 0 then func_args = func_args .. ", " end
            func_args = func_args .. "ref_param: &i32"
        end
    end
    local is_bundle = (c == "arena_struct_bundle" or c == "arena_tuple_bundle")
    if is_bundle then
        if #func_args > 0 then func_args = func_args .. ", " end
        func_args = func_args .. "ext_tag: i32"
    end
    -- How the bundled arena is named once it has moved into the bundle.
    local bundled_arena = "b.a"
    if c == "arena_tuple_bundle" then bundled_arena = "b.1" end

    local ret_sig = ""
    if ret_type ~= "void" then
        ret_sig = " -> " .. ret_type
    end

    emit('fn escape_storer(' .. func_args .. ')' .. ret_sig .. ' {')

    local err_ret = "return;"
    if ret_type == "i32" then
        err_ret = "return -1;"
    elseif ret_type == payload_type then
        if is_slice then err_ret = "return @slice(0 as *" .. elem_type .. ", 0);"
        elseif is_ref then err_ret = "let dummy_err = 0; return &dummy_err;"
        elseif is_fn then err_ret = "return default_fn;"
        end
    end

    -- Step 1: Create the source value
    if is_safe_twin and is_bundle then
        if c == "arena_struct_bundle" then
            emit('    let b = ArenaBundle { ext_tag: ext_tag, a: arena_param };')
        else
            emit('    let b = (ext_tag, arena_param);')
        end
        emit('    let mut v = Vec::<i32>.new_in(' .. bundled_arena .. ');')
        emit('    v.push(42);')
        emit('    let src_val = v.as_slice();')
    elseif is_bundle then
        emit('    let a = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { ' .. err_ret .. ' } };')
        if c == "arena_struct_bundle" then
            emit('    let mut b = ArenaBundle { ext_tag: ext_tag, a: a };')
        else
            emit('    let mut b = (ext_tag, a);')
        end
        emit('    let mut v = Vec::<i32>.new_in(&' .. bundled_arena .. ');')
        emit('    v.push(42);')
        emit('    let src_val = v.as_slice();')
    elseif is_safe_twin then
        if s == "arena_vec" or s == "local_vec" then
            emit('    let mut v = Vec::<i32>.new_in(arena_param);')
            emit('    v.push(42);')
            emit('    let src_val = v.as_slice();')
        elseif s == "string" then
            emit('    let src_val = "hello";')
        elseif s == "ref_local" or s == "elem_ref" then
            emit('    let src_val = ref_param;')
        elseif s == "closure_local" then
            emit('    let src_val = twin_fn;')
        end
    else
        if s == "arena_vec" then
            emit('    let mut a = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { ' .. err_ret .. ' } };')
            emit('    let mut v = Vec::<i32>.new_in(&a);')
            emit('    v.push(42);')
            emit('    let src_val = v.as_slice();')
        elseif s == "local_vec" then
            emit('    let mut v = Vec::<i32>.new();')
            emit('    v.push(42);')
            emit('    let src_val = v.as_slice();')
        elseif s == "string" then
            emit('    let mut s = String.new();')
            emit('    s.push_u8(42 as u8);')
            emit('    let src_val = s.as_slice();')
        elseif s == "ref_local" then
            emit('    let x = 42;')
            emit('    let src_val = &x;')
        elseif s == "elem_ref" then
            emit('    let mut arr = [42, 0];')
            emit('    let src_val = &arr[0];')
        elseif s == "closure_local" then
            emit('    let x = 42;')
            emit('    let src_val = || -> i32 { return x; };')
        end
    end

    -- Step 2: Wrap in carrier
    if c == "direct" or is_bundle then
        emit('    let carried = src_val;')
    elseif c == "struct_field" then
        if is_slice then
            emit('    let mut carrier_obj = Carrier { v: @slice(0 as *' .. elem_type .. ', 0) };')
        elseif is_ref then
            emit('    let mut seed = 0;')
            emit('    let mut carrier_obj = Carrier { v: &seed };')
        elseif is_fn then
            emit('    let mut carrier_obj = Carrier { v: default_fn };')
        end
        emit('    carrier_obj.v = src_val;')
        emit('    let carried = carrier_obj.v;')
    elseif c == "tuple_slot" then
        if is_slice then
            emit('    let mut carrier_tup = (@slice(0 as *' .. elem_type .. ', 0), 10);')
        elseif is_ref then
            emit('    let mut seed = 0;')
            emit('    let mut carrier_tup = (&seed, 10);')
        elseif is_fn then
            emit('    let mut carrier_tup = (default_fn, 10);')
        end
        emit('    carrier_tup.0 = src_val;')
        emit('    let carried = carrier_tup.0;')
    elseif c == "enum_payload" then
        emit('    let carrier_opt = Option.Some(src_val);')
        emit('    let carried = match carrier_opt { Option.Some(item) => item, Option.None => { ' .. err_ret .. ' } };')
    elseif c == "box" then
        emit('    let carrier_box = box src_val;')
        emit('    let carried = *carrier_box;')
    elseif c == "array_slot" then
        if is_slice then
            emit('    let mut carrier_arr = [@slice(0 as *' .. elem_type .. ', 0)];')
        elseif is_ref then
            emit('    let mut seed = 0;')
            emit('    let mut carrier_arr = [&seed];')
        elseif is_fn then
            emit('    let mut carrier_arr = [default_fn];')
        end
        emit('    carrier_arr[0] = src_val;')
        emit('    let carried = carrier_arr[0];')
    elseif c == "struct_val" then
        emit('    let carrier_obj = Carrier { v: src_val };')
        emit('    let carried = extract_carrier_val(carrier_obj);')
    elseif c == "struct_scalar" then
        emit('    let carrier_obj = CarrierScalar { v: src_val, tag: 1 };')
        emit('    let carried = carrier_obj.v;')
    elseif c == "call_local" then
        emit('    let carrier_obj = make_carrier(src_val);')
        emit('    let carried = carrier_obj.v;')
    elseif c == "call_method" then
        emit('    let maker = CarrierMaker { x: 0 };')
        emit('    let carrier_obj = maker.make(src_val);')
        emit('    let carried = carrier_obj.v;')
    elseif c == "call_identity" then
        emit('    let carrier_obj = id_carrier(Carrier { v: src_val });')
        emit('    let carried = carrier_obj.v;')
    elseif c == "call_closure" then
        emit('    let make_c = |item: ' .. payload_type .. '| -> Carrier { return Carrier { v: item }; };')
        emit('    let carrier_obj = make_c(src_val);')
        emit('    let carried = carrier_obj.v;')
    elseif c == "ref_direct" then
        emit('    let carrier_obj = Carrier { v: src_val };')
        emit('    let carried = take_ref(&carrier_obj);')
    elseif c == "ref_let" then
        emit('    let carrier_obj = Carrier { v: src_val };')
        emit('    let carrier_ref = &carrier_obj;')
        emit('    let carried = take_ref(carrier_ref);')
    elseif c == "ref_identity" then
        emit('    let carrier_obj = Carrier { v: src_val };')
        emit('    let carried = take_ref(id_ref(&carrier_obj));')
    elseif c == "ref_phi" then
        -- The branch depends on a call, so it is a real join of two references, not a folded one.
        emit('    let carrier_obj = Carrier { v: src_val };')
        emit('    let carrier_alt = Carrier { v: src_val };')
        emit('    let carrier_ref = if clobber_stack() > 0 { &carrier_obj } else { &carrier_alt };')
        emit('    let carried = take_ref(carrier_ref);')
    end

    -- Step 3: Route through path
    if p == "direct" then
        emit('    let routed = carried;')
    elseif p == "helper" then
        emit('    let routed = forward_helper(carried);')
    elseif p == "two_level_helper" then
        emit('    let routed = helper_outer(carried);')
    elseif p == "method" then
        emit('    let m_pass = MethodPass { x: 0 };')
        emit('    let routed = m_pass.forward(carried);')
    elseif p == "self_method" then
        emit('    let d_self = DummySelf { x: 0 };')
        emit('    let routed = d_self.pass(carried);')
    elseif p == "trait_method" then
        emit('    let t_impl = TraitImpl { x: 0 };')
        emit('    let routed = t_impl.forward(carried);')
    elseif p == "closure" then
        emit('    let f_clos = |item: ' .. payload_type .. '| -> ' .. payload_type .. ' { return item; };')
        emit('    let routed = f_clos(carried);')
    elseif p == "fn_val" then
        emit('    let f_ptr: fn(' .. payload_type .. ') -> ' .. payload_type .. ' = forward_fn_target;')
        emit('    let routed = f_ptr(carried);')
    elseif p == "mutual_rec" then
        emit('    let routed = rec_b(1, carried);')
    elseif p == "param_65" then
        local dummy_args = ""
        for i = 1, 63 do dummy_args = dummy_args .. i .. ", " end
        emit('    let routed = pass_param65(' .. dummy_args .. 'carried);')
    elseif p == "same_param" then
        emit('    stash_pair((out, carried));')
    elseif p == "store_mutual_rec" then
        emit('    stash_b(out, 1, carried);')
    elseif p == "store_param_65" then
        local s_dummy = ""
        for i = 1, 63 do s_dummy = s_dummy .. i .. ", " end
        emit('    stash65(out, ' .. s_dummy .. 'carried);')
    end

    -- Step 4: Write into destination (if not already handled by a path that stores)
    if p ~= "same_param" and p ~= "store_mutual_rec" and p ~= "store_param_65" then
        if d == "deref_out" then
            emit('    *out = routed;')
        elseif d == "field_out" then
            emit('    out.s = routed;')
        elseif d == "closure_call_mut" then
            emit('    let get_out = || -> &mut ' .. payload_type .. ' { return &mut out.s; };')
            emit('    let slot = get_out();')
            emit('    *slot = routed;')
        elseif d == "call_mut" then
            emit('    let slot = get_mut_slot(out);')
            emit('    *slot = routed;')
        elseif d == "call_struct_mut" then
            emit('    let slot_holder = get_struct_slot(out);')
            emit('    *slot_holder.r = routed;')
        elseif d == "closure_capture_mut" then
            emit('    let mut cl = || { *out = routed; };')
            emit('    cl();')
        elseif d == "closure_owned_capture" then
            -- Initial dummy holder
            if is_slice then
                emit('    let mut h = OwnedHolder { s: @slice(0 as *' .. elem_type .. ', 0), keep_non_copy: Vec::<i32>.new() };')
            elseif is_ref then
                emit('    let mut dummy_seed = 0;')
                emit('    let mut h = OwnedHolder { s: &dummy_seed, keep_non_copy: Vec::<i32>.new() };')
            elseif is_fn then
                emit('    let mut h = OwnedHolder { s: default_fn, keep_non_copy: Vec::<i32>.new() };')
            end
            emit('    let mut c_owned = |store_mode: bool| -> i32 {')
            emit('        if store_mode {')
            emit('            h = OwnedHolder { s: routed, keep_non_copy: Vec::<i32>.new() };')
            emit('            return 0;')
            emit('        }')
            if is_slice then
                emit('        return h.s[0] as i32;')
            elseif is_ref then
                emit('        return *h.s;')
            elseif is_fn then
                emit('        return h.s();')
            end
            emit('    };')
            emit('    let _ = c_owned(true);')
        elseif d == "local_field_assigned_out" then
            if is_slice then
                emit('    let mut dummy_slice: ' .. payload_type .. ' = @slice(0 as *' .. elem_type .. ', 0);')
                emit('    let mut sm = LocalSlot { r: &mut dummy_slice };')
            elseif is_ref then
                emit('    let mut dummy_seed = 0;')
                emit('    let mut dummy_ref: &i32 = &dummy_seed;')
                emit('    let mut sm = LocalSlot { r: &mut dummy_ref };')
            elseif is_fn then
                emit('    let mut dummy_f: fn() -> i32 = default_fn;')
                emit('    let mut sm = LocalSlot { r: &mut dummy_f };')
            end
            emit('    sm.r = out;')
            emit('    *sm.r = routed;')
        elseif d == "ten_copies" then
            emit('    let r1 = out;')
            emit('    let r2 = r1;')
            emit('    let r3 = r2;')
            emit('    let r4 = r3;')
            emit('    let r5 = r4;')
            emit('    let r6 = r5;')
            emit('    let r7 = r6;')
            emit('    let r8 = r7;')
            emit('    let r9 = r8;')
            emit('    let r10 = r9;')
            emit('    *r10 = routed;')
        elseif d == "return_val" then
            -- Note: return handled below after invalidation (if invalidation is before return)
        end
    end

    -- Step 5: Invalidation inside storer (for reset, free, push, drop, move)
    if not is_safe_twin then
        if inv == "arena_reset" and is_bundle then
            emit('    ' .. bundled_arena .. '.reset();')
        elseif inv == "arena_reset" then
            emit('    a.reset();')
        elseif inv == "vec_free" then
            emit('    v.free();')
        elseif inv == "push_growth" then
            if s == "string" then
                emit('    s.push_str("large string reallocation exceeding initial buffer size");')
            else
                emit('    for i in 0..100 { v.push(i); }')
            end
        elseif inv == "drop" and is_bundle then
            emit('    @drop(b);')
        elseif inv == "drop" then
            if s == "arena_vec" then
                emit('    @drop(a);')
            elseif s == "local_vec" then
                emit('    @drop(v);')
            elseif s == "string" then
                emit('    @drop(s);')
            elseif s == "closure_local" then
                emit('    @drop(x);')
            end
        elseif inv == "move_owner" and is_bundle then
            emit('    sink(b);')
        elseif inv == "move_owner" then
            if s == "arena_vec" then
                emit('    sink(a);')
            elseif s == "local_vec" then
                emit('    sink(v);')
            elseif s == "string" then
                emit('    sink(s);')
            elseif s == "closure_local" then
                emit('    sink(x);')
            end
        end
    end

    if d == "return_val" then
        emit('    return routed;')
    elseif d == "closure_owned_capture" then
        emit('    return c_owned(false);')
    end

    emit('}') -- end escape_storer

    -- Step 6: Caller / main function
    emit('fn main() -> i32 {')
    local extra_arg = ""
    if is_safe_twin then
        if s == "arena_vec" or s == "local_vec" then
            emit('    let a_main = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return 1; } };')
            extra_arg = "&a_main"
        elseif s == "ref_local" or s == "elem_ref" then
            emit('    let val_main = 42;')
            extra_arg = "&val_main"
        end
    end
    if is_bundle then
        if #extra_arg > 0 then extra_arg = extra_arg .. ", " end
        extra_arg = extra_arg .. "7"
    end
    if d == "return_val" then
        if #extra_arg > 0 then
            emit('    let res = escape_storer(' .. extra_arg .. ');')
        else
            emit('    let res = escape_storer();')
        end
        -- Invalidation by frame_ends: allocate another arena/stack and overwrite
        if not is_safe_twin and inv == "frame_ends" then
            emit('    let _ = clobber_stack();')
            if s == "arena_vec" then
                emit('    let mut a_clobber = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return 2; } };')
                emit('    let mut v_clobber = Vec::<i32>.new_in(&a_clobber);')
                emit('    v_clobber.push(77);')
            end
        end
        if is_slice then
            emit('    return res[0] as i32;')
        elseif is_ref then
            emit('    return *res;')
        elseif is_fn then
            emit('    return res();')
        end
    elseif d == "closure_owned_capture" then
        if #extra_arg > 0 then
            emit('    let res = escape_storer(' .. extra_arg .. ');')
        else
            emit('    let res = escape_storer();')
        end
        emit('    return res;')
    elseif d == "field_out" or d == "closure_call_mut" then
        if is_slice then
            emit('    let mut fd = FieldDest { s: @slice(0 as *' .. elem_type .. ', 0) };')
        elseif is_ref then
            emit('    let mut seed = 0;')
            emit('    let mut fd = FieldDest { s: &seed };')
        elseif is_fn then
            emit('    let mut fd = FieldDest { s: default_fn };')
        end
        if #extra_arg > 0 then
            emit('    escape_storer(&mut fd, ' .. extra_arg .. ');')
        else
            emit('    escape_storer(&mut fd);')
        end
        if not is_safe_twin and inv == "frame_ends" then
            emit('    let _ = clobber_stack();')
            if s == "arena_vec" then
                emit('    let mut a_clobber = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return 2; } };')
                emit('    let mut v_clobber = Vec::<i32>.new_in(&a_clobber);')
                emit('    v_clobber.push(77);')
            end
        end
        if is_slice then
            emit('    return fd.s[0] as i32;')
        elseif is_ref then
            emit('    return *fd.s;')
        elseif is_fn then
            emit('    return fd.s();')
        end
    else
        -- standard out: &mut payload_type
        if is_slice then
            emit('    let mut dest_val: ' .. payload_type .. ' = @slice(0 as *' .. elem_type .. ', 0);')
        elseif is_ref then
            emit('    let mut seed = 0;')
            emit('    let mut dest_val: &i32 = &seed;')
        elseif is_fn then
            emit('    let mut dest_val: fn() -> i32 = default_fn;')
        end
        if #extra_arg > 0 then
            emit('    escape_storer(&mut dest_val, ' .. extra_arg .. ');')
        else
            emit('    escape_storer(&mut dest_val);')
        end
        if not is_safe_twin and inv == "frame_ends" then
            emit('    let _ = clobber_stack();')
            if s == "arena_vec" then
                emit('    let mut a_clobber = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return 2; } };')
                emit('    let mut v_clobber = Vec::<i32>.new_in(&a_clobber);')
                emit('    v_clobber.push(77);')
            end
        end
        if is_slice then
            emit('    return dest_val[0] as i32;')
        elseif is_ref then
            emit('    return *dest_val;')
        elseif is_fn then
            emit('    return dest_val();')
        end
    end
    emit('}') -- end main

    if modular and #mod_out > 0 then
        local uses = {}
        for _, line in ipairs(mod_out) do
            local name = line:match("^pub fn ([%w_]+)")
            if name then table.insert(uses, 'use pathmod::' .. name .. ';') end
        end
        for i = #uses, 1, -1 do table.insert(out, 1, uses[i]) end
        table.insert(out, 1, 'import "pathmod.zrl";')
    end
    return table.concat(out, "\n") .. "\n", table.concat(mod_out, "\n") .. "\n"
end

-- CLI Handler
local mode = "summary"
local target_cell = nil
local target_dir = nil

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--list" then
        mode = "list"
    elseif a == "--summary" then
        mode = "summary"
    elseif a == "--emit" then
        mode = "emit"
        i = i + 1
        target_cell = arg[i]
    elseif a == "--emit-twin" then
        mode = "emit-twin"
        i = i + 1
        target_cell = arg[i]
    elseif a == "--generate-all" then
        mode = "generate-all"
        i = i + 1
        target_dir = arg[i]
    elseif a == "--generate-modular" then
        mode = "generate-modular"
        i = i + 1
        target_dir = arg[i]
    else
        io.stderr:write("Unknown argument: " .. a .. "\n")
        os.exit(1)
    end
    i = i + 1
end

if mode == "emit" then
    local s, c, p, d, inv = parse_cell_id(target_cell)
    if not s then
        io.stderr:write("Invalid cell ID: " .. tostring(target_cell) .. "\n")
        os.exit(1)
    end
    local reason = get_skip_reason(s, c, p, d, inv)
    if reason then
        io.stderr:write("Cell is skipped: " .. reason .. "\n")
        os.exit(2)
    end
    io.write(generate_code(s, c, p, d, inv, false))
    os.exit(0)
elseif mode == "emit-twin" then
    local s, c, p, d, inv = parse_cell_id(target_cell)
    if not s then
        io.stderr:write("Invalid cell ID: " .. tostring(target_cell) .. "\n")
        os.exit(1)
    end
    local reason = get_skip_reason(s, c, p, d, inv)
    if reason then
        io.stderr:write("Cell is skipped: " .. reason .. "\n")
        os.exit(2)
    end
    io.write(generate_code(s, c, p, d, inv, true))
    os.exit(0)
end

-- Enumerate all cells
local total = 0
local skipped_count = 0
local skip_reasons = {}
local valid_cells = {}

for _, s in ipairs(sources) do
    for _, c in ipairs(carriers) do
        for _, p in ipairs(paths) do
            for _, d in ipairs(destinations) do
                for _, inv in ipairs(invalidations) do
                    total = total + 1
                    local reason = get_skip_reason(s, c, p, d, inv)
                    if reason then
                        skipped_count = skipped_count + 1
                        skip_reasons[reason] = (skip_reasons[reason] or 0) + 1
                    else
                        table.insert(valid_cells, cell_id(s, c, p, d, inv))
                    end
                end
            end
        end
    end
end

if mode == "summary" then
    print(string.format("Total: %d, Skipped: %d, Valid: %d", total, skipped_count, #valid_cells))
    for r, cnt in pairs(skip_reasons) do
        print(string.format("  - %s: %d", r, cnt))
    end
elseif mode == "list" then
    for _, id in ipairs(valid_cells) do
        print(id)
    end
elseif mode == "generate-all" then
    assert(target_dir, "Target directory required for --generate-all")
    os.execute("mkdir -p " .. target_dir)
    local manifest = io.open(target_dir .. "/manifest.txt", "w")
    for idx, id in ipairs(valid_cells) do
        local s, c, p, d, inv = parse_cell_id(id)
        local u_code = generate_code(s, c, p, d, inv, false)
        local t_code = generate_code(s, c, p, d, inv, true)
        local u_path = string.format("%s/%s.unsafe.zrl", target_dir, id)
        local t_path = string.format("%s/%s.twin.zrl", target_dir, id)
        local fu = io.open(u_path, "w")
        fu:write(u_code)
        fu:close()
        local ft = io.open(t_path, "w")
        ft:write(t_code)
        ft:close()
        manifest:write(id .. "\n")
    end
    manifest:close()
    print(string.format("Generated %d cell pairs in %s", #valid_cells, target_dir))
elseif mode == "generate-modular" then
    -- One directory per cell: pathmod.zrl (the path's functions), unsafe.zrl and twin.zrl (each
    -- importing it). The cells are the direct carrier with the frame_ends invalidation, over every
    -- source and destination, for each path whose callee is a free function: the routes the call
    -- summary decides, without the grid's full product.
    assert(target_dir, "Target directory required for --generate-modular")
    modular = true
    os.execute("mkdir -p " .. target_dir)
    local manifest = io.open(target_dir .. "/manifest.txt", "w")
    local count = 0
    for _, id in ipairs(valid_cells) do
        local s, c, p, d, inv = parse_cell_id(id)
        if modular_paths[p] and c == "direct" and inv == "frame_ends" and (p ~= "same_param" or d == "deref_out") then
            local dir = target_dir .. "/" .. id
            os.execute("mkdir -p " .. dir)
            local u_code, mod_code = generate_code(s, c, p, d, inv, false)
            local t_code = generate_code(s, c, p, d, inv, true)
            for name, text in pairs({["pathmod.zrl"] = mod_code, ["unsafe.zrl"] = u_code, ["twin.zrl"] = t_code}) do
                local f = io.open(dir .. "/" .. name, "w")
                f:write(text)
                f:close()
            end
            manifest:write(id .. "\n")
            count = count + 1
        end
    end
    manifest:close()
    print(string.format("Generated %d two-module cells in %s", count, target_dir))
end
