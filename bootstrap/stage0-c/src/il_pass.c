#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "il_pass.h"
#include "il_ownership.h"
#include "il_type.h"
#include "il_cfg.h"
#include "il_instr.h"
#include "diagnostics.h"

typedef enum {
    ARENA_UNKNOWN,
    ARENA_KNOWN
} ArenaState;

typedef struct {
    ArenaState state;
    uint64_t capacity;
    uint64_t allocated;
} ArenaInfo;

static const ILFunction* find_func_by_id(const ILModule* mod, uint32_t id) {
    if (!mod) return NULL;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        if (mod->functions[i]->id == id) return mod->functions[i];
    }
    return NULL;
}

void il_pass_must_use_check(const void* mod_ptr, ILFunction* func, DiagnosticReport* report) {
    if (!func || func->block_count == 0 || !report) return;
    const ILModule* mod = (const ILModule*)mod_ptr;

    uint32_t max_id = il_func_get_max_ssa_id(func);
    if (max_id == 0) return;

    // Track which values come from a #[must_use] function.
    // 0: not must_use, 1: must_use and NOT YET used, 2: must_use and used.
    uint8_t* must_use_state = calloc(max_id + 1, sizeof(uint8_t));
    if (!must_use_state) return;

    // Source location for each value (where it was produced)
    SourceLocation* locs = calloc(max_id + 1, sizeof(SourceLocation));
    if (!locs) { free(must_use_state); return; }

    const char** origin_names = calloc(max_id + 1, sizeof(char*));
    if (!origin_names) { free(must_use_state); free(locs); return; }

    // First pass: Identify results from #[must_use] calls
    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* block = func->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            ILInstruction* instr = block->instructions[i];
            
            if (instr->opcode == IL_OP_CALL && instr->result_id != 0) {
                const ILFunction* target = find_func_by_id(mod, instr->operands.call.func_id);
                if (target && target->is_must_use) {
                    must_use_state[instr->result_id] = 1;
                    origin_names[instr->result_id] = target->name;
                    locs[instr->result_id] = (SourceLocation){
                        .file_path = func->file_path,
                        .line = instr->line,
                        .col = instr->col
                    };
                }
            }
        }
    }

    // Second pass: Detect uses
    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* block = func->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            ILInstruction* instr = block->instructions[i];
            
            // Simple operand check based on opcode
            switch (instr->opcode) {
                case IL_OP_ADD: case IL_OP_SUB: case IL_OP_MUL: case IL_OP_DIV:
                case IL_OP_REM: case IL_OP_AND: case IL_OP_OR: case IL_OP_XOR:
                case IL_OP_SHL: case IL_OP_SHR:
                case IL_OP_CMP_LT: case IL_OP_CMP_LE: case IL_OP_CMP_GT:
                case IL_OP_CMP_GE: case IL_OP_CMP_EQ: case IL_OP_CMP_NE:
                    if (instr->operands.binary.left <= max_id) must_use_state[instr->operands.binary.left] = 2;
                    if (instr->operands.binary.right <= max_id) must_use_state[instr->operands.binary.right] = 2;
                    break;
                case IL_OP_LOAD:
                    if (instr->operands.load.ptr <= max_id) must_use_state[instr->operands.load.ptr] = 2;
                    break;
                case IL_OP_STORE:
                    if (instr->operands.store.ptr <= max_id) must_use_state[instr->operands.store.ptr] = 2;
                    if (instr->operands.store.value <= max_id) must_use_state[instr->operands.store.value] = 2;
                    break;
                case IL_OP_CALL:
                    for (uint32_t a = 0; a < instr->operands.call.num_args; a++) {
                        if (instr->operands.call.arg_ids[a] <= max_id) must_use_state[instr->operands.call.arg_ids[a]] = 2;
                    }
                    break;
                case IL_OP_CALL_PTR:
                    if (instr->operands.call_ptr.func_ptr_id <= max_id) must_use_state[instr->operands.call_ptr.func_ptr_id] = 2;
                    for (uint32_t a = 0; a < instr->operands.call_ptr.num_args; a++) {
                        if (instr->operands.call_ptr.arg_ids[a] <= max_id) must_use_state[instr->operands.call_ptr.arg_ids[a]] = 2;
                    }
                    break;
                case IL_OP_DROP:
                    // Drop is NOT a use for #[must_use] purposes
                    break;
                case IL_OP_ELEM_ADDR:
                    if (instr->operands.elem_addr.base <= max_id) must_use_state[instr->operands.elem_addr.base] = 2;
                    if (instr->operands.elem_addr.index <= max_id) must_use_state[instr->operands.elem_addr.index] = 2;
                    break;
                case IL_OP_SUM_CONSTRUCT:
                    if (instr->operands.sum_construct.payload_id <= max_id) must_use_state[instr->operands.sum_construct.payload_id] = 2;
                    break;
                case IL_OP_VARIANT_MATCH:
                    if (instr->operands.variant_match.sum_ptr <= max_id) must_use_state[instr->operands.variant_match.sum_ptr] = 2;
                    break;
                case IL_OP_SLICE_CONSTRUCT:
                    if (instr->operands.slice_construct.ptr <= max_id) must_use_state[instr->operands.slice_construct.ptr] = 2;
                    if (instr->operands.slice_construct.len <= max_id) must_use_state[instr->operands.slice_construct.len] = 2;
                    break;
                case IL_OP_SLICE_LOAD:
                    if (instr->operands.slice_load.slice_ptr <= max_id) must_use_state[instr->operands.slice_load.slice_ptr] = 2;
                    if (instr->operands.slice_load.index <= max_id) must_use_state[instr->operands.slice_load.index] = 2;
                    break;
                case IL_OP_SLICE_STORE:
                    if (instr->operands.slice_store.slice_ptr <= max_id) must_use_state[instr->operands.slice_store.slice_ptr] = 2;
                    if (instr->operands.slice_store.index <= max_id) must_use_state[instr->operands.slice_store.index] = 2;
                    if (instr->operands.slice_store.value <= max_id) must_use_state[instr->operands.slice_store.value] = 2;
                    break;
                case IL_OP_RETURN:
                    if (instr->operands.ret.value <= max_id) must_use_state[instr->operands.ret.value] = 2;
                    break;
                case IL_OP_BRANCH:
                    if (instr->operands.branch.condition <= max_id) must_use_state[instr->operands.branch.condition] = 2;
                    break;
                case IL_OP_BITCAST:
                    if (instr->operands.bitcast.source <= max_id) must_use_state[instr->operands.bitcast.source] = 2;
                    break;
                case IL_OP_MOVE:
                case IL_OP_UNWRAP:
                case IL_OP_IS_SOME:
                    if (instr->operands.move.source <= max_id) must_use_state[instr->operands.move.source] = 2;
                    break;
                case IL_OP_ALLOC:
                    if (instr->operands.alloc.allocator_id <= max_id) must_use_state[instr->operands.alloc.allocator_id] = 2;
                    break;
                case IL_OP_REGION_CAST:
                    if (instr->operands.region_cast.source <= max_id) must_use_state[instr->operands.region_cast.source] = 2;
                    break;
                case IL_OP_PHI:
                    for (uint32_t p = 0; p < instr->operands.phi.num_incoming; p++) {
                        if (instr->operands.phi.incoming[p].value_id <= max_id) {
                            must_use_state[instr->operands.phi.incoming[p].value_id] = 2;
                        }
                    }
                    break;
                case IL_OP_SYSCALL:
                    for (uint32_t a = 0; a < instr->operands.syscall_op.num_args; a++) {
                        if (instr->operands.syscall_op.arg_ids[a] <= max_id) must_use_state[instr->operands.syscall_op.arg_ids[a]] = 2;
                    }
                    break;
                case IL_OP_ARRAY_CONSTRUCT:
                    for (uint32_t a = 0; a < instr->operands.array_construct.count; a++) {
                        if (instr->operands.array_construct.element_ids[a] <= max_id) {
                            must_use_state[instr->operands.array_construct.element_ids[a]] = 2;
                        }
                    }
                    break;
                case IL_OP_ARRAY_LOAD:
                    if (instr->operands.array_load.array_ptr <= max_id) must_use_state[instr->operands.array_load.array_ptr] = 2;
                    if (instr->operands.array_load.index <= max_id) must_use_state[instr->operands.array_load.index] = 2;
                    break;
                case IL_OP_ARRAY_STORE:
                    if (instr->operands.array_store.array_ptr <= max_id) must_use_state[instr->operands.array_store.array_ptr] = 2;
                    if (instr->operands.array_store.index <= max_id) must_use_state[instr->operands.array_store.index] = 2;
                    if (instr->operands.array_store.value <= max_id) must_use_state[instr->operands.array_store.value] = 2;
                    break;
                case IL_OP_BOUNDS_CHECK:
                    if (instr->operands.bounds_check.index <= max_id) must_use_state[instr->operands.bounds_check.index] = 2;
                    if (instr->operands.bounds_check.length <= max_id) must_use_state[instr->operands.bounds_check.length] = 2;
                    break;
                case IL_OP_WRAPPING_ADD: case IL_OP_WRAPPING_SUB: case IL_OP_WRAPPING_MUL:
                case IL_OP_SATURATING_ADD:
                case IL_OP_CHECKED_ADD: case IL_OP_CHECKED_SUB: case IL_OP_CHECKED_MUL:
                    if (instr->operands.binary.left <= max_id) must_use_state[instr->operands.binary.left] = 2;
                    if (instr->operands.binary.right <= max_id) must_use_state[instr->operands.binary.right] = 2;
                    break;
                case IL_OP_FIELD_ADDR:
                    if (instr->operands.field_addr.struct_ptr <= max_id) must_use_state[instr->operands.field_addr.struct_ptr] = 2;
                    break;
                default: break;
            }
        }
    }

    // Third pass: Warn on state == 1
    for (uint32_t id = 1; id <= max_id; id++) {
        if (must_use_state[id] == 1) {
            const char* fname = origin_names[id] ? origin_names[id] : "unknown";
            char msg[256];
            snprintf(msg, sizeof(msg), "unused result from #[must_use] function '%s'", fname);
            diag_emit(report, DIAG_WARNING, locs[id], "%s", msg);
        }
    }

    free(must_use_state);
    free(locs);
    free(origin_names);
}

