#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include "il_read.h"

typedef struct {
    uint32_t line;
    uint32_t col;
} SourceLoc;

static SourceLoc current_loc = {1, 1};
static ILModule* current_mod = NULL;

static void skip_whitespace(const char** src) {
    while (**src) {
        if (**src == '\n') {
            current_loc.line++;
            current_loc.col = 1;
            (*src)++;
        } else if (isspace((unsigned char)**src)) {
            current_loc.col++;
            (*src)++;
        } else if (**src == '#' || (**src == '/' && *(*src + 1) == '/')) {
            while (**src && **src != '\n') {
                current_loc.col++;
                (*src)++;
            }
        } else {
            break;
        }
    }
}

static bool match(const char** src, const char* pat) {
    size_t len = strlen(pat);
    if (strncmp(*src, pat, len) == 0) {
        *src += len;
        current_loc.col += (uint32_t)len;
        return true;
    }
    return false;
}

static bool skip_match(const char** src, const char* pat) {
    skip_whitespace(src);
    return match(src, pat);
}

static uint32_t parse_uint32(const char** src) {
    char* next;
    uint32_t val = (uint32_t)strtoul(*src, &next, 10);
    current_loc.col += (uint32_t)(next - *src);
    *src = next;
    return val;
}

static void parse_region(const char** src, char* out_region, size_t max_len) {
    skip_whitespace(src);
    if (**src == '\'') {
        (*src)++; // Strip leading quote
        current_loc.col++;
    }
    size_t i = 0;
    while (**src && (isalnum((unsigned char)**src) || **src == '_') && i < max_len - 1) {
        current_loc.col++;
        out_region[i++] = *(*src)++;
    }
    out_region[i] = '\0';
}

static uint32_t read_region_id(const char** src) {
    char region_name[16];
    parse_region(src, region_name, sizeof(region_name));
    return il_region_parse(current_mod ? current_mod->region_table : NULL, region_name);
}

static uint32_t parse_ssa_id(const char** src) {
    skip_whitespace(src);
    while (**src && strchr("vbfg@", **src)) {
        (*src)++;
        current_loc.col++;
    }
    return parse_uint32(src);
}

const ILType* il_read_type(const char* src, const char** end) {
    if (src == NULL) return NULL;
    skip_whitespace(&src);

    const ILType* t = NULL;
    if (match(&src, "unit")) {
        t = il_type_unit();
    } else if (match(&src, "bool")) {
        t = il_type_bool();
    } else if (match(&src, "u8")) {
        t = il_type_u8();
    } else if (match(&src, "u16")) {
        t = il_type_u16();
    } else if (match(&src, "u32")) {
        t = il_type_u32();
    } else if (match(&src, "u64")) {
        t = il_type_u64();
    } else if (match(&src, "i8")) {
        t = il_type_i8();
    } else if (match(&src, "i16")) {
        t = il_type_i16();
    } else if (match(&src, "i32")) {
        t = il_type_i32();
    } else if (match(&src, "i64")) {
        t = il_type_i64();
    } else if (match(&src, "f32")) {
        t = il_type_f32();
    } else if (match(&src, "f64")) {
        t = il_type_f64();
    } else if (match(&src, "usize")) {
        t = il_type_usize();
    } else if (match(&src, "isize")) {
        t = il_type_isize();
    } else if (match(&src, "never")) {
        t = il_type_never();
    } else if (strncmp(src, "Ptr", 3) == 0) {
        bool is_mut = false;
        if (match(&src, "PtrMut<")) is_mut = true;
        else if (match(&src, "Ptr<")) is_mut = false;
        else return NULL;

        const ILType* pointee = il_read_type(src, &src);
        uint32_t region_id = REGION_STATIC;
        skip_whitespace(&src);
        if (match(&src, ",")) {
            region_id = read_region_id(&src);
            skip_whitespace(&src);
        }
        match(&src, ">");
        t = il_type_ptr(pointee, region_id, is_mut);
    } else if (match(&src, "BoxMut<")) {
        const ILType* pointee = il_read_type(src, &src);
        t = il_type_box(pointee, REGION_HEAP, true);
        skip_whitespace(&src);
        match(&src, ">");
    } else if (match(&src, "Box<")) {
        const ILType* pointee = il_read_type(src, &src);
        t = il_type_box(pointee, REGION_HEAP, false);
        skip_whitespace(&src);
        match(&src, ">");
    } else if (match(&src, "SliceMut<")) {
        const ILType* element = il_read_type(src, &src);
        uint32_t region_id = REGION_STATIC;
        skip_whitespace(&src);
        if (match(&src, ",")) {
            region_id = read_region_id(&src);
        }
        skip_whitespace(&src);
        match(&src, ">");
        t = il_type_slice(element, region_id, true);
    } else if (match(&src, "Slice<")) {
        const ILType* element = il_read_type(src, &src);
        uint32_t region_id = REGION_STATIC;
        skip_whitespace(&src);
        if (match(&src, ",")) {
            region_id = read_region_id(&src);
        }
        skip_whitespace(&src);
        match(&src, ">");
        t = il_type_slice(element, region_id, false);
    } else if (match(&src, "[")) {
        const ILType* element = il_read_type(src, &src);
        uint64_t length = 0;
        skip_whitespace(&src);
        if (match(&src, ";")) {
            skip_whitespace(&src);
            char* next;
            length = (uint64_t)strtoull(src, &next, 10);
            src = next;
            skip_whitespace(&src);
            match(&src, "]");
        }
        t = il_type_array(element, length);
    } else if (match(&src, "T")) {
        char* next;
        uint32_t id = (uint32_t)strtoul(src, &next, 10);
        src = next;
        t = il_type_struct(NULL, id);
    } else if (match(&src, "async_context")) {
        t = il_type_async_context();
    } else if (match(&src, "fn(")) {
        const ILType ** param_types = NULL;
        uint32_t param_count = 0;
        bool is_variadic = false;
        while (*src != ')' && *src != '\0') {
            skip_whitespace(&src);
            if (match(&src, "...")) {
                is_variadic = true;
                break;
            }
            const ILType ** new_param_types = realloc(param_types, sizeof(const ILType*) * (param_count + 1));
            if (!new_param_types) {
                free(param_types);
                return NULL;
            }
            param_types = new_param_types;
            param_types[param_count++] = il_read_type(src, &src);
            skip_whitespace(&src);
            if (!match(&src, ",")) break;
        }
        match(&src, ")");
        skip_whitespace(&src);
        match(&src, "->");
        const ILType* return_type = il_read_type(src, &src);
        t = il_type_fn(return_type, param_types, param_count, is_variadic);
        free(param_types);
    } else if (match(&src, "(")) {
        const ILType ** elements = NULL;
        uint32_t count = 0;
        while (*src != ')' && *src != '\0') {
            skip_whitespace(&src);
            const ILType ** new_elements = realloc(elements, sizeof(const ILType*) * (count + 1));
            if (!new_elements) {
                free(elements);
                return NULL;
            }
            elements = new_elements;
            elements[count++] = il_read_type(src, &src);
            skip_whitespace(&src);
            if (!match(&src, ",")) break;
        }
        match(&src, ")");
        t = il_type_tuple(elements, count);
        free(elements);
    } else if (match(&src, "fd<")) {
        skip_whitespace(&src);
        ILFdCap cap;
        if (match(&src, "rw")) {
            cap = IL_CAP_RW;
        } else if (match(&src, "r")) {
            cap = IL_CAP_READ;
        } else if (match(&src, "w")) {
            cap = IL_CAP_WRITE;
        } else {
            cap = IL_CAP_RW; /* default */
        }
        skip_whitespace(&src);
        match(&src, ">");
        t = il_type_fd(cap);
    }

    if (end) *end = src;
    return t;
}

