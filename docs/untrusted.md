<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Untrusted queries

A query from a user of your program cannot read files, run code or reach
the network: it only selects parts of the document you pass. What it can do
is cost time and memory. The deck bounds both.

- **Nesting.** Parentheses, filters and function calls nest at most
  `MAX_NESTING` (64) levels deep; a deeper query fails in `compile` at once.
- **Work.** One run of a query may do at most `Path.maxNodes` nodes of
  work, `MAX_NODES` (1,000,000) by default. Every node a selector produces
  counts, every child a filter tests, every container a descendant segment
  visits, every name or index selector per input node and every step of a
  singular query in a filter, inside filter subqueries too. The count is
  checked before the work is done: `$[*,*,*,...]` fails before it builds the
  nodes, and nested descendant filters (`$..[?@..[?@..*]]`, whose cost grows
  with the cube of the document depth) fail once their total passes the
  limit. Past it the query fails with `Error{kind: "limit"}`. Lower it
  for untrusted queries:

  ```jennifer
  import "@deckyard/jsonpath/" as jsonpath;

  def p as jsonpath.Path init jsonpath.compile($userQuery);
  $p.maxNodes = 50000;
  def found as list of jsonpath.Match init jsonpath.find($doc, $p);
  ```

  One node of work costs 10 to 25 µs (Go build of Jennifer 0.25.0-dev, one
  core): `$.store.items[*].name` over 100,000 items is about 200,000 nodes
  and 2.4 s; `$..[?@..[?@..*]]` on a 200-deep array stops at 50,000 nodes
  after 0.9 s. The default limit allows 10 to 25 s, 50,000 about 1 s. A
  whole-document `$..*` on a large file can pass the default: 100,000
  records of 5 members (11 MB) do.
- **Repeated subqueries.** A `$` query inside a filter does not depend on the
  node being tested, so it runs once per `find` rather than once per node.
  `$..*[?count($..*) > 1]` costs two walks of the document, not one per node.
  A pattern taken from the document is translated once per run.
- **Regular expressions** run on RE2, which matches in time linear in the
  input: no pattern backtracks catastrophically. Translating an I-Regexp is
  linear in the pattern: 4,000 `\p{L}` (20 KB) from the document take
  0.15 s. RE2 refuses patterns over 32 KiB or 50,000 instructions and
  repeats over 1000; such a valid I-Regexp throws `Error{kind: "jsonpath"}`,
  at `compile` for a literal and while running for one from the document.
- **Queries.** Parsing is linear in the query length: 24 KB of
  `$[0,1,2,...]` parses in 0.3 s. Error messages quote at most 64 code
  points of the query.

Documents are bounded by `json.decode`, which refuses nesting past 1000
levels (64 on `jennifer-tiny`); descendant segments walk with a stack,
never recursion.