void il_func_auto_drop(const void* mod, ILFunction* func) {
    if (!func || func->block_count == 0) return;

    il_func_assign_rpo_ids(func);
    OwnershipAnalysisResult res = il_func_analyze_ownership(mod, func);
    if (!res.states || !res.types) {
        il_func_ownership_result_free(res, func->block_count);
        return;
    }

    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* block = func->blocks[b];
        if (block->instr_count == 0) continue;

        ILInstruction* last_instr = block->instructions[block->instr_count - 1];
        if (last_instr->opcode == IL_OP_RETURN) {
            OwnershipState* current = ownership_state_copy(res.states[b]);
            if (!current) continue;

            // Replay the block instructions (except the last one) to get the state at return
            for (uint32_t i = 0; i < block->instr_count - 1; i++) {
                ownership_update_for_instr(current, mod, func, block->instructions[i], res.types);
            }

            // Create a list of values to drop
            uint32_t* to_drop = malloc(sizeof(uint32_t) * res.ssa_count);
            uint32_t drop_count = 0;
            for (uint32_t id = 1; id < res.ssa_count; id++) {
                if (ownership_get(current, id) == VAL_AVAILABLE) {
                    // Check if it's the value being returned!
                    if (last_instr->operands.ret.value == id) {
                        continue;
                    }

                    const ILType* type = res.types[id];
                    if (type && !il_type_is_copy_mod(mod, type)) {
                        // Linear resources must be explicitly closed, not auto-dropped.
                        if (type->kind == IL_TY_FD || type->kind == IL_TY_ASYNC_CONTEXT) {
                            continue;
                        }
                        to_drop[drop_count++] = id;
                    }
                }
            }

            if (drop_count > 0) {
                uint32_t new_instr_count = block->instr_count + drop_count;
                ILInstruction** new_instrs = calloc(new_instr_count, sizeof(ILInstruction*));
                if (!new_instrs) { free(to_drop); ownership_state_free(current); return; }
                for (uint32_t i = 0; i < block->instr_count - 1; i++) {
                    new_instrs[i] = block->instructions[i];
                }
                for (uint32_t i = 0; i < drop_count; i++) {
                    const ILType* type = res.types[to_drop[i]];
                    ILValue val = {.id = to_drop[i], .type = (const ILType*)type};
                    bool dispatched = false;
                    
                    if (type && (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM)) {
                        const ILModule* m = (const ILModule*)mod;
                        const ILTypeDef* def = il_mod_get_type_def(m, type->as.struct_sum.type_def_id);
                        if (def && def->drop_fn_name) {
                            if (func->name && strcmp(func->name, def->drop_fn_name) == 0) {
                                // Recursion guard: don't auto-drop 'self' inside its own drop method.
                            } else {
                                const ILFunction* drop_fn = il_mod_get_func_by_name(m, def->drop_fn_name);
                                if (drop_fn) {
                                    uint32_t arg_count = 1;
                                    if (!drop_fn->is_extern && strcmp(drop_fn->name, "main") != 0) arg_count++;
                                    uint32_t env_id = 0;
                                    // Search for an existing constant 0 pointer
                                    for (uint32_t b2 = 0; b2 < func->block_count; b2++) {
                                        for (uint32_t i2 = 0; i2 < func->blocks[b2]->instr_count; i2++) {
                                            ILInstruction* in = func->blocks[b2]->instructions[i2];
                                            if (in->opcode == IL_OP_CONST && in->operands.const_val.u.val == 0 && in->result_type && in->result_type->kind == IL_TY_PTR) {
                                                env_id = in->result_id;
                                                break;
                                            }
                                        }
                                        if (env_id != 0) break;
                                    }

                                    if (env_id == 0 && func->param_count > 0 && func->param_types[0]->kind == IL_TY_PTR) {
                                        // Use the first argument if it's a pointer (common for environment pointers)
                                        env_id = 0; // SSA ID 0 is the first parameter
                                    }

                                    ILValue* args = malloc(sizeof(ILValue) * arg_count);
                                    if (args) {
                                        const ILType* env_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);
                                        if (arg_count > 1) {
                                            args[0] = (ILValue){ .id = env_id, .type = env_ty };
                                            args[1] = val;
                                        } else {
                                            args[0] = val;
                                        }
                                        const ILType* unit_ty = il_type_unit();
                                        new_instrs[block->instr_count - 1 + i] = il_build_call(drop_fn->id, args, arg_count, unit_ty);
                                        
                                        free(args);
                                        dispatched = true;
                                    }
                                }
                            }
                        }
                    }
                    
                    if (!dispatched) {
                        new_instrs[block->instr_count - 1 + i] = il_build_drop(val);
                    }
                }
                new_instrs[new_instr_count - 1] = last_instr;
                free(block->instructions);
                block->instructions = new_instrs;
                block->instr_count = new_instr_count;
            }
            free(to_drop);
            ownership_state_free(current);
        }
    }

    il_func_ownership_result_free(res, func->block_count);
}