static void read_binary_instr(const char** src, ILInstruction* instr) {
    instr->operands.binary.left = parse_ssa_id(src);
    skip_match(src, ",");
    instr->operands.binary.right = parse_ssa_id(src);
}

static void read_mem_instr(const char** src, ILInstruction* instr) {
    switch (instr->opcode) {
        case IL_OP_ALLOC: {
            char region_name[16];
            parse_region(src, region_name, sizeof(region_name));
            if (current_mod) {
                instr->operands.alloc.region_id = string_table_intern(current_mod->region_table, region_name);
            } else {
                if (isdigit(region_name[0])) {
                    uint32_t rid = (uint32_t)atoi(region_name);
                    if (rid == 0) instr->operands.alloc.region_id = REGION_STATIC;
                    else instr->operands.alloc.region_id = rid;
                } else if (strcmp(region_name, "static") == 0) {
                    instr->operands.alloc.region_id = REGION_STATIC;
                } else if (strcmp(region_name, "local") == 0) {
                    instr->operands.alloc.region_id = REGION_LOCAL;
                } else if (strcmp(region_name, "heap") == 0) {
                    instr->operands.alloc.region_id = REGION_HEAP;
                }
            }
            skip_match(src, ",");
            il_read_type(*src, src); // Consume but don't store (recovered from result_type)
            break;
        }
        case IL_OP_LOAD:
            instr->operands.load.ptr = parse_ssa_id(src);
            break;
        case IL_OP_STORE:
            instr->operands.store.ptr = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.store.value = parse_ssa_id(src);
            break;
        case IL_OP_DROP:
            instr->operands.drop.value = parse_ssa_id(src);
            break;
        case IL_OP_GLOBAL_ADDR:
            skip_whitespace(src);
            if (**src == 'g') (*src)++;
            instr->operands.global_addr.global_id = parse_uint32(src);
            break;
        case IL_OP_FUNC_ADDR:
            skip_whitespace(src);
            if (**src == 'f') (*src)++;
            instr->operands.func_addr.func_id = parse_uint32(src);
            break;
        case IL_OP_FIELD_ADDR:
            instr->operands.field_addr.struct_ptr = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.field_addr.field_index = parse_uint32(src);
            break;
        default: break;
    }
}

