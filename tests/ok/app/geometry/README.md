# Geometry Module

This directory demonstrates the module system with multiple files in the same module.

## Files

- `point.cz` - Point struct and related functions
- `rectangle.cz` - Rectangle struct and related functions

## Module Validation Rules

Both files declare `module app.geometry`:
1. ✅ Files in the same directory share the same module name
2. ✅ Module name `app.geometry` ends with directory name `geometry`

These rules enforce Go-like module organization:
- All files in a directory must have the same module name
- The module name must end with the directory name
