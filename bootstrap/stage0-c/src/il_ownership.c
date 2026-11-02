#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../include/il_ownership.h"
#include "../include/il_type.h"

static void update_val_id(uint32_t* max_id, uint32_t id) {
    if (id != 0 && id < 0xFFFFFFF0) {
        if (id > *max_id) *max_id = id;
    }
}

ValueStatus ownership_get(const OwnershipState* state, uint32_t id) {
    if (id >= state->count) return VAL_UNDEFINED;
    uint32_t byte_idx = id / 4;
    uint32_t bit_offset = (uint32_t)(id % 4) * 2;
    return (ValueStatus)((state->packed_status[byte_idx] >> bit_offset) & 0x03);
}

void ownership_set(OwnershipState* state, uint32_t id, ValueStatus status) {
    if (id >= state->count) return;
    uint32_t byte_idx = id / 4;
    uint32_t bit_offset = (uint32_t)(id % 4) * 2;
    state->packed_status[byte_idx] &= (uint8_t)~(0x03 << bit_offset);
    state->packed_status[byte_idx] |= (uint8_t)(((uint8_t)status & 0x03) << bit_offset);
}

size_t ownership_state_size(uint32_t count) {
    return sizeof(OwnershipState) + (count + 3) / 4;
}

void ownership_state_init(OwnershipState* state, uint32_t count) {
    state->count = count;
    memset(state->packed_status, 0, (count + 3) / 4);
}

OwnershipState* ownership_state_create(uint32_t count) {
    OwnershipState* state = calloc(1, ownership_state_size(count));
    if (!state) return NULL;
    state->count = count;
    return state;
}

void ownership_state_free(OwnershipState* state) {
    free(state);
}

OwnershipState* ownership_state_copy(const OwnershipState* state) {
    if (!state) return NULL;
    size_t size = ownership_state_size(state->count);
    OwnershipState* copy = malloc(size);
    if (!copy) return NULL;
    memcpy(copy, state, size);
    return copy;
}

void ownership_state_copy_to(OwnershipState* dest, const OwnershipState* src) {
    if (!dest || !src) return;
    uint32_t count = (dest->count < src->count) ? dest->count : src->count;
    memcpy(dest->packed_status, src->packed_status, (count + 3) / 4);
}

bool ownership_state_merge(OwnershipState* target, const OwnershipState* source) {
    if (!target || !source || target->count != source->count) return false;
    bool changed = false;
    uint32_t num_bytes = (target->count + 3) / 4;
    for (uint32_t i = 0; i < num_bytes; i++) {
        uint8_t t = target->packed_status[i];
        uint8_t s = source->packed_status[i];
        if (t == s) continue;

        uint8_t new_t = 0;
        for (int b = 0; b < 4; b++) {
            uint8_t t_bits = (uint8_t)((t >> (b * 2)) & 0x03);
            uint8_t s_bits = (uint8_t)((s >> (b * 2)) & 0x03);
            uint8_t res_bits = t_bits;
            
            if (t_bits == VAL_UNDEFINED) {
                res_bits = s_bits;
            } else if (s_bits == VAL_UNDEFINED) {
                // res_bits already set to t_bits
            } else if (t_bits == VAL_MOVED || s_bits == VAL_MOVED) {
                res_bits = VAL_MOVED;
            } else if (t_bits == VAL_AVAILABLE && s_bits == VAL_AVAILABLE) {
                res_bits = VAL_AVAILABLE;
            }
            new_t |= (uint8_t)(res_bits << (b * 2));
        }
        
        if (new_t != t) {
            target->packed_status[i] = new_t;
            changed = true;
        }
    }
    return changed;
}