static void read_control_flow_instr(const char** src, ILInstruction* instr) {
    switch (instr->opcode) {
        case IL_OP_RETURN:
            skip_whitespace(src);
            if (**src == 'v') {
                instr->operands.ret.value = parse_ssa_id(src);
            } else {
                instr->operands.ret.value = 0;
            }
            break;
        case IL_OP_BRANCH:
            instr->operands.branch.condition = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.branch.then_block_id = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.branch.else_block_id = parse_ssa_id(src);
            break;
        case IL_OP_JUMP:
            instr->operands.jump.target_block_id = parse_ssa_id(src);
            break;
        case IL_OP_BOUNDS_CHECK:
            instr->operands.bounds_check.index = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.bounds_check.length = parse_ssa_id(src);
            break;
        default: break;
    }
}

static void read_sum_instr(const char** src, ILInstruction* instr) {
    switch (instr->opcode) {
        case IL_OP_IS_SOME:
            instr->operands.move.source = parse_ssa_id(src);
            break;
        case IL_OP_UNWRAP:
            instr->operands.move.source = parse_ssa_id(src);
            break;
        case IL_OP_VARIANT_MATCH:
            // Two forms: the terminator `variant_match vS, K, @bT, @bN`, and the value form
            // `vR: bool = variant_match vS, Type, K` that ZIL has used since c66fe15. The value
            // form names the sum type before the index and has no target blocks; its absent
            // targets are IL_NO_BLOCK, since 0 is a real block id (@b0) in ZIL text.
            instr->operands.variant_match.sum_ptr = parse_ssa_id(src);
            skip_match(src, ",");
            skip_whitespace(src);
            if (**src && !(**src >= '0' && **src <= '9')) {
                while (**src && **src != ',' && **src != '\n') (*src)++;
                skip_match(src, ",");
            }
            instr->operands.variant_match.variant_index = parse_uint32(src);
            instr->operands.variant_match.target_block_id = IL_NO_BLOCK;
            instr->operands.variant_match.next_block_id = IL_NO_BLOCK;
            skip_match(src, ",");
            skip_whitespace(src);
            if (match(src, "@")) {
                instr->operands.variant_match.target_block_id = parse_ssa_id(src);
            }
            skip_match(src, ",");
            skip_whitespace(src);
            if (match(src, "@")) {
                instr->operands.variant_match.next_block_id = parse_ssa_id(src);
            }
            break;
        case IL_OP_SUM_CONSTRUCT:
            skip_whitespace(src);
            if (match(src, "T")) {
                instr->operands.sum_construct.type_def_id = parse_uint32(src);
            } else {
                instr->operands.sum_construct.type_def_id = parse_uint32(src);
            }
            skip_match(src, ",");
            instr->operands.sum_construct.variant_index = parse_uint32(src);
            skip_match(src, ",");
            instr->operands.sum_construct.payload_id = parse_ssa_id(src);
            break;
        default: break;
    }
}

static void read_slice_instr(const char** src, ILInstruction* instr) {
    switch (instr->opcode) {
        case IL_OP_SLICE_LOAD:
            instr->operands.slice_load.slice_ptr = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.slice_load.index = parse_ssa_id(src);
            break;
        case IL_OP_SLICE_STORE:
            instr->operands.slice_store.slice_ptr = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.slice_store.index = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.slice_store.value = parse_ssa_id(src);
            break;
        case IL_OP_SLICE_LEN:
        case IL_OP_SLICE_DATA:
            instr->operands.slice_op.slice_ptr = parse_ssa_id(src);
            break;
        case IL_OP_SLICE_CONSTRUCT:
            instr->operands.slice_construct.ptr = parse_ssa_id(src);
            skip_match(src, ",");
            instr->operands.slice_construct.len = parse_ssa_id(src);
            break;
        default: break;
    }
}

static void read_conversion_instr(const char** src, ILInstruction* instr) {
    switch (instr->opcode) {
        case IL_OP_MOVE:
        case IL_OP_BITCAST:
            instr->operands.move.source = parse_ssa_id(src);
            break;
        case IL_OP_REGION_CAST: {
            char region_name[16];
            parse_region(src, region_name, sizeof(region_name));
            if (current_mod) {
                instr->operands.region_cast.target_region_id = string_table_intern(current_mod->region_table, region_name);
            } else {
                if (strcmp(region_name, "static") == 0) instr->operands.region_cast.target_region_id = REGION_STATIC;
                else if (strcmp(region_name, "local") == 0) instr->operands.region_cast.target_region_id = REGION_LOCAL;
                else if (strcmp(region_name, "heap") == 0) instr->operands.region_cast.target_region_id = REGION_HEAP;
            }
            skip_match(src, ",");
            instr->operands.region_cast.source = parse_ssa_id(src);
            break;
        }
        default: break;
    }
}