static bool is_signed_int(ILTypeKind kind) {
    return kind == IL_TY_I8 || kind == IL_TY_I16 ||
           kind == IL_TY_I32 || kind == IL_TY_I64;
}

static uint64_t truncate_to_width(uint64_t val, const ILType* type) {
    if (!type) return val;
    switch (type->kind) {
        case IL_TY_I8:  return (uint64_t)(int64_t)(int8_t) (val & 0xFFu);
        case IL_TY_U8:  return val & 0xFFu;
        case IL_TY_I16: return (uint64_t)(int64_t)(int16_t)(val & 0xFFFFu);
        case IL_TY_U16: return val & 0xFFFFu;
        case IL_TY_I32: return (uint64_t)(int64_t)(int32_t)(val & 0xFFFFFFFFu);
        case IL_TY_U32: return val & 0xFFFFFFFFu;
        default:        return val;
    }
}

static uint64_t fold_binary(ILOpcode op, uint64_t lv, uint64_t rv,
                            const ILType* operand_type) {
    bool is_signed = operand_type && is_signed_int(operand_type->kind);
    lv = truncate_to_width(lv, operand_type);
    rv = truncate_to_width(rv, operand_type);
    int64_t ls = (int64_t)lv;
    int64_t rs = (int64_t)rv;
    switch (op) {
        case IL_OP_ADD:          return lv + rv;
        case IL_OP_SUB:          return lv - rv;
        case IL_OP_MUL:          return lv * rv;
        case IL_OP_DIV:
            if (rv == 0) return 0;
            return is_signed ? (uint64_t)(ls / rs) : lv / rv;
        case IL_OP_REM:
            if (rv == 0) return 0;
            return is_signed ? (uint64_t)(ls % rs) : lv % rv;
        case IL_OP_AND:          return lv & rv;
        case IL_OP_OR:           return lv | rv;
        case IL_OP_XOR:          return lv ^ rv;
        case IL_OP_SHL:          return lv << (rv & 63u);
        case IL_OP_SHR:
            return is_signed ? (uint64_t)(ls >> (rv & 63u)) : lv >> (rv & 63u);
        case IL_OP_WRAPPING_ADD: return truncate_to_width(lv + rv, operand_type);
        case IL_OP_WRAPPING_SUB: return truncate_to_width(lv - rv, operand_type);
        case IL_OP_WRAPPING_MUL: return truncate_to_width(lv * rv, operand_type);
        case IL_OP_SATURATING_ADD: {
            uint64_t r = lv + rv;
            return (r < lv) ? UINT64_MAX : r;
        }
        case IL_OP_CMP_LT:
            return is_signed ? (uint64_t)(ls <  rs) : (uint64_t)(lv <  rv);
        case IL_OP_CMP_LE:
            return is_signed ? (uint64_t)(ls <= rs) : (uint64_t)(lv <= rv);
        case IL_OP_CMP_GT:
            return is_signed ? (uint64_t)(ls >  rs) : (uint64_t)(lv >  rv);
        case IL_OP_CMP_GE:
            return is_signed ? (uint64_t)(ls >= rs) : (uint64_t)(lv >= rv);
        case IL_OP_CMP_EQ:       return (uint64_t)(lv == rv);
        case IL_OP_CMP_NE:       return (uint64_t)(lv != rv);
        default:                 return 0;
    }
}