uint32_t il_func_get_max_ssa_id(const ILFunction* func) {
    uint32_t max_id = func->param_count; // Parameters start at v1
    for (uint32_t b = 0; b < func->block_count; b++) {
        const ILBasicBlock* block = func->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            const ILInstruction* instr = block->instructions[i];
            update_val_id(&max_id, instr->result_id);
            
            switch (instr->opcode) {
                case IL_OP_ADD: case IL_OP_SUB: case IL_OP_MUL: case IL_OP_DIV:
                case IL_OP_REM: case IL_OP_AND: case IL_OP_OR: case IL_OP_XOR:
                case IL_OP_SHL: case IL_OP_SHR:
                case IL_OP_CMP_LT: case IL_OP_CMP_LE: case IL_OP_CMP_GT:
                case IL_OP_CMP_GE: case IL_OP_CMP_EQ: case IL_OP_CMP_NE:
                case IL_OP_WRAPPING_ADD: case IL_OP_WRAPPING_SUB: case IL_OP_WRAPPING_MUL:
                case IL_OP_SATURATING_ADD:
                case IL_OP_CHECKED_ADD: case IL_OP_CHECKED_SUB: case IL_OP_CHECKED_MUL:
                    update_val_id(&max_id, instr->operands.binary.left);
                    update_val_id(&max_id, instr->operands.binary.right);
                    break;
                case IL_OP_LOAD: update_val_id(&max_id, instr->operands.load.ptr); break;
                case IL_OP_STORE:
                    update_val_id(&max_id, instr->operands.store.ptr);
                    update_val_id(&max_id, instr->operands.store.value);
                    break;
                case IL_OP_MOVE: case IL_OP_UNWRAP: case IL_OP_IS_SOME:
                    update_val_id(&max_id, instr->operands.move.source);
                    break;
                case IL_OP_BITCAST:
                    update_val_id(&max_id, instr->operands.bitcast.source);
                    break;
                case IL_OP_DROP: update_val_id(&max_id, instr->operands.drop.value); break;
                case IL_OP_RETURN: update_val_id(&max_id, instr->operands.ret.value); break;
                case IL_OP_BRANCH: update_val_id(&max_id, instr->operands.branch.condition); break;
                case IL_OP_JUMP: break;
                case IL_OP_CALL:
                    for (uint32_t arg = 0; arg < instr->operands.call.num_args; arg++) {
                        update_val_id(&max_id, instr->operands.call.arg_ids[arg]);
                    }
                    break;
                case IL_OP_CALL_PTR:
                    update_val_id(&max_id, instr->operands.call_ptr.func_ptr_id);
                    for (uint32_t arg = 0; arg < instr->operands.call_ptr.num_args; arg++) {
                        update_val_id(&max_id, instr->operands.call_ptr.arg_ids[arg]);
                    }
                    break;
                case IL_OP_SYSCALL:
                    if (instr->operands.syscall_op.arg_ids) {
                        for (uint32_t arg = 0; arg < instr->operands.syscall_op.num_args; arg++) {
                            update_val_id(&max_id, instr->operands.syscall_op.arg_ids[arg]);
                        }
                    }
                    break;
                case IL_OP_FD_OPEN:
                    update_val_id(&max_id, instr->operands.fd_open.path);
                    update_val_id(&max_id, instr->operands.fd_open.flags);
                    update_val_id(&max_id, instr->operands.fd_open.mode);
                    break;
                case IL_OP_FD_CLOSE: update_val_id(&max_id, instr->operands.fd_close.fd); break;
                case IL_OP_FD_READ:
                case IL_OP_FD_WRITE:
                    update_val_id(&max_id, instr->operands.fd_io.fd);
                    update_val_id(&max_id, instr->operands.fd_io.buf);
                    update_val_id(&max_id, instr->operands.fd_io.count);
                    break;
                case IL_OP_ASYNC_SETUP: update_val_id(&max_id, instr->operands.async_setup.entries); break;
                case IL_OP_ASYNC_ENTER:
                    update_val_id(&max_id, instr->operands.async_enter.ctx);
                    update_val_id(&max_id, instr->operands.async_enter.to_submit);
                    update_val_id(&max_id, instr->operands.async_enter.min_complete);
                    break;
                case IL_OP_ASYNC_CLOSE: update_val_id(&max_id, instr->operands.async_close.ctx); break;
                case IL_OP_FIELD_ADDR: update_val_id(&max_id, instr->operands.field_addr.struct_ptr); break;
                case IL_OP_ELEM_ADDR:
                    update_val_id(&max_id, instr->operands.elem_addr.base);
                    update_val_id(&max_id, instr->operands.elem_addr.index);
                    break;
                case IL_OP_VARIANT_MATCH: update_val_id(&max_id, instr->operands.variant_match.sum_ptr); break;
                case IL_OP_SUM_CONSTRUCT: update_val_id(&max_id, instr->operands.sum_construct.payload_id); break;
                case IL_OP_PHI:
                    for (uint32_t arg = 0; arg < instr->operands.phi.num_incoming; arg++) {
                        update_val_id(&max_id, instr->operands.phi.incoming[arg].value_id);
                    }
                    break;
                case IL_OP_BOUNDS_CHECK:
                    update_val_id(&max_id, instr->operands.bounds_check.index);
                    update_val_id(&max_id, instr->operands.bounds_check.length);
                    break;
                case IL_OP_SLICE_LOAD:
                    update_val_id(&max_id, instr->operands.slice_load.slice_ptr);
                    update_val_id(&max_id, instr->operands.slice_load.index);
                    break;
                case IL_OP_SLICE_STORE:
                    update_val_id(&max_id, instr->operands.slice_store.slice_ptr);
                    update_val_id(&max_id, instr->operands.slice_store.index);
                    update_val_id(&max_id, instr->operands.slice_store.value);
                    break;
                case IL_OP_SLICE_LEN:
                case IL_OP_SLICE_DATA:
                    update_val_id(&max_id, instr->operands.slice_op.slice_ptr);
                    break;
                case IL_OP_SLICE_CONSTRUCT:
                    update_val_id(&max_id, instr->operands.slice_construct.ptr);
                    update_val_id(&max_id, instr->operands.slice_construct.len);
                    break;
                case IL_OP_ARRAY_CONSTRUCT:
                    for (uint32_t arg = 0; arg < instr->operands.array_construct.count; arg++) {
                        update_val_id(&max_id, instr->operands.array_construct.element_ids[arg]);
                    }
                    break;
                case IL_OP_ARRAY_LOAD:
                    update_val_id(&max_id, instr->operands.array_load.array_ptr);
                    update_val_id(&max_id, instr->operands.array_load.index);
                    break;
                case IL_OP_ARRAY_STORE:
                    update_val_id(&max_id, instr->operands.array_store.array_ptr);
                    update_val_id(&max_id, instr->operands.array_store.index);
                    update_val_id(&max_id, instr->operands.array_store.value);
                    break;
                case IL_OP_REGION_CAST: update_val_id(&max_id, instr->operands.region_cast.source); break;
                case IL_OP_FUNC_ADDR:
                case IL_OP_CONST:
                case IL_OP_STRING_CONST:
                case IL_OP_GLOBAL_ADDR:
                case IL_OP_ALLOC:
                    // Only result matters
                    break;
                default: break;
            }
        }
    }
    return max_id;
}