static void read_io_instr(const char** src, ILInstruction* instr) {
    switch (instr->opcode) {
        case IL_OP_FD_OPEN:
            skip_whitespace(src);
            instr->operands.fd_open.path = parse_ssa_id(src);
            skip_whitespace(src);
            if (match(src, ",")) {
                skip_whitespace(src);
                instr->operands.fd_open.flags = parse_ssa_id(src);
            }
            skip_whitespace(src);
            if (match(src, ",")) {
                skip_whitespace(src);
                instr->operands.fd_open.mode = parse_ssa_id(src);
            }
            break;
        case IL_OP_FD_CLOSE:
            skip_whitespace(src);
            instr->operands.fd_close.fd = parse_ssa_id(src);
            break;
        case IL_OP_FD_READ:
        case IL_OP_FD_WRITE:
            skip_whitespace(src);
            instr->operands.fd_io.fd = parse_ssa_id(src);
            skip_whitespace(src);
            if (match(src, ",")) {
                skip_whitespace(src);
                instr->operands.fd_io.buf = parse_ssa_id(src);
                skip_whitespace(src);
                if (match(src, ",")) {
                    skip_whitespace(src);
                    instr->operands.fd_io.count = parse_ssa_id(src);
                }
            }
            break;
        case IL_OP_ASYNC_SETUP:
            skip_whitespace(src);
            instr->operands.async_setup.entries = parse_ssa_id(src);
            break;
        case IL_OP_ASYNC_ENTER:
            skip_whitespace(src);
            instr->operands.async_enter.ctx = parse_ssa_id(src);
            skip_whitespace(src);
            if (match(src, ",")) {
                skip_whitespace(src);
                instr->operands.async_enter.to_submit = parse_ssa_id(src);
            }
            skip_whitespace(src);
            if (match(src, ",")) {
                skip_whitespace(src);
                instr->operands.async_enter.min_complete = parse_ssa_id(src);
            }
            break;
        case IL_OP_ASYNC_CLOSE:
            skip_whitespace(src);
            instr->operands.async_close.ctx = parse_ssa_id(src);
            break;
        default: break;
    }
}

static void read_other_instr(const char** src, ILInstruction* instr) {
    switch (instr->opcode) {
        case IL_OP_CALL:
            instr->operands.call.func_id = parse_ssa_id(src);
            skip_whitespace(src);
            if (match(src, "(")) {
                uint32_t capacity = 4;
                instr->operands.call.arg_ids = calloc(capacity, sizeof(uint32_t));
                uint32_t count = 0;
                while (**src && **src != ')') {
                    skip_whitespace(src);
                    if (**src == 'v') {
                        if (count >= capacity) {
                            capacity *= 2;
                            instr->operands.call.arg_ids = realloc(instr->operands.call.arg_ids, sizeof(uint32_t) * capacity);
                        }
                        instr->operands.call.arg_ids[count] = parse_ssa_id(src);
                        count++;
                    }
                    skip_whitespace(src);
                    if (match(src, ",")) continue;
                    else break;
                }
                match(src, ")");
                instr->operands.call.num_args = count;
            } else {
                instr->operands.call.arg_ids = NULL;
                instr->operands.call.num_args = 0;
            }
            break;
        case IL_OP_CALL_PTR:
            instr->operands.call_ptr.func_ptr_id = parse_ssa_id(src);
            skip_whitespace(src);
            if (match(src, "(")) {
                uint32_t capacity = 4;
                instr->operands.call_ptr.arg_ids = calloc(capacity, sizeof(uint32_t));
                uint32_t count = 0;
                while (**src && **src != ')') {
                    skip_whitespace(src);
                    if (**src == 'v') {
                        if (count >= capacity) {
                            capacity *= 2;
                            instr->operands.call_ptr.arg_ids = realloc(instr->operands.call_ptr.arg_ids, sizeof(uint32_t) * capacity);
                        }
                        instr->operands.call_ptr.arg_ids[count] = parse_ssa_id(src);
                        count++;
                    }
                    skip_whitespace(src);
                    if (match(src, ",")) continue;
                    else break;
                }
                match(src, ")");
                instr->operands.call_ptr.num_args = count;
            }
            break;
        case IL_OP_SYSCALL:
            skip_whitespace(src);
            instr->operands.syscall_op.syscall_num = parse_uint32(src);
            skip_whitespace(src);
            if (match(src, ",")) {
                uint32_t capacity = 4;
                instr->operands.syscall_op.arg_ids = calloc(capacity, sizeof(uint32_t));
                uint32_t count = 0;
                while (true) {
                    skip_whitespace(src);
                    if (**src == 'v') {
                        if (count >= capacity) {
                            uint32_t old_capacity = capacity;
                            capacity *= 2;
                            instr->operands.syscall_op.arg_ids = realloc(instr->operands.syscall_op.arg_ids, sizeof(uint32_t) * capacity);
                            memset(instr->operands.syscall_op.arg_ids + old_capacity, 0, sizeof(uint32_t) * (capacity - old_capacity));
                        }
                        instr->operands.syscall_op.arg_ids[count] = parse_ssa_id(src);
                        count++;
                    } else {
                        break;
                    }
                    skip_whitespace(src);
                    if (match(src, ",")) continue;
                    else break;
                }
                instr->operands.syscall_op.num_args = count;
            } else {
                instr->operands.syscall_op.arg_ids = NULL;
                instr->operands.syscall_op.num_args = 0;
            }
            break;
        case IL_OP_CONST: {
            skip_whitespace(src);
            char* next;
            if (instr->result_type && (instr->result_type->kind == IL_TY_F32 || instr->result_type->kind == IL_TY_F64)) {
                instr->operands.const_val.u.fval = strtod(*src, &next);
            } else {
                instr->operands.const_val.u.val = (uint64_t)strtoull(*src, &next, 10);
            }
            current_loc.col += (uint32_t)(next - *src);
            *src = next;
            break;
        }
        case IL_OP_PHI: {
            skip_whitespace(src);
            if (match(src, "[")) {
                uint32_t capacity = 4;
                instr->operands.phi.incoming = calloc(capacity, sizeof(ILPhiIncoming));
                uint32_t count = 0;
                while (**src && **src != ']') {
                    skip_whitespace(src);
                    if (match(src, "@")) {
                        if (**src == 'b') (*src)++;
                        uint32_t bid = parse_uint32(src);
                        skip_match(src, ":");
                        uint32_t vid = parse_ssa_id(src);
                        
                        if (count >= capacity) {
                            capacity *= 2;
                            instr->operands.phi.incoming = realloc(instr->operands.phi.incoming, sizeof(ILPhiIncoming) * capacity);
                        }
                        instr->operands.phi.incoming[count].block_id = bid;
                        instr->operands.phi.incoming[count].value_id = vid;
                        count++;
                    }
                    skip_whitespace(src);
                    if (match(src, ",")) continue;
                    else break;
                }
                match(src, "]");
                instr->operands.phi.num_incoming = count;
            } else {
                instr->operands.phi.incoming = NULL;
                instr->operands.phi.num_incoming = 0;
            }
            break;
        }
        default: break;
    }
}