static bool is_foldable_binop(ILOpcode op) {
    switch (op) {
        case IL_OP_ADD: case IL_OP_SUB: case IL_OP_MUL:
        case IL_OP_DIV: case IL_OP_REM:
        case IL_OP_AND: case IL_OP_OR:  case IL_OP_XOR:
        case IL_OP_SHL: case IL_OP_SHR:
        case IL_OP_WRAPPING_ADD: case IL_OP_WRAPPING_SUB: case IL_OP_WRAPPING_MUL:
        case IL_OP_SATURATING_ADD:
        case IL_OP_CMP_LT: case IL_OP_CMP_LE:
        case IL_OP_CMP_GT: case IL_OP_CMP_GE:
        case IL_OP_CMP_EQ: case IL_OP_CMP_NE:
            return true;
        default:
            return false;
    }
}

void il_pass_const_fold(const void* mod, ILFunction* func) {
    if (!func || func->block_count == 0) return;

    il_func_assign_rpo_ids(func);
    OwnershipAnalysisResult res = il_func_analyze_ownership(mod, func);
    if (!res.states || !res.types) {
        il_func_ownership_result_free(res, func->block_count);
        return;
    }

    uint32_t map_size = res.ssa_count;
    uint8_t*  known = calloc(map_size, sizeof(uint8_t));
    uint64_t* vals  = calloc(map_size, sizeof(uint64_t));
    if (!known || !vals) {
        free(known); free(vals);
        il_func_ownership_result_free(res, func->block_count);
        return;
    }

    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* block = func->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            ILInstruction* instr = block->instructions[i];
            uint32_t rid = instr->result_id;

            if (instr->opcode == IL_OP_CONST && rid != 0 && rid < map_size) {
                if (res.types[rid] && (res.types[rid]->kind == IL_TY_F32 || res.types[rid]->kind == IL_TY_F64)) {
                    continue;
                }
                known[rid] = 1;
                vals[rid]  = instr->operands.const_val.u.val;
                continue;
            }

            if (!is_foldable_binop(instr->opcode)) continue;

            uint32_t lid = instr->operands.binary.left;
            uint32_t pid = instr->operands.binary.right;

            if (lid >= map_size || pid >= map_size) continue;
            if (!known[lid] || !known[pid]) continue;
            if (rid == 0 || rid >= map_size) continue;

            const ILType* op_ty = res.types[lid];
            uint64_t result = fold_binary(instr->opcode, vals[lid], vals[pid], op_ty);

            memset(&instr->operands, 0, sizeof(instr->operands));
            instr->opcode = IL_OP_CONST;
            instr->operands.const_val.u.val = result;

            known[rid] = 1;
            vals[rid]  = result;
        }
    }

    free(known);
    free(vals);
    il_func_ownership_result_free(res, func->block_count);
}

