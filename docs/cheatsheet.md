<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# jsonpath cheatsheet

Every export of `@deckyard/jsonpath`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/jsonpath/" as jsonpath;
```

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `ERROR_KIND` | `"jsonpath"` | the `kind` of every error the deck throws |
| `MAX_NESTING` | `64` | how deep parentheses, filters and calls may nest |
| `MAX_NODES` | `1000000` | the default `Path.maxNodes`, the work one run of a query may do |
| `MAX_INDEX` | `9007199254740991` | the largest index or slice bound, 2^53 - 1 |

## Types

### `Path`

A parsed query, from `compile`.

| Field | Meaning |
|---|---|
| `source as string` | the query as written |
| `nodes as list of Node` | the parsed form |
| `root as int` | the query node's index |
| `maxNodes as int` | the most nodes of work one `find` may do, subqueries included; lower it for untrusted queries |

### `Match`

| Field | Meaning |
|---|---|
| `value as json.Value` | the selected value |
| `pointer as string` | its JSON Pointer |
| `path as string` | its normalized path |

### `Node`

One node of the parsed form; read it through the deck.

| Field | Meaning |
|---|---|
| `kind as int` | what the node is |
| `text as string` | a name, a function name or an operator |
| `num as int` | an index, a flag or a type |
| `start as int` | a slice's start; a literal pattern's state; the root's `$`-subquery flag |
| `stop as int` | a slice's end |
| `step as int` | a slice's step; an expression's static work |
| `hasStart as bool` | the slice gives a start |
| `hasStop as bool` | the slice gives an end |
| `lit as json.Value` | a literal's value |
| `kids as list of int` | the child nodes |

## Functions

| Function | Returns | Does |
|---|---|---|
| `jsonpath.query(doc, path)` | `list of json.Value` | the values a query selects |
| `jsonpath.paths(doc, path)` | `list of string` | their JSON Pointers |
| `jsonpath.normalizedPaths(doc, path)` | `list of string` | their normalized paths |
| `jsonpath.compile(path)` | `Path` | parse a query once |
| `jsonpath.find(doc, path)` | `list of Match` | run a compiled query: value, pointer and normalized path of each node |
| `jsonpath.isValid(path)` | `bool` | whether a string is a valid query |
