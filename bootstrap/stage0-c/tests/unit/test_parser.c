#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_ast.h"
#include "surface_parser.h"
#include "diagnostics.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_parse_minimal_func(void) {
    const char* src = "fn main() -> i32 { return 0; }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    ASSERT(mod->function_count == 1, "Module should have one function");
    ASSERT(strcmp(mod->functions[0]->name, "main") == 0, "Function name should be main");
    ASSERT(mod->functions[0]->return_type != NULL, "Function should have return type");
    ASSERT(mod->functions[0]->return_type->kind == IL_TY_I32, "Return type should be i32");
    
    surface_mod_free(mod);
    return true;
}

static bool test_parse_func_params(void) {
    const char* src = "fn add(a: i32, b: i32) -> i32 { return a + b; }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    ASSERT(mod->function_count == 1, "Module should have one function");
    ASSERT(mod->functions[0]->param_count == 2, "Function should have 2 parameters");
    ASSERT(strcmp(mod->functions[0]->params[0].name, "a") == 0, "First param should be a");
    ASSERT(mod->functions[0]->params[0].type->kind == IL_TY_I32, "First param should be i32");
    
    ASSERT(mod->functions[0]->body != NULL, "Function should have a body");
    ASSERT(mod->functions[0]->body->stmt_count == 1, "Body should have 1 statement");
    ASSERT(mod->functions[0]->body->statements[0]->kind == STMT_RETURN, "Statement should be return");
    
    const Expression* ret_expr = mod->functions[0]->body->statements[0]->as.ret;
    ASSERT(ret_expr->kind == EXPR_BINARY, "Return expr should be BINARY");
    ASSERT(strcmp(ret_expr->as.binary.op, "+") == 0, "Op should be +");
    ASSERT(ret_expr->as.binary.left->kind == EXPR_VAR, "Left should be VAR");
    ASSERT(strcmp(ret_expr->as.binary.left->as.var.name, "a") == 0, "Left should be a");
    ASSERT(ret_expr->as.binary.right->kind == EXPR_VAR, "Right should be VAR");
    ASSERT(strcmp(ret_expr->as.binary.right->as.var.name, "b") == 0, "Right should be b");

    surface_mod_free(mod);
    return true;
}

static bool test_parse_let_mut(void) {
    const char* src = "fn main() { let x = 1; let mut y = 2; }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    ASSERT(mod->functions[0]->body->stmt_count == 2, "Body should have 2 statements");
    
    const Statement* s1 = mod->functions[0]->body->statements[0];
    ASSERT(s1->kind == STMT_LET, "First stmt should be LET");
    ASSERT(strcmp(s1->as.let.name, "x") == 0, "Name should be x");
    ASSERT(s1->as.let.is_mutable == false, "x should be immutable");
    
    const Statement* s2 = mod->functions[0]->body->statements[1];
    ASSERT(s2->kind == STMT_LET, "Second stmt should be LET");
    ASSERT(strcmp(s2->as.let.name, "y") == 0, "Name should be y");
    ASSERT(s2->as.let.is_mutable == true, "y should be mutable");

    surface_mod_free(mod);
    return true;
}

static bool test_parse_while(void) {
    const char* src = "fn main() { while true { } }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    const BlockExpr* body = mod->functions[0]->body;
    ASSERT(body->stmt_count == 0, "Body should have 0 statements");
    ASSERT(body->result != NULL, "Body should have a result expression");
    const Expression* e = body->result;
    ASSERT(e->kind == EXPR_WHILE, "Expression should be WHILE");
    const Expression* cond = e->as.while_expr.condition;
    ASSERT(cond->kind == EXPR_BOOL, "Condition should be bool");
    ASSERT(cond->as.bool_val == true, "Condition should be true");
    
    ASSERT(e->as.while_expr.body != NULL, "While loop should have a body");
    
    surface_mod_free(mod);
    return true;
}

