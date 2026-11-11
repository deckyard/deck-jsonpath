# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * White-box tests: jennifer test src/jsonpath_test.j
 *
 * Mirrors the include splice of jsonpath.j over the topic overlays. Most of
 * the coverage is the JSONPath Compliance Test Suite in testdata/cts, which
 * runs only from a checkout.
 */
use fs;
use testing;

include "topics/core_test.j";
include "topics/parse_test.j";
include "topics/functions_test.j";
include "topics/evaluate_test.j";
