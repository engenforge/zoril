#ifndef IL_INSTR_H
#define IL_INSTR_H

#include "il_type.h"

typedef enum {
    IL_OP_INVALID = 0,
    // Arithmetic
    IL_OP_ADD = 1,
    IL_OP_SUB = 2,
    IL_OP_MUL = 3,
    IL_OP_DIV = 4,
    IL_OP_REM = 5,
    IL_OP_AND = 6,
    IL_OP_OR = 7,
    IL_OP_XOR = 8,
    IL_OP_SHL = 9,
    IL_OP_SHR = 10,

    // Comparison
    IL_OP_CMP_LT = 11,
    IL_OP_CMP_LE = 12,
    IL_OP_CMP_GT = 13,
    IL_OP_CMP_GE = 14,
    IL_OP_CMP_EQ = 15,
    IL_OP_CMP_NE = 16,

    // Explicit overflow variants
    IL_OP_WRAPPING_ADD = 17,
    IL_OP_WRAPPING_SUB = 18,
    IL_OP_WRAPPING_MUL = 19,
    IL_OP_SATURATING_ADD = 20,
    IL_OP_CHECKED_ADD = 21,
    IL_OP_CHECKED_SUB = 22,
    IL_OP_CHECKED_MUL = 23,

    // Memory
    IL_OP_ALLOC = 24,
    IL_OP_LOAD = 25,
    IL_OP_STORE = 26,
    IL_OP_DROP = 27,

    // Safety
    IL_OP_BOUNDS_CHECK = 28,
    IL_OP_SLICE_LOAD = 29,
    IL_OP_SLICE_STORE = 30,
    IL_OP_SLICE_LEN = 31,
    IL_OP_SLICE_DATA = 32,
    IL_OP_SLICE_CONSTRUCT = 33,
    IL_OP_ARRAY_CONSTRUCT = 34,
    IL_OP_ARRAY_LOAD = 35,
    IL_OP_ARRAY_STORE = 36,
    IL_OP_MOVE = 37,
    IL_OP_BITCAST = 38,
    IL_OP_REGION_CAST = 39,

    // Option / Sum Types
    IL_OP_IS_SOME = 40,
    IL_OP_UNWRAP = 41,

    // Control Flow
    IL_OP_CALL = 42,
    IL_OP_RETURN = 43,
    IL_OP_BRANCH = 44,
    IL_OP_JUMP = 45,
    IL_OP_GLOBAL_ADDR = 46,
    IL_OP_FIELD_ADDR = 47,
    IL_OP_ELEM_ADDR = 48,
    IL_OP_VARIANT_MATCH = 49,
    IL_OP_SUM_CONSTRUCT = 50,
    IL_OP_SYSCALL = 51,
    IL_OP_CONST = 52,
    IL_OP_PHI = 53,
    IL_OP_STRING_CONST = 54,

    IL_OP_CALL_PTR = 55,
    IL_OP_FUNC_ADDR = 56,

    // File-descriptor I/O (capability-checked)
    IL_OP_FD_OPEN = 57,   // open(path, flags, mode)  -> fd<cap>
    IL_OP_FD_CLOSE = 58,  // close(fd)                -> unit
    IL_OP_FD_READ = 59,   // read(fd, count)           -> i64 (bytes read)
    IL_OP_FD_WRITE = 60,  // write(fd, count)          -> i64 (bytes written)

    // Async I/O context (io_uring on Linux, kqueue on BSD/macOS)
    IL_OP_ASYNC_SETUP = 61,  // async_setup(entries) -> async_context
    IL_OP_ASYNC_ENTER = 62,  // async_enter(ctx, to_submit, min_complete) -> i64
    IL_OP_ASYNC_CLOSE = 63   // async_close(ctx)           -> unit
} ILOpcode;

// Represents an SSA value (variable or constant)
typedef struct {
    uint32_t id;
    const ILType* type;
} ILValue;

typedef struct {
    uint32_t block_id;
    uint32_t value_id;
} ILPhiIncoming;