static bool test_parse_for(void) {
    const char* src = "fn main() { for i in 0..10 { print(i); } }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    const BlockExpr* body = mod->functions[0]->body;
    ASSERT(body->stmt_count == 1, "Body should have 1 statement");
    ASSERT(body->statements[0]->kind == STMT_FOR, "Statement should be FOR");
    
    const char* var_name = body->statements[0]->as.for_loop.var_name;
    ASSERT(strcmp(var_name, "i") == 0, "Loop var should be i");
    ASSERT(body->statements[0]->as.for_loop.start->kind == EXPR_INT, "Start should be INT");
    ASSERT(body->statements[0]->as.for_loop.end->kind == EXPR_INT, "End should be INT");

    surface_mod_free(mod);
    return true;
}

static bool test_parse_defer(void) {
    const char* src = "fn main() { defer file.close(); }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    const BlockExpr* body = mod->functions[0]->body;
    ASSERT(body->stmt_count == 1, "Body should have 1 statement");
    ASSERT(body->statements[0]->kind == STMT_DEFER, "Statement should be DEFER");
    ASSERT(body->statements[0]->as.defer_block != NULL, "Defer should have a block");

    surface_mod_free(mod);
    return true;
}

static bool test_parse_annotations(void) {
    const char* src = "fn main() { if @unlikely(error) { return 1; } }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    const BlockExpr* body = mod->functions[0]->body;
    ASSERT(body->stmt_count == 0, "Body should have 0 statements");
    ASSERT(body->result != NULL, "Body should have a result expression");
    const Expression* e = body->result;
    ASSERT(e->kind == EXPR_IF, "Expression should be IF");
    
    const IfExpr* if_e = e->as.if_expr;
    ASSERT(if_e->annotation == ANNOT_UNLIKELY, "Annotation should be UNLIKELY");

    surface_mod_free(mod);
    return true;
}

static bool test_parse_globals(void) {
    const char* src = "const MAX_VAL: i32 = 100; static counter = 0; pub static global_var: u64 = 42;";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    ASSERT(mod->global_count == 3, "Module should have 3 globals");
    
    const GlobalDecl* g1 = mod->globals[0];
    ASSERT(strcmp(g1->name, "MAX_VAL") == 0, "First global name should be MAX_VAL");
    ASSERT(g1->is_const == true, "MAX_VAL should be const");
    ASSERT(g1->type != NULL && g1->type->kind == IL_TY_I32, "MAX_VAL should be i32");
    ASSERT(g1->init != NULL && g1->init->kind == EXPR_INT && g1->init->as.int_val == 100, "MAX_VAL should be 100");
    
    const GlobalDecl* g2 = mod->globals[1];
    ASSERT(strcmp(g2->name, "counter") == 0, "Second global name should be counter");
    ASSERT(g2->is_const == false, "counter should be static");
    ASSERT(g2->type == NULL, "counter type should be inferred");
    ASSERT(g2->init != NULL && g2->init->kind == EXPR_INT && g2->init->as.int_val == 0, "counter should be 0");
    
    const GlobalDecl* g3 = mod->globals[2];
    ASSERT(strcmp(g3->name, "global_var") == 0, "Third global name should be global_var");
    ASSERT(g3->is_pub == true, "global_var should be public");
    ASSERT(g3->type != NULL && g3->type->kind == IL_TY_U64, "global_var should be u64");

    surface_mod_free(mod);
    return true;
}

static bool test_parse_never(void) {
    const char* src = "fn panics() -> never { loop {} }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    ASSERT(mod->functions[0]->return_type->kind == IL_TY_NEVER, "Return type should be never");
    
    surface_mod_free(mod);
    return true;
}

