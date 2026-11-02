#ifndef SURFACE_LOWER_H
#define SURFACE_LOWER_H

#include "surface_ast.h"
#include "il_cfg.h"
#include "diagnostics.h"

ILModule* surface_lower_module(const SurfaceModule* smod, DiagnosticReport* report, bool release_mode);

#endif