void il_pass_arena_capacity_check(const void* mod_ptr, ILFunction* func, DiagnosticReport* report) {
    if (!func || func->block_count == 0) return;
    const ILModule* mod = (const ILModule*)mod_ptr;

    il_func_assign_rpo_ids(func);

    uint32_t max_id = il_func_get_max_ssa_id(func);
    if (max_id == 0) return;

    uint8_t* is_const = calloc(max_id + 1, sizeof(uint8_t));
    uint64_t* const_vals = calloc(max_id + 1, sizeof(uint64_t));
    ArenaInfo* arenas = calloc(max_id + 1, sizeof(ArenaInfo));
    
    uint8_t* in_loop = calloc(func->block_count, sizeof(uint8_t));
    
    if (!is_const || !const_vals || !arenas || !in_loop) {
        free(is_const); free(const_vals); free(arenas); free(in_loop); return;
    }

    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* bb = func->blocks[b];
        if (bb->rpo_index == 0xFFFFFFFF) continue;
        for (uint32_t s = 0; s < bb->succ_count; s++) {
            ILBasicBlock* succ = bb->successors[s];
            if (succ->rpo_index == 0xFFFFFFFF) continue;
            if (bb->rpo_index >= succ->rpo_index) {
                for (uint32_t k = succ->rpo_index; k <= bb->rpo_index; k++) {
                    if (k < func->block_count) in_loop[k] = 1;
                }
            }
        }
    }

    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* block = func->blocks[b];
        bool is_in_loop = (block->rpo_index < func->block_count && in_loop[block->rpo_index]);
        
        for (uint32_t i = 0; i < block->instr_count; i++) {
            ILInstruction* instr = block->instructions[i];
            uint32_t rid = instr->result_id;

            if (instr->opcode == IL_OP_CONST && rid > 0 && rid <= max_id) {
                is_const[rid] = 1;
                const_vals[rid] = instr->operands.const_val.u.val;
            }
            else if (instr->opcode == IL_OP_CALL && rid > 0 && rid <= max_id) {
                const ILFunction* target = NULL;
                for (uint32_t fi = 0; fi < mod->function_count; fi++) {
                    if (mod->functions[fi]->id == instr->operands.call.func_id) {
                        target = mod->functions[fi]; break;
                    }
                }
                if (target && strcmp(target->name, "arena_init") == 0) {
                    if (instr->operands.call.num_args >= 2) {
                        uint32_t cap_arg_id = instr->operands.call.arg_ids[1];
                        if (is_const[cap_arg_id]) {
                            arenas[rid].state = ARENA_KNOWN;
                            arenas[rid].capacity = const_vals[cap_arg_id];
                            arenas[rid].allocated = 0;
                        }
                    }
                }
            }
            else if (instr->opcode == IL_OP_STORE) {
                uint32_t ptr_id = instr->operands.store.ptr;
                uint32_t val_id = instr->operands.store.value;
                if (ptr_id > 0 && ptr_id <= max_id && val_id > 0 && val_id <= max_id) {
                    arenas[ptr_id] = arenas[val_id];
                }
            }
            else if (instr->opcode == IL_OP_MOVE || instr->opcode == IL_OP_BITCAST || instr->opcode == IL_OP_LOAD) {
                uint32_t src_id = 0;
                if (instr->opcode == IL_OP_MOVE) src_id = instr->operands.move.source;
                else if (instr->opcode == IL_OP_BITCAST) src_id = instr->operands.bitcast.source;
                else if (instr->opcode == IL_OP_LOAD) src_id = instr->operands.load.ptr;
                
                if (src_id > 0 && src_id <= max_id && rid > 0 && rid <= max_id) {
                    arenas[rid] = arenas[src_id];
                }
            }
            else if (instr->opcode == IL_OP_FIELD_ADDR || instr->opcode == IL_OP_ELEM_ADDR) {
                uint32_t src_id = (instr->opcode == IL_OP_FIELD_ADDR) ? instr->operands.field_addr.struct_ptr : instr->operands.elem_addr.base;
                if (src_id > 0 && src_id <= max_id && rid > 0 && rid <= max_id) {
                    arenas[rid] = arenas[src_id];
                }
            }
            else if (instr->opcode == IL_OP_PHI && rid > 0 && rid <= max_id) {
                arenas[rid].state = ARENA_UNKNOWN;
            }
            else if (instr->opcode == IL_OP_ALLOC) {
                uint32_t alloc_id = instr->operands.alloc.allocator_id;
                if (alloc_id > 0 && alloc_id <= max_id && arenas[alloc_id].state == ARENA_KNOWN) {
                    const ILType* alloc_ty = (instr->result_type && (instr->result_type->kind == IL_TY_PTR || instr->result_type->kind == IL_TY_BOX)) ? instr->result_type->as.ptr.pointee : NULL;
                    size_t size = il_type_size(mod, alloc_ty);
                    size_t aligned_size = (size + 7) & ~7ULL;
                    
                    if (is_in_loop) {
                        arenas[alloc_id].state = ARENA_UNKNOWN;
                    } else {
                        arenas[alloc_id].allocated += aligned_size;
                        
                        if (arenas[alloc_id].allocated > arenas[alloc_id].capacity) {
                            SourceLocation loc = {
                                .file_path = func->file_path,
                                .line = (uint16_t)instr->line,
                                .col = (uint16_t)instr->col
                            };
                            diag_emit(report, DIAG_ERROR, loc,
                                      "arena capacity exceeded at compile time (capacity=%lu, allocated=%lu)",
                                      (unsigned long)arenas[alloc_id].capacity, (unsigned long)arenas[alloc_id].allocated);
                        }
                    }
                }
            }
        }
    }

    free(is_const);
    free(const_vals);
    free(arenas);
    free(in_loop);
}