static bool test_parse_loop(void) {
    const char* src = "fn main() { loop { break; } }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", report);
    
    if (!mod) {
        diag_report_print(report, stderr);
    }
    ASSERT(mod != NULL, "Parser should produce a module");
    ABORT_IF_NULL(mod);
    ASSERT(mod->function_count > 0, "Module should have main function");
    const BlockExpr* body = mod->functions[0]->body;
    ASSERT(body->stmt_count == 0, "Body should have 0 statements (loop is the result)");
    ASSERT(body->result != NULL, "Body should have a result");
    const Expression* e = body->result;
    ASSERT(e->kind == EXPR_WHILE, "loop should be lowered to EXPR_WHILE in parser");
    ASSERT(e->as.while_expr.condition->kind == EXPR_BOOL, "loop condition should be bool");
    ASSERT(e->as.while_expr.condition->as.bool_val == true, "loop condition should be true");
    
    surface_mod_free(mod);
    diag_report_destroy(report);
    return true;
}

static bool test_parse_struct(void) {
    const char* src = "struct Point { x: i32, y: i32 }";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    ASSERT(mod->type_def_count == 1, "Module should have one type def");
    ASSERT(mod->type_defs[0]->kind == TYPE_DEF_STRUCT, "Should be a struct");
    
    const StructDecl* s = mod->type_defs[0]->as.struct_decl;
    ASSERT(strcmp(s->name, "Point") == 0, "Struct name should be Point");
    ASSERT(s->field_count == 2, "Struct should have 2 fields");
    ASSERT(strcmp(s->fields[0].name, "x") == 0, "First field should be x");
    ASSERT(s->fields[0].type->kind == IL_TY_I32, "First field type should be i32");
    
    surface_mod_free(mod);
    return true;
}

static bool test_trailing_commas(void) {
    const char* src = 
        "enum Option { Some(i32), None, } "
        "struct Point { x: i32, y: i32, } "
        "fn f(a: i32, b: i32, ) {} "
        "fn main() { "
        "  let a = [1, 2, 3,]; "
        "  let t = (1, 2,); "
        "  let p = Point { x: 1, y: 2, }; "
        "  f(1, 2,); "
        "}";
        
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should succeed for trailing commas");
    
    surface_mod_free(smod);
    return true;
}

static bool check_parse_robustness(const char* source) {
    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    
    if (smod) {
        surface_mod_free(smod);
    }
    diag_report_destroy(diag);
    return true; 
}

static bool test_malformed_fn(void) {
    ASSERT(check_parse_robustness("fn"), "fn");
    ASSERT(check_parse_robustness("fn main"), "fn main");
    ASSERT(check_parse_robustness("fn main("), "fn main(");
    ASSERT(check_parse_robustness("fn main() -> "), "fn main() -> ");
    ASSERT(check_parse_robustness("fn main() {"), "fn main() {");
    ASSERT(check_parse_robustness("fn main() { /* unclosed comment "), "fn main() { unclosed comment");
    return true;
}

static bool test_malformed_struct(void) {
    ASSERT(check_parse_robustness("struct"), "struct");
    ASSERT(check_parse_robustness("struct Point"), "struct Point");
    ASSERT(check_parse_robustness("struct Point { x }"), "struct Point { x }");
    ASSERT(check_parse_robustness("struct Point { x: }"), "struct Point { x: }");
    ASSERT(check_parse_robustness("struct Point { x: i32, "), "struct Point { x: i32, ");
    return true;
}

static bool test_malformed_enum(void) {
    ASSERT(check_parse_robustness("enum"), "enum");
    ASSERT(check_parse_robustness("enum Color"), "enum Color");
    ASSERT(check_parse_robustness("enum Color { Red("), "enum Color { Red(");
    ASSERT(check_parse_robustness("enum Color { Red, Green: }"), "enum Color { Red, Green: }");
    return true;
}

static bool test_malformed_let(void) {
    ASSERT(check_parse_robustness("fn main() { let ; }"), "let ;");
    ASSERT(check_parse_robustness("fn main() { let x = ; }"), "let x = ;");
    ASSERT(check_parse_robustness("fn main() { let x: = 1; }"), "let x: = 1;");
    ASSERT(check_parse_robustness("fn main() { let mut ; }"), "let mut ;");
    return true;
}

