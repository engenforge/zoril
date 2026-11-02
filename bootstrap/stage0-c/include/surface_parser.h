#ifndef SURFACE_PARSER_H
#define SURFACE_PARSER_H

#include "surface_ast.h"
#include "diagnostics.h"

SurfaceModule* surface_parse_module(const char* src, const char* file_path, DiagnosticReport* report);

#endif