// The Instruction Node
typedef struct {
    const ILType* result_type; // The type this instruction produces
    uint32_t result_id;        // SSA ID of the result (0 if none)
    uint16_t line;
    uint8_t opcode;
    uint8_t col;

    // Instruction operands
    union {
        struct {
            uint32_t left;
            uint32_t right;
        } binary;

        struct {
            uint32_t region_id;
            uint32_t allocator_id;
        } alloc;

        struct {
            uint32_t ptr;
        } load;

        struct {
            uint32_t ptr;
            uint32_t value;
        } store;

        struct {
            uint32_t value;
        } drop;

        struct {
            uint32_t index;
            uint32_t length;
        } bounds_check;

        struct {
            uint32_t slice_ptr;
            uint32_t index;
        } slice_load;

        struct {
            uint32_t slice_ptr;
        } slice_op;

        struct {
            uint32_t ptr;
            uint32_t len;
        } slice_construct;

        struct {
            uint32_t slice_ptr;
            uint32_t index;
            uint32_t value;
        } slice_store;

        struct {
            uint32_t* element_ids;
            uint32_t count;
        } array_construct;

        struct {
            uint32_t array_ptr;
            uint32_t index;
        } array_load;

        struct {
            uint32_t array_ptr;
            uint32_t index;
            uint32_t value;
        } array_store;

        struct {
            uint32_t source;
        } move;

        struct {
            uint32_t source;
            uint32_t target_region_id;
        } region_cast;

        struct {
            uint32_t source;
        } bitcast;

        struct {
            uint32_t* arg_ids;
            uint32_t func_id;
            uint32_t num_args;
        } call;

        struct {
            uint32_t* arg_ids;
            uint32_t func_ptr_id;
            uint32_t num_args;
        } call_ptr;

        struct {
            uint32_t value;
        } ret;

        struct {
            uint32_t condition;
            uint32_t then_block_id;
            uint32_t else_block_id;
        } branch;

        struct {
            uint32_t target_block_id;
        } jump;

        struct {
            uint32_t global_id;
        } global_addr;

        struct {
            uint32_t func_id;
        } func_addr;

        struct {
            uint32_t struct_ptr;
            uint32_t field_index;
        } field_addr;

        struct {
            uint32_t base;
            uint32_t index;
        } elem_addr;

        struct {
            uint32_t sum_ptr;
            uint32_t variant_index;
            uint32_t target_block_id;
            uint32_t next_block_id;
        } variant_match;

        struct {
            uint32_t type_def_id;
            uint32_t variant_index;
            uint32_t payload_id;
        } sum_construct;

        struct {
            uint32_t* arg_ids;
            uint32_t syscall_num;
            uint32_t num_args;
        } syscall_op;

        struct {
            union {
                uint64_t val;
                double fval;
            } u;
        } const_val;

        struct {
            ILPhiIncoming* incoming;
            uint32_t num_incoming;
        } phi;

        struct {
            char* val;
            uint32_t len;
        } string_literal;

        struct {
            uint32_t path;
            uint32_t flags;
            uint32_t mode;
        } fd_open;

        struct {
            uint32_t fd;
        } fd_close;

        struct {
            uint32_t fd;
            uint32_t buf;
            uint32_t count;
        } fd_io;

        struct {
            uint32_t entries;
        } async_setup;

        struct {
            uint32_t ctx;
            uint32_t to_submit;
            uint32_t min_complete;
        } async_enter;

        struct {
            uint32_t ctx;
        } async_close;
    } operands;
} ILInstruction;

// Instruction constructors
const ILType* il_build_unit_type(void);
ILInstruction* il_build_add(ILValue left, ILValue right);
ILInstruction* il_build_sub(ILValue left, ILValue right);
ILInstruction* il_build_mul(ILValue left, ILValue right);
ILInstruction* il_build_div(ILValue left, ILValue right);
ILInstruction* il_build_rem(ILValue left, ILValue right);
ILInstruction* il_build_and(ILValue left, ILValue right);
ILInstruction* il_build_or(ILValue left, ILValue right);
ILInstruction* il_build_xor(ILValue left, ILValue right);
ILInstruction* il_build_shl(ILValue left, ILValue right);
ILInstruction* il_build_shr(ILValue left, ILValue right);

ILInstruction* il_build_cmp_lt(ILValue left, ILValue right, const ILType* bool_type);
ILInstruction* il_build_cmp_le(ILValue left, ILValue right, const ILType* bool_type);
ILInstruction* il_build_cmp_gt(ILValue left, ILValue right, const ILType* bool_type);
ILInstruction* il_build_cmp_ge(ILValue left, ILValue right, const ILType* bool_type);
ILInstruction* il_build_cmp_eq(ILValue left, ILValue right, const ILType* bool_type);
ILInstruction* il_build_cmp_ne(ILValue left, ILValue right, const ILType* bool_type);

ILInstruction* il_build_wrapping_add(ILValue left, ILValue right);
ILInstruction* il_build_wrapping_sub(ILValue left, ILValue right);
ILInstruction* il_build_wrapping_mul(ILValue left, ILValue right);
ILInstruction* il_build_saturating_add(ILValue left, ILValue right);
ILInstruction* il_build_checked_add(ILValue left, ILValue right, const ILType* option_type);
ILInstruction* il_build_checked_sub(ILValue left, ILValue right, const ILType* option_type);
ILInstruction* il_build_checked_mul(ILValue left, ILValue right, const ILType* option_type);