static bool test_malformed_if_while_for(void) {
    ASSERT(check_parse_robustness("fn main() { if { } }"), "if { }");
    ASSERT(check_parse_robustness("fn main() { while { } }"), "while { }");
    ASSERT(check_parse_robustness("fn main() { if true }"), "if true");
    ASSERT(check_parse_robustness("fn main() { for { } }"), "for { }");
    ASSERT(check_parse_robustness("fn main() { for i in { } }"), "for i in { }");
    return true;
}

static bool test_malformed_match(void) {
    ASSERT(check_parse_robustness("fn main() { match { } }"), "match { }");
    ASSERT(check_parse_robustness("fn main() { match x { => 1 } }"), "match => 1");
    ASSERT(check_parse_robustness("fn main() { match x { Variant => } }"), "match Variant =>");
    return true;
}

static bool test_malformed_type_alias_import(void) {
    ASSERT(check_parse_robustness("type"), "type");
    ASSERT(check_parse_robustness("type Alias"), "type Alias");
    ASSERT(check_parse_robustness("type Alias ="), "type Alias =");
    ASSERT(check_parse_robustness("import"), "import");
    ASSERT(check_parse_robustness("import \""), "import unclosed string");
    return true;
}

static bool test_malformed_expressions(void) {
    ASSERT(check_parse_robustness("fn main() { @ }"), "@ alone");
    ASSERT(check_parse_robustness("fn main() { x. }"), "x.");
    ASSERT(check_parse_robustness("fn main() { x:: }"), "x::");
    ASSERT(check_parse_robustness("fn main() { (1+ ) }"), "(1+ )");
    ASSERT(check_parse_robustness("fn main() { f(1, ) }"), "f(1, )");
    ASSERT(check_parse_robustness("fn main() { |x, | { } }"), "|x, | { }");
    ASSERT(check_parse_robustness("fn main() { Point { x: } }"), "Point { x: }");
    return true;
}

static bool test_malformed_generics_traits(void) {
    ASSERT(check_parse_robustness("fn main<T>() { }"), "fn main<T>() { }");
    ASSERT(check_parse_robustness("fn main<T: >() { }"), "fn main<T: >() { }");
    ASSERT(check_parse_robustness("trait { }"), "trait missing name");
    ASSERT(check_parse_robustness("impl for T { }"), "impl missing trait");
    ASSERT(check_parse_robustness("impl Trait for { }"), "impl missing type");
    return true;
}

static bool test_parser_incomplete_constructs(void) {
    const char* sources[] = {
        "fn main() { let ; }",               
        "fn main() { let mut ; }",           
        "fn main() { for in 0..10 {} }",     
        "fn main() { for i in ..10 {} }",    
        "fn foo<: Trait>() {}",              
        "fn foo<T: >() {}",                  
        "import ;",                          
        "import foo as ;",                   
        "fn foo( : i32) {}",                 
    };

    for (size_t i = 0; i < sizeof(sources)/sizeof(sources[0]); i++) {
        check_parse_robustness(sources[i]);
    }
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_parse_minimal_func);
    RUN_TEST(test_parse_func_params);
    RUN_TEST(test_parse_let_mut);
    RUN_TEST(test_parse_while);
    RUN_TEST(test_parse_for);
    RUN_TEST(test_parse_defer);
    RUN_TEST(test_parse_never);
    RUN_TEST(test_parse_loop);
    RUN_TEST(test_parse_struct);
    RUN_TEST(test_parse_annotations);
    RUN_TEST(test_parse_globals);
    RUN_TEST(test_trailing_commas);
    RUN_TEST(test_malformed_fn);
    RUN_TEST(test_malformed_struct);
    RUN_TEST(test_malformed_enum);
    RUN_TEST(test_malformed_let);
    RUN_TEST(test_malformed_if_while_for);
    RUN_TEST(test_malformed_match);
    RUN_TEST(test_malformed_type_alias_import);
    RUN_TEST(test_malformed_expressions);
    RUN_TEST(test_malformed_generics_traits);
    RUN_TEST(test_parser_incomplete_constructs);

    printf("[%2d/%2d] Surface Syntax Parser\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
