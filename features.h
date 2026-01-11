/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Registers all CZar transpiler features.
 */

#pragma once

#include "registry.h"

/* Register all built-in features with the registry */
void register_all_features(FeatureRegistry *registry);