ILInstruction* il_read_instr(const char* src, const char** end) {
    if (src == NULL) return NULL;
    skip_whitespace(&src);

    const char* saved_src = src;
    uint32_t result_id = 0;
    const ILType* result_type = NULL;

    if (*src == 'v') {
        uint32_t id = parse_ssa_id(&src);
        skip_whitespace(&src);
        if (*src == ':') {
            src++;
            current_loc.col++;
            result_id = id;
            result_type = il_read_type(src, &src);
            skip_whitespace(&src);
            if (match(&src, "=")) {
                skip_whitespace(&src);
            }
        } else {
            src = saved_src;
        }
    }

    skip_whitespace(&src);
    SourceLoc instr_loc = current_loc;

    ILOpcode opcode = IL_OP_INVALID;
    if (skip_match(&src, "add")) opcode = IL_OP_ADD;
    else if (skip_match(&src, "sub")) opcode = IL_OP_SUB;
    else if (skip_match(&src, "mul")) opcode = IL_OP_MUL;
    else if (skip_match(&src, "div")) opcode = IL_OP_DIV;
    else if (skip_match(&src, "rem")) opcode = IL_OP_REM;
    else if (skip_match(&src, "and")) opcode = IL_OP_AND;
    else if (skip_match(&src, "or")) opcode = IL_OP_OR;
    else if (skip_match(&src, "xor")) opcode = IL_OP_XOR;
    else if (skip_match(&src, "shl")) opcode = IL_OP_SHL;
    else if (skip_match(&src, "shr")) opcode = IL_OP_SHR;
    else if (skip_match(&src, "lt")) opcode = IL_OP_CMP_LT;
    else if (skip_match(&src, "le")) opcode = IL_OP_CMP_LE;
    else if (skip_match(&src, "gt")) opcode = IL_OP_CMP_GT;
    else if (skip_match(&src, "ge")) opcode = IL_OP_CMP_GE;
    else if (skip_match(&src, "eq")) opcode = IL_OP_CMP_EQ;
    else if (skip_match(&src, "ne")) opcode = IL_OP_CMP_NE;
    else if (skip_match(&src, "wrapping_add")) opcode = IL_OP_WRAPPING_ADD;
    else if (skip_match(&src, "wrapping_sub")) opcode = IL_OP_WRAPPING_SUB;
    else if (skip_match(&src, "wrapping_mul")) opcode = IL_OP_WRAPPING_MUL;
    else if (skip_match(&src, "saturating_add")) opcode = IL_OP_SATURATING_ADD;
    else if (skip_match(&src, "checked_add")) opcode = IL_OP_CHECKED_ADD;
    else if (skip_match(&src, "checked_sub")) opcode = IL_OP_CHECKED_SUB;
    else if (skip_match(&src, "checked_mul")) opcode = IL_OP_CHECKED_MUL;
    else if (skip_match(&src, "alloc")) opcode = IL_OP_ALLOC;
    else if (skip_match(&src, "load")) opcode = IL_OP_LOAD;
    else if (skip_match(&src, "store")) opcode = IL_OP_STORE;
    else if (skip_match(&src, "drop")) opcode = IL_OP_DROP;
    else if (skip_match(&src, "bounds_check")) opcode = IL_OP_BOUNDS_CHECK;
    else if (skip_match(&src, "slice_load")) opcode = IL_OP_SLICE_LOAD;
    else if (skip_match(&src, "slice_store")) opcode = IL_OP_SLICE_STORE;
    else if (skip_match(&src, "slice_len")) opcode = IL_OP_SLICE_LEN;
    else if (skip_match(&src, "slice_data")) opcode = IL_OP_SLICE_DATA;
    else if (skip_match(&src, "slice_construct")) opcode = IL_OP_SLICE_CONSTRUCT;
    else if (skip_match(&src, "move")) opcode = IL_OP_MOVE;
    else if (skip_match(&src, "bitcast")) opcode = IL_OP_BITCAST;
    else if (skip_match(&src, "region_cast")) opcode = IL_OP_REGION_CAST;
    else if (skip_match(&src, "global_addr")) opcode = IL_OP_GLOBAL_ADDR;
    else if (skip_match(&src, "func_addr")) opcode = IL_OP_FUNC_ADDR;
    else if (skip_match(&src, "field_addr")) opcode = IL_OP_FIELD_ADDR;
    else if (skip_match(&src, "is_some")) opcode = IL_OP_IS_SOME;
    else if (skip_match(&src, "unwrap")) opcode = IL_OP_UNWRAP;
    else if (skip_match(&src, "array_construct")) opcode = IL_OP_ARRAY_CONSTRUCT;
    else if (skip_match(&src, "array_load")) opcode = IL_OP_ARRAY_LOAD;
    else if (skip_match(&src, "array_store")) opcode = IL_OP_ARRAY_STORE;
    else if (skip_match(&src, "sum_construct")) opcode = IL_OP_SUM_CONSTRUCT;
    else if (skip_match(&src, "variant_match")) opcode = IL_OP_VARIANT_MATCH;
    else if (skip_match(&src, "string_const")) opcode = IL_OP_STRING_CONST;
    else if (skip_match(&src, "syscall")) opcode = IL_OP_SYSCALL;
    else if (skip_match(&src, "const")) opcode = IL_OP_CONST;
    else if (skip_match(&src, "phi")) opcode = IL_OP_PHI;
    else if (skip_match(&src, "ret")) opcode = IL_OP_RETURN;
    else if (skip_match(&src, "branch")) opcode = IL_OP_BRANCH;
    else if (skip_match(&src, "jump")) opcode = IL_OP_JUMP;
    else if (skip_match(&src, "call_ptr")) opcode = IL_OP_CALL_PTR;
    else if (skip_match(&src, "call")) opcode = IL_OP_CALL;
    else if (skip_match(&src, "fd_open"))        opcode = IL_OP_FD_OPEN;
    else if (skip_match(&src, "fd_close"))       opcode = IL_OP_FD_CLOSE;
    else if (skip_match(&src, "fd_read"))        opcode = IL_OP_FD_READ;
    else if (skip_match(&src, "fd_write"))       opcode = IL_OP_FD_WRITE;
    else if (skip_match(&src, "async_setup"))    opcode = IL_OP_ASYNC_SETUP;
    else if (skip_match(&src, "async_enter"))    opcode = IL_OP_ASYNC_ENTER;
    else if (skip_match(&src, "async_close"))    opcode = IL_OP_ASYNC_CLOSE;

    if (opcode == IL_OP_INVALID) {
        
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) {
        
        return NULL;
    }
    instr->line = (uint16_t)instr_loc.line;
    instr->col = (uint8_t)instr_loc.col;
    instr->opcode = (uint8_t)opcode;
    instr->result_id = result_id;
    instr->result_type = result_type;

    switch (instr->opcode) {
        case IL_OP_ADD:
        case IL_OP_SUB:
        case IL_OP_MUL:
        case IL_OP_DIV:
        case IL_OP_REM:
        case IL_OP_AND:
        case IL_OP_OR:
        case IL_OP_XOR:
        case IL_OP_SHL:
        case IL_OP_SHR:
        case IL_OP_CMP_LT:
        case IL_OP_CMP_LE:
        case IL_OP_CMP_GT:
        case IL_OP_CMP_GE:
        case IL_OP_CMP_EQ:
        case IL_OP_CMP_NE:
        case IL_OP_WRAPPING_ADD:
        case IL_OP_WRAPPING_SUB:
        case IL_OP_WRAPPING_MUL:
        case IL_OP_SATURATING_ADD:
        case IL_OP_CHECKED_ADD:
        case IL_OP_CHECKED_SUB:
        case IL_OP_CHECKED_MUL:
            read_binary_instr(&src, instr);
            break;
        case IL_OP_ALLOC:
        case IL_OP_LOAD:
        case IL_OP_STORE:
        case IL_OP_DROP:
        case IL_OP_GLOBAL_ADDR:
        case IL_OP_FUNC_ADDR:
        case IL_OP_FIELD_ADDR:
            read_mem_instr(&src, instr);
            break;
        case IL_OP_RETURN:
        case IL_OP_BRANCH:
        case IL_OP_JUMP:
        case IL_OP_BOUNDS_CHECK:
            read_control_flow_instr(&src, instr);
            break;
        case IL_OP_IS_SOME:
        case IL_OP_UNWRAP:
        case IL_OP_VARIANT_MATCH:
        case IL_OP_SUM_CONSTRUCT:
            read_sum_instr(&src, instr);
            break;
        case IL_OP_SLICE_LOAD:
        case IL_OP_SLICE_STORE:
        case IL_OP_SLICE_LEN:
        case IL_OP_SLICE_CONSTRUCT:
            read_slice_instr(&src, instr);
            break;
        case IL_OP_MOVE:
        case IL_OP_BITCAST:
        case IL_OP_REGION_CAST:
            read_conversion_instr(&src, instr);
            break;
        case IL_OP_STRING_CONST: {
            skip_whitespace(&src);
            if (*src == '"') {
                src++;
                size_t capacity = 1024;
                char* str = malloc(capacity);
                uint32_t len = 0;
                while (*src && *src != '"') {
                    if (len + 1 >= capacity) {
                        capacity *= 2;
                        char* new_str = realloc(str, capacity);
                        if (!new_str) {
                            free(str);
                            free(instr);
                            return NULL;
                        }
                        str = new_str;
                    }
                    if (*src == '\\' && *(src + 1)) {
                        src++;
                        if (*src == 'n') str[len++] = '\n';
                        else if (*src == 'r') str[len++] = '\r';
                        else if (*src == 't') str[len++] = '\t';
                        else if (*src == '0') str[len++] = '\0';
                        else if (*src == '\\') str[len++] = '\\';
                        else if (*src == '"') str[len++] = '"';
                        else if (*src == '\'') str[len++] = '\'';
                        else if (*src == 'x') {
                            src++;
                            uint8_t val = 0;
                            int count = 0;
                            while (count < 2 && *src && isxdigit(*src)) {
                                char hc = *src++;
                                uint8_t digit = 0;
                                if (isdigit(hc)) digit = (uint8_t)(hc - '0');
                                else if (hc >= 'a' && hc <= 'f') digit = (uint8_t)(hc - 'a' + 10);
                                else if (hc >= 'A' && hc <= 'F') digit = (uint8_t)(hc - 'A' + 10);
                                val = (uint8_t)(val * 16 + digit);
                                count++;
                            }
                            str[len++] = (char)val;
                            src--; // Back up because of src++ at end of loop
                        }
                        else str[len++] = *src;
                    } else {
                        str[len++] = *src;
                    }
                    src++;
                }
                str[len] = '\0';
                if (*src == '"') src++;
                instr->operands.string_literal.val = str;
                instr->operands.string_literal.len = len;
            }
            break;
        }
        case IL_OP_FD_OPEN:
        case IL_OP_FD_CLOSE:
        case IL_OP_FD_READ:
        case IL_OP_FD_WRITE:
        case IL_OP_ASYNC_SETUP:
        case IL_OP_ASYNC_ENTER:
        case IL_OP_ASYNC_CLOSE:
            read_io_instr(&src, instr);
            break;
        case IL_OP_CALL:
        case IL_OP_CALL_PTR:
        case IL_OP_SYSCALL:
        case IL_OP_CONST:
        case IL_OP_PHI:
            read_other_instr(&src, instr);
            break;
        default: break;
    }

    if (end) *end = src;
    return instr;
}