void ownership_update_for_instr(OwnershipState* state, const void* mod, const ILFunction* func, const ILInstruction* instr, const ILType** types) {
    (void)func;
    switch (instr->opcode) {
        case IL_OP_LOAD: {
            if (instr->result_type && !il_type_is_copy_mod(mod, instr->result_type)) {
                uint32_t ptr_id = instr->operands.load.ptr;
                if (ptr_id != 0 && ptr_id < state->count) {
                    ownership_set(state, ptr_id, VAL_MOVED);
                }
            }
            break;
        }
        case IL_OP_MOVE: {
            uint32_t source_id = instr->operands.move.source;
            if (source_id != 0 && source_id < state->count) {
                const ILType* source_type = types[source_id];
                if (source_type && !il_type_is_copy_mod(mod, source_type)) {
                    ownership_set(state, source_id, VAL_MOVED);
                }
            }
            break;
        }
        case IL_OP_BITCAST: {
            // Only treat as a consuming move when a Box is bitcast to a raw Ptr
            // (Box::into_raw semantics). Pointer-to-pointer bitcasts (borrows) are not moves.
            uint32_t source_id = instr->operands.bitcast.source;
            if (source_id != 0 && source_id < state->count) {
                const ILType* source_type = types[source_id];
                if (source_type && source_type->kind == IL_TY_BOX &&
                    instr->result_type && instr->result_type->kind == IL_TY_PTR) {
                    ownership_set(state, source_id, VAL_MOVED);
                }
            }
            break;
        }
        case IL_OP_CALL: {
            for (uint32_t arg = 0; arg < instr->operands.call.num_args; arg++) {
                uint32_t arg_id = instr->operands.call.arg_ids[arg];
                if (arg_id != 0 && arg_id < state->count) {
                    const ILType* arg_type = types[arg_id];
                    if (arg_type && !il_type_is_copy_mod(mod, arg_type)) {
                        ownership_set(state, arg_id, VAL_MOVED);
                    }
                }
            }
            break;
        }
        case IL_OP_SYSCALL: {
            if (instr->operands.syscall_op.arg_ids) {
                for (uint32_t arg = 0; arg < instr->operands.syscall_op.num_args; arg++) {
                    uint32_t arg_id = instr->operands.syscall_op.arg_ids[arg];
                    if (arg_id != 0 && arg_id < state->count) {
                        const ILType* arg_type = types[arg_id];
                        if (arg_type && !il_type_is_copy_mod(mod, arg_type)) {
                            ownership_set(state, arg_id, VAL_MOVED);
                        }
                    }
                }
            }
            break;
        }
        case IL_OP_STORE: {
            uint32_t val_id = instr->operands.store.value;
            if (val_id != 0 && val_id < state->count) {
                const ILType* val_type = types[val_id];
                if (val_type && !il_type_is_copy_mod(mod, val_type)) {
                    ownership_set(state, val_id, VAL_MOVED);
                }
            }
            break;
        }
        case IL_OP_DROP: {
            uint32_t val_id = instr->operands.drop.value;
            if (val_id != 0 && val_id < state->count) {
                ownership_set(state, val_id, VAL_MOVED);
            }
            break;
        }
        case IL_OP_FD_CLOSE: {
            uint32_t val_id = instr->operands.fd_close.fd;
            if (val_id != 0 && val_id < state->count) {
                ownership_set(state, val_id, VAL_MOVED);
            }
            break;
        }
        case IL_OP_ASYNC_CLOSE: {
            uint32_t val_id = instr->operands.async_close.ctx;
            if (val_id != 0 && val_id < state->count) {
                ownership_set(state, val_id, VAL_MOVED);
            }
            break;
        }
        case IL_OP_RETURN: {
            uint32_t val_id = instr->operands.ret.value;
            if (val_id != 0 && val_id < state->count) {
                const ILType* val_type = types[val_id];
                if (val_type && !il_type_is_copy_mod(mod, val_type)) {
                    ownership_set(state, val_id, VAL_MOVED);
                }
            }
            break;
        }
        case IL_OP_SUM_CONSTRUCT: {
            uint32_t val_id = instr->operands.sum_construct.payload_id;
            if (val_id != 0 && val_id < state->count) {
                const ILType* val_type = types[val_id];
                if (val_type && !il_type_is_copy_mod(mod, val_type)) {
                    ownership_set(state, val_id, VAL_MOVED);
                }
            }
            break;
        }
        default: break;
    }

    // Then handle the definition: any instruction that produces a result marks it available.
    if (instr->result_id != 0 && instr->result_id < state->count) {
        ownership_set(state, instr->result_id, VAL_AVAILABLE);
    }
}