static void infer_result_type(const void* mod_ptr, ILInstruction* instr, const ILType** types, uint32_t ssa_count) {
    const ILModule* mod = (const ILModule*)mod_ptr;
    switch (instr->opcode) {
        case IL_OP_ADD: case IL_OP_SUB: case IL_OP_MUL: case IL_OP_DIV:
        case IL_OP_REM: case IL_OP_AND: case IL_OP_OR: case IL_OP_XOR:
        case IL_OP_SHL: case IL_OP_SHR:
        case IL_OP_WRAPPING_ADD: case IL_OP_WRAPPING_SUB: case IL_OP_WRAPPING_MUL:
        case IL_OP_SATURATING_ADD:
            if (instr->operands.binary.left < ssa_count) types[instr->result_id] = types[instr->operands.binary.left];
            break;
        case IL_OP_CMP_LT: case IL_OP_CMP_LE: case IL_OP_CMP_GT:
        case IL_OP_CMP_GE: case IL_OP_CMP_EQ: case IL_OP_CMP_NE:
        case IL_OP_IS_SOME:
            types[instr->result_id] = il_type_bool();
            break;
        case IL_OP_LOAD: {
            const ILType* pt = (instr->operands.load.ptr < ssa_count) ? types[instr->operands.load.ptr] : NULL;
            if (pt) {
                if (pt->kind == IL_TY_PTR) types[instr->result_id] = pt->as.ptr.pointee;
                else if (pt->kind == IL_TY_BOX) types[instr->result_id] = pt->as.box.pointee;
            }
            break;
        }
        case IL_OP_FIELD_ADDR: {
            const ILType* pt = (instr->operands.field_addr.struct_ptr < ssa_count) ? types[instr->operands.field_addr.struct_ptr] : NULL;
            if (pt) {
                const ILType* struct_ty = NULL;
                uint32_t rid = REGION_LOCAL;
                if (pt->kind == IL_TY_PTR) {
                    struct_ty = pt->as.ptr.pointee;
                    rid = pt->as.ptr.region_id;
                } else if (pt->kind == IL_TY_BOX) {
                    struct_ty = pt->as.box.pointee;
                    rid = pt->as.box.region_id;
                } else if (pt->kind == IL_TY_STRUCT || pt->kind == IL_TY_SUM || pt->kind == IL_TY_TUPLE) {
                    struct_ty = pt;
                    rid = instr->operands.field_addr.struct_ptr;
                }

                if (struct_ty) {
                    if (struct_ty->kind == IL_TY_STRUCT || struct_ty->kind == IL_TY_SUM) {
                        const ILTypeDef* def = il_mod_get_type_def(mod, struct_ty->as.struct_sum.type_def_id);
                        if (def && instr->operands.field_addr.field_index < def->field_count) {
                            types[instr->result_id] = il_type_ptr(def->fields[instr->operands.field_addr.field_index].type, rid, true);
                        }
                    } else if (struct_ty->kind == IL_TY_TUPLE) {
                        if (instr->operands.field_addr.field_index < struct_ty->as.tuple.count) {
                            types[instr->result_id] = il_type_ptr(struct_ty->as.tuple.elements[instr->operands.field_addr.field_index], rid, true);
                        }
                    }
                }
            }
            break;
        }
        case IL_OP_ELEM_ADDR: {
            const ILType* pt = (instr->operands.elem_addr.base < ssa_count) ? types[instr->operands.elem_addr.base] : NULL;
            if (pt) {
                const ILType* agg_ty = NULL;
                uint32_t rid = REGION_LOCAL;
                if (pt->kind == IL_TY_PTR) {
                    agg_ty = pt->as.ptr.pointee;
                    rid = pt->as.ptr.region_id;
                } else if (pt->kind == IL_TY_BOX) {
                    agg_ty = pt->as.box.pointee;
                    rid = pt->as.box.region_id;
                } else if (pt->kind == IL_TY_ARRAY || pt->kind == IL_TY_SLICE) {
                    agg_ty = pt;
                    rid = instr->operands.elem_addr.base;
                }

                if (agg_ty) {
                    if (agg_ty->kind == IL_TY_ARRAY) types[instr->result_id] = il_type_ptr(agg_ty->as.array.element, rid, true);
                    else if (agg_ty->kind == IL_TY_SLICE) types[instr->result_id] = il_type_ptr(agg_ty->as.slice.element, rid, true);
                }
            }
            break;
        }
        case IL_OP_MOVE: case IL_OP_BITCAST: case IL_OP_REGION_CAST: case IL_OP_UNWRAP:
            if (instr->result_type) {
                types[instr->result_id] = instr->result_type;
            } else {
                uint32_t source_id = (instr->opcode == IL_OP_REGION_CAST) ? instr->operands.region_cast.source : instr->operands.move.source;
                if (source_id < ssa_count) {
                    types[instr->result_id] = types[source_id];
                }
            }
            break;
        case IL_OP_PHI:
            if (instr->operands.phi.num_incoming > 0 && instr->operands.phi.incoming[0].value_id < ssa_count) {
                types[instr->result_id] = types[instr->operands.phi.incoming[0].value_id];
            }
            break;
        case IL_OP_ALLOC:
            if (instr->result_type) {
                types[instr->result_id] = instr->result_type;
            }
            break;
        case IL_OP_CALL: {
            const ILFunction* target = find_func_by_id(mod, instr->operands.call.func_id);
            if (target) types[instr->result_id] = target->return_type;
            break;
        }
        case IL_OP_SLICE_LEN: case IL_OP_SLICE_DATA: case IL_OP_SYSCALL:
            types[instr->result_id] = il_type_u64();
            break;
        case IL_OP_STRING_CONST:
            types[instr->result_id] = il_type_slice(il_type_u8(), REGION_STATIC, false);
            break;
        case IL_OP_FUNC_ADDR: {
            const ILFunction* target = find_func_by_id(mod, instr->operands.func_addr.func_id);
            if (target) {
                const ILType ** ptypes = calloc(target->param_count, sizeof(const ILType*));
                if (ptypes) {
                    for (uint32_t p = 0; p < target->param_count; p++) ptypes[p] = target->param_types[p];
                    types[instr->result_id] = il_type_fn(target->return_type, ptypes, target->param_count, target->is_variadic);
                }
            }
            break;
        }
        default: break;
    }
}

void il_func_populate_types(const void* mod, ILFunction* func) {
    if (!func) return;
    uint32_t ssa_count = il_func_get_max_ssa_id(func) + 1;
    const ILType ** types = calloc(ssa_count, sizeof(const ILType*));
    if (!types) return;
    for (uint32_t i = 0; i < func->param_count; i++) if (i + 1 < ssa_count) types[i + 1] = func->param_types[i];

    for (uint32_t b = 0; b < func->block_count; b++) {
        for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
            ILInstruction* instr = (ILInstruction*)func->blocks[b]->instructions[i];
            if (instr->result_id != 0 && instr->result_id < ssa_count && !types[instr->result_id]) {
                if (instr->result_type) {
                    types[instr->result_id] = instr->result_type;
                } else {
                    infer_result_type(mod, instr, types, ssa_count);
                }
            }
            if (instr->result_id != 0 && instr->result_id < ssa_count) {
                instr->result_type = types[instr->result_id];
            }
        }
    }
    free(types);
}