ILFunction* il_read_func(const char* src, const char** end) {
    if (src == NULL) return NULL;
    skip_whitespace(&src);

    if (!match(&src, "f")) return NULL;
    uint32_t id = parse_uint32(&src);
    skip_whitespace(&src);
    if (!match(&src, ":")) return NULL;
    
    const ILType* ret_ty = il_read_type(src, &src);
    skip_whitespace(&src);

    char name[64] = {0};
    int i = 0;
    while (*src && (isalnum((unsigned char)*src) || *src == '_') && i < 63) {
        name[i++] = *src++;
    }
    
    ILFunction* func = il_func_create_synthetic(id, name, ret_ty);
    if (!func) return NULL;

    skip_whitespace(&src);
    if (match(&src, "(")) {
        while (*src && *src != ')') {
            skip_whitespace(&src);
            // Check for name:
            const char* temp = src;
            while (*temp && (isalnum((unsigned char)*temp) || *temp == '_')) temp++;
            skip_whitespace(&temp);
            if (*temp == ':') {
                src = temp + 1;
            }
            
            if (match(&src, "...")) {
                func->is_variadic = true;
                break;
            }
            
            const ILType* param = il_read_type(src, &src);
            if (param) il_func_add_param(func, param);
            else break;
            skip_match(&src, ",");
        }
        match(&src, ")");
    }

    skip_whitespace(&src);
    if (match(&src, "{")) {
        ILBasicBlock* current_block = NULL;
        while (*src && *src != '}') {
            skip_whitespace(&src);
            if (*src == '\0') break;
            if (*src == '@') {
                src++; // Skip '@'
                if (*src == 'b') src++;
                uint32_t bid = parse_uint32(&src);
                skip_match(&src, ":");
                current_block = il_block_create(bid);
                il_func_add_block(func, current_block);
            } else if (current_block) {
                const char* prev_src = src;
                ILInstruction* instr = il_read_instr(src, &src);
                if (instr) {
                    il_block_add_instr(current_block, instr);
                } else {
                    if (src == prev_src) src++;
                }
            } else {
                src++;
            }
            skip_whitespace(&src);
        }
        match(&src, "}");
    }

    il_func_resolve_successors(func);
    if (end) *end = src;
    return func;
}