static const ILFunction* find_func_by_id(const void* mod_ptr, uint32_t id) {
    if (!mod_ptr) return NULL;
    const ILModule* mod = (const ILModule*)mod_ptr;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        if (mod->functions[i]->id == id) return mod->functions[i];
    }
    return NULL;
}

static void infer_result_type(const void* mod, const ILInstruction* instr, const ILType** types, uint32_t ssa_count) {
    switch (instr->opcode) {
        case IL_OP_ADD: case IL_OP_SUB: case IL_OP_MUL: case IL_OP_DIV:
        case IL_OP_REM: case IL_OP_AND: case IL_OP_OR: case IL_OP_XOR:
        case IL_OP_SHL: case IL_OP_SHR:
        case IL_OP_WRAPPING_ADD: case IL_OP_SATURATING_ADD:
            if (instr->operands.binary.left < ssa_count) types[instr->result_id] = types[instr->operands.binary.left];
            break;
        case IL_OP_CMP_LT: case IL_OP_CMP_LE: case IL_OP_CMP_GT:
        case IL_OP_CMP_GE: case IL_OP_CMP_EQ: case IL_OP_CMP_NE:
        case IL_OP_IS_SOME:
            types[instr->result_id] = il_type_bool();
            break;
        case IL_OP_LOAD: {
            uint32_t ptr_id = instr->operands.load.ptr;
            const ILType* pt = (ptr_id < ssa_count) ? types[ptr_id] : NULL;
            if (pt) {
                if (pt->kind == IL_TY_PTR) types[instr->result_id] = pt->as.ptr.pointee;
                else if (pt->kind == IL_TY_BOX) types[instr->result_id] = pt->as.box.pointee;
            }
            break;
        }
        case IL_OP_FIELD_ADDR: {
            uint32_t struct_ptr_id = instr->operands.field_addr.struct_ptr;
            const ILType* pt = (struct_ptr_id < ssa_count) ? types[struct_ptr_id] : NULL;
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
                    rid = struct_ptr_id;
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
            uint32_t base_id = instr->operands.elem_addr.base;
            const ILType* pt = (base_id < ssa_count) ? types[base_id] : NULL;
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
                    rid = base_id;
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

OwnershipAnalysisResult il_func_analyze_ownership(const void* mod, const ILFunction* func) {
    if (!func || func->block_count == 0) return (OwnershipAnalysisResult){0};
    uint32_t ssa_count = il_func_get_max_ssa_id(func) + 1;
    
    const ILType ** types = calloc(ssa_count, sizeof(const ILType*));
    if (!types) return (OwnershipAnalysisResult){0};
    for (uint32_t i = 0; i < func->param_count; i++) {
        if (i + 1 < ssa_count) types[i + 1] = func->param_types[i];
    }
    
    for (uint32_t b = 0; b < func->block_count; b++) {
        for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
            const ILInstruction* instr = func->blocks[b]->instructions[i];
            if (instr->result_id != 0 && instr->result_id < ssa_count && !types[instr->result_id]) {
                if (instr->result_type) {
                    types[instr->result_id] = instr->result_type;
                } else {
                    infer_result_type(mod, instr, types, ssa_count);
                }
            }
        }
    }

    OwnershipState** states = calloc(func->block_count, sizeof(OwnershipState*));
    if (!states) { free(types); return (OwnershipAnalysisResult){0}; }
    for (uint32_t i = 0; i < func->block_count; i++) {
        states[i] = ownership_state_create(ssa_count);
        if (!states[i]) {
            for (uint32_t j = 0; j < i; j++) ownership_state_free(states[j]);
            free(states);
            free(types);
            return (OwnershipAnalysisResult){0};
        }
    }
    
    if (states[0]) {
        for (uint32_t i = 0; i < func->param_count; i++) {
            if (i + 1 < ssa_count) ownership_set(states[0], i + 1, VAL_AVAILABLE);
        }
    }

    bool changed = true;
    while (changed) {
        changed = false;
        for (uint32_t b = 0; b < func->block_count; b++) {
            OwnershipState* current = ownership_state_copy(states[b]);
            for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                ownership_update_for_instr(current, mod, func, func->blocks[b]->instructions[i], types);
            }
            for (uint32_t s = 0; s < func->blocks[b]->succ_count; s++) {
                uint32_t succ_idx = func->blocks[b]->successors[s]->rpo_index;
                if (succ_idx < func->block_count) {
                    if (ownership_state_merge(states[succ_idx], current)) changed = true;
                }
            }
            ownership_state_free(current);
        }
    }
    return (OwnershipAnalysisResult){ .states = states, .types = types, .ssa_count = ssa_count };
}

void il_func_ownership_result_free(OwnershipAnalysisResult res, uint32_t block_count) {
    if (res.states) {
        for (uint32_t i = 0; i < block_count; i++) {
            ownership_state_free(res.states[i]);
        }
        free(res.states);
    }
    if (res.types) free(res.types);
}
