#ifndef SURFACE_AST_H
#define SURFACE_AST_H

#include <stdint.h>
#include <stdbool.h>
#include "il_type.h"
#include "arena.h"

typedef enum {
    EXPR_INT = 0,
    EXPR_FLOAT = 1,
    EXPR_BOOL = 2,
    EXPR_VAR = 3,
    EXPR_BINARY = 4,
    EXPR_CALL = 5,
    EXPR_BLOCK = 6,
    EXPR_IF = 7,
    EXPR_WHILE = 8,
    EXPR_STRUCT = 9,
    EXPR_MEMBER = 10,
    EXPR_MATCH = 11,
    EXPR_STRING = 12,
    EXPR_UNARY = 13,
    EXPR_BOX = 14,
    EXPR_CAST = 15,
    EXPR_TRY = 16,
    EXPR_ARRAY = 17,
    EXPR_INDEX = 18,
    EXPR_CLOSURE = 19,
    EXPR_TUPLE = 20,
    EXPR_SIZEOF = 21,
    EXPR_ALIGNOF = 22,
    EXPR_RETURN = 23,
} ExprKind;

typedef struct Expression Expression;
typedef struct Statement Statement;
typedef struct IfExpr IfExpr;

typedef struct BlockExpr {
    Statement** statements;
    uint32_t stmt_count;
    Expression* result;
} BlockExpr;

typedef struct {
    char* op;
    Expression* left;
    Expression* right;
} BinaryExpr;

typedef struct {
    char* name;
    Expression* callee;
    const ILType** type_args;
    uint32_t type_arg_count;
    Expression* receiver;
    Expression** args;
    uint32_t arg_count;
} CallExpr;

typedef struct {
    char* name;
    const ILType** type_args;
    uint32_t type_arg_count;
    char** field_names;
    Expression** field_values;
    uint32_t field_count;
} StructExpr;

typedef struct {
    Expression* object;
    char* field_name;
    const ILType** type_args;
    uint32_t type_arg_count;
} MemberExpr;

typedef enum {
    PATTERN_VARIANT = 0,
    PATTERN_INT = 1,
    PATTERN_BOOL = 2,
    PATTERN_CHAR = 3,
    PATTERN_RANGE = 4,
    PATTERN_WILD = 5
} PatternKind;

typedef struct Pattern Pattern;
struct Pattern {
    PatternKind kind;
    union {
        struct {
            char* name;
            char** bind_names; // Optional: Bar(a, b) -> ["a", "b"]
            uint32_t bind_count;
        } variant;
        struct {
            uint64_t start;
            uint64_t end;
            bool is_inclusive;
        } range;
        uint64_t int_val;
        bool bool_val;
    } as;
    Pattern* next; // For OR patterns: p1 | p2 | p3
};

typedef struct {
    Pattern* pattern;
    Expression* body;
} MatchArm;

typedef struct {
    Expression* target;
    MatchArm** arms;
    uint32_t arm_count;
} MatchExpr;

typedef struct {
    char* op;
    Expression* expr;
    bool is_mut;
} UnaryExpr;

typedef struct {
    Expression* left;
    Expression* index;
} IndexExpr;

typedef struct {
    char* name;
    const ILType* type;
    uint64_t tag;
    bool has_tag;
    bool is_mutable;
    bool is_pub;
} Param;

typedef struct {
    Param* params;
    uint32_t param_count;
    const ILType* return_type;
    BlockExpr* body;
    char** captures;
    uint32_t capture_count;
} ClosureExpr;

typedef struct {
    Expression* condition;
    BlockExpr* body;
} WhileExpr;

struct Expression {
    ExprKind kind;
    union {
        uint64_t int_val;
        double float_val;
        bool bool_val;
        struct {
            char* name;
            const ILType** type_args;
            uint32_t type_arg_count;
        } var;
        BinaryExpr binary;
        UnaryExpr unary;
        CallExpr call;
        BlockExpr* block;
        IfExpr* if_expr;
        WhileExpr while_expr;
        StructExpr struct_expr;
        MemberExpr member;
        MatchExpr match_expr;
        Expression* ret_expr;
        struct {
            char* val;
            size_t len;
        } string_val;
        struct {
            Expression** elements;
            uint32_t count;
            Expression* fill_count; // if non-NULL, count is determined by this expression and value is elements[0]
        } array_expr;
        struct {
            Expression** elements;
            uint32_t count;
        } tuple_expr;
        IndexExpr index_expr;
        struct {
            Expression* inner;
            Expression* allocator; // NULL means default heap
        } box_expr;
        struct {
            Expression* expr;
            const ILType* target_type;
        } cast_expr;
        Expression* try_expr;
        const ILType* type_expr;
        ClosureExpr closure;
    } as;
    const ILType* type;
    const char* file_path;
    const char* source;
    uint32_t line;
    uint32_t col;
    uint32_t offset;
    uint32_t length;
};

