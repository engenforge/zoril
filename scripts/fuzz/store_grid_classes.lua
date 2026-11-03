-- scripts/fuzz/store_grid_classes.lua — Compute combinatorial class report for store grid
-- Usage: lua scripts/fuzz/store_grid_classes.lua <actual_failing_names_file> [output_file]

local actual_file = arg[1]
local out_file = arg[2]

if not actual_file then
    io.stderr:write("Usage: lua scripts/fuzz/store_grid_classes.lua <actual_failing_names_file> [output_file]\n")
    os.exit(1)
end

-- Set of unsafe cells that compiled (failing safety)
local unsafe_accepted = {}
for line in io.lines(actual_file) do
    local cell = line:match("^(%S+)")
    if cell then
        unsafe_accepted[cell] = true
    end
end

local base = {
    s = "arena_vec",
    c = "direct",
    p = "direct",
    d = "deref_out",
    inv = "frame_ends"
}
local base_id = string.format("%s__%s__%s__%s__%s", base.s, base.c, base.p, base.d, base.inv)

if unsafe_accepted[base_id] then
    io.stderr:write("Error: Base cell " .. base_id .. " is accepted (must be rejected)!\n")
    os.exit(1)
end

local sources = {"arena_vec", "local_vec", "string", "ref_local", "elem_ref", "closure_local"}
local carriers = {"direct", "struct_field", "tuple_slot", "enum_payload", "box", "array_slot", "struct_val", "struct_scalar", "arena_struct_bundle", "arena_tuple_bundle", "call_local", "call_method", "call_identity", "call_closure", "ref_direct", "ref_let", "ref_identity", "ref_phi"}
local paths = {"direct", "helper", "two_level_helper", "method", "self_method", "trait_method", "closure", "fn_val", "mutual_rec", "param_65", "same_param", "store_mutual_rec", "store_param_65"}
local destinations = {"deref_out", "field_out", "call_mut", "call_struct_mut", "closure_capture_mut", "closure_owned_capture", "local_field_assigned_out", "ten_copies", "return_val", "closure_call_mut"}
local invalidations = {"frame_ends", "arena_reset", "vec_free", "push_growth", "drop", "move_owner"}

local axes = {
    {name = "source", key = "s", vals = sources},
    {name = "carrier", key = "c", vals = carriers},
    {name = "path", key = "p", vals = paths},
    {name = "destination", key = "d", vals = destinations},
    {name = "invalidation", key = "inv", vals = invalidations},
}

-- Step 1: 1-axis changes
local passing_singles = {}
local failing_singles = {}

for _, axis in ipairs(axes) do
    for _, val in ipairs(axis.vals) do
        if val ~= base[axis.key] then
            local cell = {s = base.s, c = base.c, p = base.p, d = base.d, inv = base.inv}
            cell[axis.key] = val
            local id = string.format("%s__%s__%s__%s__%s", cell.s, cell.c, cell.p, cell.d, cell.inv)
            local change_info = {
                axis = axis.name,
                key = axis.key,
                val = val,
                id = id
            }
            if unsafe_accepted[id] then
                table.insert(failing_singles, change_info)
            else
                table.insert(passing_singles, change_info)
            end
        end
    end
end

-- Step 2: 2-axis pairs where both single changes pass
local failing_pairs = {}
local passing_pairs = {}

for i = 1, #passing_singles do
    for j = i + 1, #passing_singles do
        local c1 = passing_singles[i]
        local c2 = passing_singles[j]
        if c1.axis ~= c2.axis then
            local cell = {s = base.s, c = base.c, p = base.p, d = base.d, inv = base.inv}
            cell[c1.key] = c1.val
            cell[c2.key] = c2.val
            local id = string.format("%s__%s__%s__%s__%s", cell.s, cell.c, cell.p, cell.d, cell.inv)
            if unsafe_accepted[id] then
                table.insert(failing_pairs, {c1 = c1, c2 = c2, id = id})
            else
                table.insert(passing_pairs, {c1 = c1, c2 = c2, id = id})
            end
        end
    end
end

-- Format report
local lines = {}
table.insert(lines, "# Store Grid Soundness Hole Class Report")
table.insert(lines, "# Generated from base cell: " .. base_id .. " (rejected)")
table.insert(lines, string.format("# Total classes: %d (1-axis: %d, 2-axis: %d)",
    #failing_singles + #failing_pairs, #failing_singles, #failing_pairs))
table.insert(lines, "")
table.insert(lines, "# --- 1-Axis Soundness Hole Classes (single change from base escapes safety check) ---")
for _, ch in ipairs(failing_singles) do
    table.insert(lines, string.format("%s=%s: %s", ch.axis, ch.val, ch.id))
end
table.insert(lines, "")
table.insert(lines, "# --- 2-Axis Soundness Hole Classes (pair of safe single changes that fail together) ---")
for _, pair in ipairs(failing_pairs) do
    table.insert(lines, string.format("%s=%s + %s=%s: %s",
        pair.c1.axis, pair.c1.val, pair.c2.axis, pair.c2.val, pair.id))
end

local report_text = table.concat(lines, "\n") .. "\n"

if out_file then
    local f = io.open(out_file, "w")
    if not f then
        io.stderr:write("Error opening output file: " .. out_file .. "\n")
        os.exit(1)
    end
    f:write(report_text)
    f:close()
end

io.write(report_text)
