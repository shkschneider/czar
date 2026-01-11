/*
 * CZar - C semantic authority layer
 * Features registration (src/features.h)
 *
 * Registers all CZar transpiler features.
 */

#pragma once

#include "registry.h"

/* Register all built-in features with the registry */
void register_all_features(FeatureRegistry *registry);