ILGlobal* il_read_global(const char* src, const char** end) {
    if (src == NULL) return NULL;
    skip_whitespace(&src);

    bool is_const = false;
    if (match(&src, "const")) {
        is_const = true;
        skip_whitespace(&src);
    }

    if (!match(&src, "global")) return NULL;
    skip_whitespace(&src);
    if (*src == 'g') src++;
    uint32_t id = parse_uint32(&src);
    skip_whitespace(&src);
    if (!match(&src, ":")) return NULL;
    
    const ILType* ty = il_read_type(src, &src);
    skip_whitespace(&src);

    char name[64] = {0};
    int i = 0;
    while (*src && (isalnum((unsigned char)*src) || *src == '_') && i < 63) {
        name[i++] = *src++;
    }
    
    ILGlobal* global = il_global_create_synthetic(id, name, ty, is_const);
    if (!global) {
        return NULL;
    }

    skip_whitespace(&src);
    if (match(&src, "=")) {
        skip_whitespace(&src);
        if (*src == '{') {
            src++;
            uint8_t data[1024] = {0};
            uint32_t len = 0;
            while (*src && *src != '}' && len < 1024) {
                skip_whitespace(&src);
                char* next;
                data[len++] = (uint8_t)strtoul(src, &next, 0);
                src = next;
                skip_match(&src, ",");
            }
            match(&src, "}");
            if (len > 0) il_global_set_init_data(global, data, len);
        } else {
            // Support simple decimal integer as well
            char* next;
            uint64_t val = (uint64_t)strtoull(src, &next, 0);
            src = next;
            // Assuming little-endian for simplicity for now
            size_t size = il_type_size(current_mod, ty);
            if (size > 0) {
                uint8_t* buf = calloc(1, size);
                if (buf) {
                    size_t copy_size = size < sizeof(val) ? size : sizeof(val);
                    memcpy(buf, &val, copy_size);
                    il_global_set_init_data(global, buf, (uint32_t)size);
                    free(buf);
                }
            }
        }
    }

    if (end) *end = src;
     // il_global_create copies it
    return global;
}

