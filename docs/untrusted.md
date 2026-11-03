<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Untrusted queries

A query from a user of your program cannot read files, run code or reach
the network: it only selects parts of the document you pass. What it can do
is cost time and memory. The deck bounds both.

- **Nesting.** Parentheses, filters and function calls nest at most
  `MAX_NESTING` (64) levels deep; a deeper query fails in `compile` at once.
- **Results.** One segment may produce at most `Path.maxNodes` nodes,
  `MAX_NODES` (1,000,000) by default. Chained descendant segments multiply
  (`$..*..*..*` on a deep document); past the limit the query fails with
  `Error{kind: "jsonpath"}` instead of exhausting memory. Lower it for
  untrusted queries:

  ```jennifer
  import "@deckyard/jsonpath/" as jsonpath;

  def p as jsonpath.Path init jsonpath.compile($userQuery);
  $p.maxNodes = 50000;
  def found as list of jsonpath.Match init jsonpath.find($doc, $p);
  ```

  A tree-walking interpreter needs some microseconds per node, so a million
  nodes is seconds of work; 50,000 is a fraction of one.
- **Repeated subqueries.** A `$` query inside a filter does not depend on the
  node being tested, so it runs once per `find` rather than once per node.
  `$..*[?count($..*) > 1]` costs two walks of the document, not one per node.
- **Regular expressions** run on RE2, which matches in time linear in the
  input: no pattern backtracks catastrophically. A pattern too large to
  compile makes `match` and `search` false.

Documents are bounded by `json.decode`, which refuses nesting past 1000
levels; descendant segments walk with a stack, never recursion.
