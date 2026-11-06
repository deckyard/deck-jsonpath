<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Query syntax

A query starts with `$`, the document, and applies segments in turn. Each
segment takes the nodes so far and selects new ones.

| Query | Selects |
|---|---|
| `$.store.bicycle` | the member `bicycle` of `store` |
| `$['store']['the shop']` | members by name, any name |
| `$.store.*` | every member of `store` |
| `$.book[0]`, `$.book[-1]` | the first, the last element |
| `$.book[0, 2]` | elements 0 and 2, in that order |
| `$.book[1:3]`, `$.book[::-1]` | a slice: `[start:end:step]`, end excluded |
| `$..price` | `price` anywhere below the root |
| `$..*` | every node below the root |
| `$.book[?@.isbn]` | the books that have an `isbn` |
| `$.book[?@.price < 10]` | the books cheaper than 10 |

Names in brackets take single or double quotes and JSON-style escapes
(`\n`, `\u00e9`, `\'`). A name after a dot is letters, digits and `_`, plus
anything beyond ASCII, and does not start with a digit.

## Filters

`[?expr]` keeps the elements of an array, or the member values of an
object, for which `expr` is true. Inside it, `@` is the node being tested
and `$` still the document.

- **Existence**: `@.isbn` is true when the member exists, even when its value
  is `false` or `null`.
- **Comparisons**: `==` `!=` `<` `<=` `>` `>=` between literals (numbers,
  strings, `true`, `false`, `null`), queries that select at most one node,
  and functions returning a value. `1 == 1.0`; strings order by code point;
  only numbers and strings are ordered; arrays and objects compare by
  content for `==`. A missing node equals only another missing node.
- **Logic**: `&&`, `||`, `!` and parentheses.

```jennifer
import "@deckyard/jsonpath/" as jsonpath;

jsonpath.query($doc, "$..book[?@.category == 'fiction' && !@.isbn]");
jsonpath.query($doc, "$..book[?@.price <= $.limits.max]");
```

## Functions

| Function | Takes | Gives |
|---|---|---|
| `length(v)` | a value | code points of a string, elements of an array, members of an object |
| `count(q)` | a query | how many nodes it selects |
| `value(q)` | a query | the one node it selects; nothing for none or several |
| `match(v, re)` | a string, a pattern | true when the whole string matches |
| `search(v, re)` | a string, a pattern | true when some part matches |

```jennifer
jsonpath.query($doc, "$..book[?length(@.title) > 20]");
jsonpath.query($doc, "$..book[?count(@.authors[*]) > 1]");
jsonpath.query($doc, "$..book[?match(@.isbn, '0-[0-9-]+')]");
```

Patterns are I-Regexp ([RFC 9485](https://www.rfc-editor.org/rfc/rfc9485)),
a small subset shared by the common regex engines: characters, `.`, classes
`[a-z]`, `[^...]`, Unicode categories `\p{L}` / `\P{Nd}`, groups, `|`, and
the quantifiers `*` `+` `?` `{n,m}`. There are no `\d`, `\w`, `\s`, lazy
quantifiers, backreferences or lookaround; a pattern using them, or any
other invalid pattern (`[a-b-c]`, `[z-a]`, `x{2,1}`), makes `match` and
`search` false rather than failing. In a class, `-` is a literal only first
or last. `.` matches any character but a line break. Inside a query a
backslash is itself escaped: `'\\.'` is a pattern matching a dot.

A valid pattern that RE2 cannot compile throws `Error{kind: "jsonpath"}`
with RE2's reason: a repeat count over 1000 (`a{1001}`), or a program over
RE2's size limits (32 KiB of pattern, 50,000 instructions). A literal
pattern fails in `compile`; one taken from the document fails while the
query runs.
