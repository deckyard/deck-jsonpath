# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * RFC 9535 JSONPath queries over `json.Value`.
 *
 * `query` returns the values a query selects, `paths` their JSON Pointers
 * (ready for `json.get`, `json.set` and `json.remove`), `normalizedPaths`
 * their RFC 9535 normalized paths. `compile` parses a query once; `find`
 * runs it and returns all three. The whole RFC is covered: name, wildcard,
 * index, slice and filter selectors, descendant segments, comparisons, the
 * logical operators, and the functions `length`, `count`, `match`, `search`
 * and `value`. Regular expressions are I-Regexp (RFC 9485), translated onto
 * RE2. Every failure is `Error{kind: "jsonpath"}`.
 *
 * The implementation is split into topic files spliced in with `include`;
 * this file is the module boundary.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | the types, errors and path escaping |
 * | `parse` | the grammar and the well-typedness checks |
 * | `functions` | the five functions and I-Regexp |
 * | `evaluate` | segments, selectors, filters, comparisons, the public functions |
 *
 * @module jsonpath
 * @see https://www.rfc-editor.org/rfc/rfc9535
 * @example
 *   def doc as json.Value init json.decode(fs.readString("store.json"));
 *   for (def title in jsonpath.query($doc, "$.store.book[?@.price < 10].title")) {
 *       io.printf("%s\n", json.asString($title));
 *   }
 */
use convert;
use json;
use lists;
use maps;
use regex;
use strings;

include "topics/core.j";
include "topics/parse.j";
include "topics/functions.j";
include "topics/evaluate.j";