typedef enum {
    ANNOT_NONE,
    ANNOT_LIKELY,
    ANNOT_UNLIKELY,
} Annotation;

struct IfExpr {
    Annotation annotation;
    Expression* condition;
    BlockExpr* then_block;
    BlockExpr* else_block;
};

typedef enum {
    STMT_RESERVED = 0,
    STMT_RETURN = 1,
    STMT_EXPR = 2,
    STMT_LET = 3,
    STMT_FOR = 4,
    STMT_BREAK = 5,
    STMT_CONTINUE = 6,
    STMT_DEFER = 7,
} StmtKind;

struct Statement {
    StmtKind kind;
    union {
        Expression* expr;
        Expression* ret;
        struct {
            char* name;
            Expression* init;
            const ILType* type;
            bool is_mutable;
        } let;
        struct {
            char* var_name;
            Expression* start;
            Expression* end;
            BlockExpr* body;
        } for_loop;
        BlockExpr* defer_block;
    } as;
    const char* file_path;
    const char* source;
    uint32_t line;
    uint32_t col;
    uint32_t offset;
    uint32_t length;
};

typedef struct {
    char* name;
    char** type_params;
    char** type_bounds; // NEW: optional trait bounds for each type parameter
    uint32_t type_param_count;
    Param* params;
    uint32_t param_count;
    const ILType* return_type;
    BlockExpr* body;
    bool is_pub;
    bool is_extern;
    bool is_variadic;
    bool is_must_use;
    uint32_t line;
    uint32_t col;
    uint32_t offset;
    uint32_t length;
    void* il_function; // ILFunction*
    const char* file_path;
} FunctionDecl;

typedef struct {
    char* name;
    char** type_params;
    char** type_bounds;
    uint32_t type_param_count;
    Param* fields;
    uint32_t field_count;
    bool is_pub;
    uint32_t line, col, offset, length;
    const char* file_path;
} StructDecl;

typedef struct {
    char* name;
    char** type_params;
    char** type_bounds;
    uint32_t type_param_count;
    Param* variants;
    uint32_t variant_count;
    bool is_pub;
    uint32_t line, col, offset, length;
    const char* file_path;
} EnumDecl;

typedef enum {
    TYPE_DEF_STRUCT = 0,
    TYPE_DEF_ENUM = 1
} TypeDefKind;

typedef struct {
    TypeDefKind kind;
    bool is_pub;
    union {
        StructDecl* struct_decl;
        EnumDecl* enum_decl;
    } as;
    const char* file_path;
} TypeDef;

typedef struct {
    char* path;
    char* alias;
    char* resolved_path;
    uint32_t line, col, offset, length;
    const char* file_path;
} ImportDecl;

typedef struct {
    char* name;
    const ILType* type;
    Expression* init;
    bool is_const;
    bool is_pub;
    uint32_t line, col, offset, length;
    const char* file_path;
} GlobalDecl;

typedef struct {
    char* name;
    const ILType* target;
    bool is_pub;
    const char* file_path;
} TypeAliasDecl;

typedef struct {
    char* name;
    char** type_params;
    char** type_bounds;
    uint32_t type_param_count;
    FunctionDecl** methods;
    uint32_t method_count;
    bool is_pub;
    uint32_t line, col, offset, length;
    const char* file_path;
} TraitDecl;

typedef struct {
    char* trait_name; // Optional: impl Trait for Type
    const ILType* trait_type; // The actual trait type (may have type args)
    char* target_name;
    const ILType* target_type;
    
    char** type_params;
    uint32_t type_param_count;

    FunctionDecl** methods;
    uint32_t method_count;
    GlobalDecl** globals;
    uint32_t global_count;
    TypeAliasDecl** type_aliases;
    uint32_t type_alias_count;
    void** il_methods; // ILFunction**
    uint32_t line, col, offset, length;
    const char* file_path;
} ImplDecl;

typedef struct {
    const char* file_path;
    const char* source;
    Arena arena;
    ImportDecl** imports;
    uint32_t import_count;
    FunctionDecl** functions;
    uint32_t function_count;
    TypeDef** type_defs;
    uint32_t type_def_count;
    GlobalDecl** globals;
    uint32_t global_count;
    TypeAliasDecl** type_aliases;
    uint32_t type_alias_count;
    TraitDecl** traits;
    uint32_t trait_count;
    ImplDecl** impls;
    uint32_t impl_count;
} SurfaceModule;

void surface_mod_free(SurfaceModule* mod);
void surface_mod_merge(SurfaceModule* dest, SurfaceModule* src);

#endif
