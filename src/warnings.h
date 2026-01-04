/*
 * CZar - C semantic authority layer
 * Centralized Warning Definitions (warnings.h)
 *
 * All warning messages used by the CZar transpiler.
 * Each warning has an UPPER_CASE_ID and a descriptive message.
 */

#pragma once

/* Warning reporting function */
void cz_warning(const char *filename, const char *source, int line, const char *message);

/* Cast Warnings */
#define WARN_CAST_WITHOUT_FALLBACK \
    "cast<%s>(value) without fallback. " \
    "Consider the safer cast<%s>(value, fallback)."

/* Enum/Switch Warnings */
#define WARN_UNSCOPED_ENUM_CONSTANT \
    "Unscoped enum constant '%s' in switch. " \
    "Prefer scoped syntax: 'case %s.%s'"
#define WARN_SWITCH_MISSING_DEFAULT \
    "Switch statement should have a default case. " \
    "Consider adding 'default: UNREACHABLE(\"\");' or appropriate handling."

/* Tracking Limit Warnings */
#define WARN_MAX_METHOD_TRACKING_LIMIT \
    "Maximum method tracking limit (%d) reached"
#define WARN_MAX_STRUCT_TYPE_TRACKING_LIMIT \
    "Maximum struct type tracking limit (%d) reached"
#define WARN_MAX_ENUM_TRACKING_LIMIT \
    "Maximum number of tracked enums (%d) reached. " \
    "Exhaustiveness checking may be incomplete for enum '%s'."

/* Named Arguments Warnings */
#define WARN_AMBIGUOUS_ARGUMENTS \
    "Ambiguous function call with consecutive same-type parameters without labels. " \
    "Consider using named arguments for clarity: %s"