ILTypeDef* il_read_type_def(const char* src, const char** end) {
    if (!match(&src, "type")) return NULL;
    skip_whitespace(&src);
    if (*src != 'T') return NULL;
    src++;
    char* next;
    uint32_t id = (uint32_t)strtoul(src, &next, 10);
    src = next;
    skip_match(&src, ":");
    skip_whitespace(&src);

    bool is_sum = false;
    if (match(&src, "struct")) is_sum = false;
    else if (match(&src, "sum")) is_sum = true;
    else return NULL;

    skip_whitespace(&src);
    skip_match(&src, "{");
    skip_whitespace(&src);

    char name_buf[32];
    snprintf(name_buf, sizeof(name_buf), "T%u", id);
    ILTypeDef* def = is_sum ? il_type_def_sum_create(id, name_buf, NULL, true) : il_type_def_struct_create(id, name_buf, NULL, true);
    while (*src && *src != '}') {
        char field_name[128] = {0};
        int i = 0;
        while (*src && (isalnum(*src) || *src == '_')) {
            field_name[i++] = *src++;
        }
        skip_match(&src, ":");
        const ILType* ty = il_read_type(src, &src);
        il_type_def_add_field(def, field_name[0] ? field_name : NULL, ty);
        skip_match(&src, ",");
        skip_whitespace(&src);
    }
    match(&src, "}");
    if (end) *end = src;
    return def;
}

ILModule* il_read_module(const char* src, const char** end) {
    if (src == NULL) return NULL;
    ILModule* mod = il_mod_create();
    if (!mod) return NULL;
    current_mod = mod;

    while (*src) {
        skip_whitespace(&src);
        if (*src == '\0') break;
        const char* prev_src = src;

        if (strncmp(src, "type", 4) == 0) {
            ILTypeDef* def = il_read_type_def(src, &src);
            if (def) il_mod_add_type_def(mod, def);
            else if (src == prev_src) src++;
        } else if (strncmp(src, "global", 6) == 0 || strncmp(src, "const", 5) == 0) {
            ILGlobal* g = il_read_global(src, &src);
            if (g) il_mod_add_global(mod, g);
            else if (src == prev_src) src++;
        } else if (strncmp(src, "f", 1) == 0) {
            ILFunction* func = il_read_func(src, &src);
            if (func) il_mod_add_func(mod, func);
            else if (src == prev_src) src++;
        } else {
            src++;
        }
        skip_whitespace(&src);
    }

    il_mod_fixup_types(mod);
    current_mod = NULL;
    if (end) *end = src;
    return mod;
}
