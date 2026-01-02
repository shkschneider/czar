/*
 * CZar - C semantic authority layer
 * Runtime header (cz.h)
 *
 * Provides source location macros.
 * Runtime assertion macros (cz_assert, cz_todo, cz_fixme, cz_unreachable)
 * are injected by the transpiler during compilation.
 */

#ifndef CZ_H
#define CZ_H

/* ========================================================================
 * Source Location Macros
 * ======================================================================== */

/* Source location macros */
#define FILE __FILE__
#define LINE __LINE__
#define FUNC __func__

#endif /* CZ_H */
