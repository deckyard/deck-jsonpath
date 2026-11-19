<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

RFC 9535 JSONPath queries over `json.Value`: name, wildcard, index, slice
and filter selectors, descendant segments, the comparison and logical
operators, and the functions `length`, `count`, `match`, `search` and
`value`, with I-Regexp (RFC 9485) for the regex functions. `query` returns
the matched values, `paths` the matches as JSON Pointers (so they feed
`json.set` and `json.remove` directly), `normalizedPaths` the RFC's
normalized paths, and `compile` with `find` parses once and returns all
three per match. The deck is pure computation: no capability, and it runs on
`jennifer-tiny`.

Not in scope:

- **Other query languages** (JMESPath, jq) and pre-RFC JSONPath dialects:
  the RFC and its compliance suite are the contract.
- **Updates through a query.** The deck finds; the pointers it returns are
  how a caller changes the document with core's writers.
- **`toml` and `yaml` trees.** Version 1 takes `json.Value` only. The other
  libraries share the accessor surface, so a later version can take the
  library as a parameter.

## Decisions

- **A deck, not core.** JSON Pointer is the one addressing scheme of the
  document-tree libraries; a second syntax in core would blur that.
  JSONPath is a query language on top of it, returning many nodes where a
  pointer names one.
- **Hand-written parser, flat tree.** A parsed query is a `Path` whose
  `nodes` refer to each other by index. Well-typedness (RFC 9535 section
  2.4.3) is checked at parse time, so a query that compiles never fails for
  a type reason while running. Inner subqueries get lower indexes than outer
  ones, which is what lets `$` subqueries be cached in index order.
- **Evaluation threads one work buffer.** The evaluator passes one mutable
  working state in place through every step: each segment reads its input
  from a slice of a shared node buffer and appends its output after it, and
  a filter subquery appends past that and resets afterwards. This keeps
  evaluation free of per-node copies under Jennifer's value semantics.
- **Two filter evaluators.** Simple filter expressions (literals, singular
  queries, comparisons, logic, `length`, `count` and `value` of a `$` query,
  a literal-pattern `match`) run in pure functions that return a value;
  everything else runs in the in-place evaluator. The split exists because
  each in-place call costs more than a plain return, and without it filters
  ran about a third slower.
- **`$` subqueries run once per `find`.** A `$` query inside a filter does
  not depend on the node being tested, so it is evaluated once per run and
  cached.
- **I-Regexp translated onto RE2.** A pattern is translated in one linear
  pass rather than passed through: `.` becomes "any character but CR and
  LF", constructs outside RFC 9485 are refused (the function is then false,
  as the RFC requires), and character classes follow the RFC's grammar
  exactly. A literal pattern is translated and compiled once at parse time;
  one from the document once per run.
- **RE2's own limits are errors, not false.** A valid I-Regexp that RE2
  cannot compile (a repeat over 1000, a program over 50,000 instructions, a
  pattern over 32 KiB) throws, at `compile` for a literal and while running
  for one from the document. A silent false hid the problem.
- **Numbers.** Two integers compare as integers; anything involving a float
  compares as floats.
- **Readable messages.** Parse errors name the position and quote at most 64
  code points of the query, with the escapes `json.encode` writes for `<`,
  `>` and `&` undone.

## Errors

Every failure is an `Error` of kind `"jsonpath"` (`ERROR_KIND`) with a
message starting `jsonpath: `, except the work budget: a run past
`Path.maxNodes` is kind `"limit"`. Nesting past `MAX_NESTING` stays
`"jsonpath"`, since it is a compile error with a position. `compile`
rewraps any other error raised while parsing as `cannot parse "<query>":
...`. A hand-edited `Path` whose node indexes are inconsistent can still
fail with kind `"runtime"`; `find` checks only that its root is a query.

## Security and limits

A query from a user cannot read files, run code or reach the network; it
can cost time and memory, and the deck bounds both ([Untrusted
queries](untrusted.md) has the figures).

- `MAX_NESTING` (64) bounds parentheses, filters and function calls, checked
  while parsing, before the interpreter's call-depth limit could be reached.
- One work budget per run, `Path.maxNodes` (`MAX_NODES`, 1,000,000, by
  default): every node produced, every child a filter tests, every container
  a descendant segment visits, every name or index selector per input node,
  and every step of a singular query in a filter, subqueries included. It is
  checked before the work is done. A per-segment limit was not enough:
  nested descendant filters grow with the cube of the document depth. Only
  `compile` plus a lowered `maxNodes` plus `find` applies a smaller budget;
  `query`, `paths` and `normalizedPaths` use the default.
- No query-length cap: parsing is linear, and nesting bounds the recursion.
- Descendant segments walk with an explicit stack, never recursion.
- RE2 matches in linear time, so no pattern backtracks catastrophically.
- Documents are bounded by `json.decode`'s own nesting cap.

## Testing and validation

- 35 tests; most coverage is the JSONPath Compliance Test Suite, vendored
  unchanged under `testdata/cts/` (BSD-2; the commit is recorded beside
  it). One test runs every case and checks the values, the normalized paths,
  and that each pointer leads back to its value.
- `jvc` runs the overlays from a copy of `src/` without `testdata/`, where
  the suite is skipped; a separate test fails if a run from the checkout
  cannot find it.
- Performance was compared with 0.1.0 on an 11 MB document of 100,000
  items when the work budget went in: `paths` and `normalizedPaths` got
  faster, simple selections and filters a few percent slower.

## Known limitations and open questions

- `json.Value` only.
- One node of work costs 10 to 25 microseconds, so the default budget allows
  10 to 25 seconds of work; a whole-document `$..*` on a large file can pass
  it. Lower `maxNodes` for untrusted queries.
- A native descendant walk in core (every pointer under a node in one call)
  would speed up `..`; it is a possible core follow-up only if profiling
  shows the need.

## Dependencies on the interpreter

- Floor `>=0.26.0` for `jennifer` and `jennifer-tiny`.
- `json`'s pointer accessors (`typeOf` reporting `"missing"`, structural
  `==` on values, `len` counting code points) and `regex` on RE2.
- The work budget as kind `"limit"` follows `jennifer`'s M28.54 and the
  deck audit M28.57.