// Memory constructors
ILInstruction* il_build_alloc(uint32_t region_id, const ILType* alloc_type, const ILType* ptr_type, ILValue allocator);
ILInstruction* il_build_load(ILValue ptr);
ILInstruction* il_build_store(ILValue ptr, ILValue value);
ILInstruction* il_build_drop(ILValue value);

// Safety constructors
ILInstruction* il_build_bounds_check(ILValue index, ILValue length);
ILInstruction* il_build_move(ILValue source);
ILInstruction* il_build_bitcast(ILValue source, const ILType* target_type);
ILInstruction* il_build_region_cast(ILValue source, uint32_t target_region_id);

// Slice constructors
ILInstruction* il_build_slice_load(ILValue slice_ptr, ILValue index);
ILInstruction* il_build_slice_store(ILValue slice_ptr, ILValue index, ILValue value);
ILInstruction* il_build_slice_len(ILValue slice_ptr, const ILType* u64_type);
ILInstruction* il_build_slice_data(ILValue slice_ptr, const ILType* ptr_type);
ILInstruction* il_build_slice_construct(ILValue ptr, ILValue len, const ILType* slice_ty);
ILInstruction* il_build_array_construct(const ILValue* elements, uint32_t count, const ILType* array_type);
ILInstruction* il_build_array_load(ILValue array_ptr, ILValue index, const ILType* result_type);
ILInstruction* il_build_array_store(ILValue array_ptr, ILValue index, ILValue value);
ILInstruction* il_build_is_some(ILValue option, const ILType* bool_type);
// Option / Sum Type constructors
ILInstruction* il_build_is_some(ILValue option, const ILType* bool_type);
ILInstruction* il_build_unwrap(ILValue option, const ILType* result_type);

// Control flow constructors
ILInstruction* il_build_call(uint32_t func_id, const ILValue* args, uint32_t num_args, const ILType* result_type);
ILInstruction* il_build_call_ptr(ILValue func_ptr, const ILValue* args, uint32_t num_args, const ILType* result_type);
ILInstruction* il_build_return(ILValue value);
ILInstruction* il_build_branch(ILValue condition, uint32_t then_block_id, uint32_t else_block_id);
ILInstruction* il_build_jump(uint32_t target_block_id);
ILInstruction* il_build_global_addr(uint32_t global_id, const ILType* ptr_type);
ILInstruction* il_build_func_addr(uint32_t func_id, const ILType* fn_type);
ILInstruction* il_build_field_addr(ILValue struct_ptr, uint32_t field_index, const ILType* ptr_type);
ILInstruction* il_build_elem_addr(ILValue base, ILValue index, const ILType* ptr_type);
/* Absent target of a value-form variant_match (see il_read.c); never a real block id. */
#define IL_NO_BLOCK UINT32_MAX
ILInstruction* il_build_variant_match(ILValue sum_ptr, uint32_t variant_index, uint32_t target_block_id, uint32_t next_block_id);
ILInstruction* il_build_sum_construct(uint32_t type_def_id, uint32_t variant_index, ILValue payload, const ILType* result_type);
ILInstruction* il_build_syscall(uint32_t syscall_num, const ILValue* args, uint32_t num_args, const ILType* result_type);
ILInstruction* il_build_const(uint64_t val, const ILType* type);
ILInstruction* il_build_fconst(double val, const ILType* type);
ILInstruction* il_build_phi(const ILPhiIncoming* incoming, uint32_t num_incoming, const ILType* result_type);

// File-descriptor I/O constructors
ILInstruction* il_build_fd_open(ILValue path, ILValue flags, ILValue mode,
                                const ILType* fd_type);
ILInstruction* il_build_fd_close(ILValue fd);
ILInstruction* il_build_fd_read(ILValue fd, ILValue buf, ILValue count,
                                const ILType* i64_type);
ILInstruction* il_build_fd_write(ILValue fd, ILValue buf, ILValue count,
                                 const ILType* i64_type);

// Async I/O context constructors
ILInstruction* il_build_async_setup(ILValue entries, const ILType* ctx_type);
ILInstruction* il_build_async_enter(ILValue ctx, ILValue to_submit,
                                      ILValue min_complete,
                                      const ILType* i64_type);
ILInstruction* il_build_async_close(ILValue ctx);

ILValue il_value_copy_type(ILValue val);
void il_instr_free(ILInstruction* instr);

#endif
