<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/jsonpath

[RFC 9535](https://www.rfc-editor.org/rfc/rfc9535) JSONPath queries over
`json.Value`. The whole RFC is covered: name, wildcard, index, slice and
filter selectors, descendant segments, comparisons, `&&` `||` `!`, and the
functions `length`, `count`, `match`, `search` and `value`. Every case of the
official [JSONPath Compliance Test Suite](https://github.com/jsonpath-standard/jsonpath-compliance-test-suite)
passes. Pure computation: no capability, and it runs on `jennifer-tiny`.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/jsonpath/" as jsonpath;

def doc as json.Value init json.decode(fs.readString("store.json"));
for (def title in jsonpath.query($doc, "$.store.book[?@.price < 10].title")) {
    io.printf("%s\n", json.asString($title));
}
```

Three ways to ask, for one query string:

| Function | Gives |
|---|---|
| `jsonpath.query` | the selected values |
| `jsonpath.paths` | their JSON Pointers, for `json.get`, `json.set` and `json.remove` |
| `jsonpath.normalizedPaths` | their RFC 9535 normalized paths, `$['store']['book'][0]` |

`jsonpath.compile` parses a query once; `jsonpath.find` runs it on a
document and returns all three for each node as a `Match`. Results come in
the order RFC 9535 defines; an object's members in document order.

## Changing what a query found

The pointers feed the `json` writers. Removing shifts the later elements of
an array, so remove from the last pointer to the first:

```jennifer
def ptrs as list of string init jsonpath.paths($doc, "$..book[?@.price > 10]");
def i as int init len($ptrs) - 1;
while ($i >= 0) {
    $doc = json.remove($doc, $ptrs[$i]);
    $i = $i - 1;
}
```

## Errors

Every failure is `Error{kind: "jsonpath"}`. A query that is not valid RFC
9535 fails in `compile`, `query`, `paths` and `normalizedPaths` with the
reason and the position:

```
jsonpath: only a singular query can be compared at position 9 of "$[?@.* == 1]"
```

That includes the type rules of RFC 9535 section 2.4.3: an unknown function,
a wrong argument count, a query that can select several nodes where one
value is needed, a function returning a value used as a test. `isValid` asks
without throwing. A query over its node limit fails while it runs; see
[Untrusted queries](untrusted.md).

A valid query never fails on a document: a selector that does not apply
(a name on an array, an index past the end) selects nothing.

## Requirements

Jennifer 0.25.0 or newer, default or `jennifer-tiny` binary.
