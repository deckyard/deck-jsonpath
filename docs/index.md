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

Snippets assume the `use` and `import` lines of this example:

```jennifer
use fs;
use io;
use json;
import "@deckyard/jsonpath/" as jsonpath;

def doc as json.Value init json.decode(fs.readString("store.json"));
for (def title in jsonpath.query($doc, "$.store.book[?@.price < 10].title")) {
    io.printf("%s\n", json.asString($title));
}
```

Three functions take a query string:

| Function | Gives |
|---|---|
| `jsonpath.query` | the selected values |
| `jsonpath.paths` | their JSON Pointers, for `json.get`, `json.set` and `json.remove` |
| `jsonpath.normalizedPaths` | their RFC 9535 normalized paths, `$['store']['book'][0]` |

`jsonpath.compile` parses a query once; `jsonpath.find` runs it on a
document and returns all three for each node as a `Match`. Results come in
the order RFC 9535 defines; an object's members in document order.

## Changing what a query found

The pointers feed the `json` writers. Removing an array element shifts the
ones after it, and `paths` returns RFC 9535 order, which is not document
order for `$[3,1]` or `$[::-1]` and may repeat a node (`$[1,1]`). So remove
each pointer once, highest array index first and descendants before their
ancestors: pad every index token to 16 digits and sort the keys in reverse.

```jennifer
use lists;
use maps;
use regex;
use strings;

def byKey as map of string to string init {};
for (def ptr in jsonpath.paths($doc, "$..book[?@.price > 10]")) {
    def parts as list of string init [];
    for (def token in strings.split($ptr, "/")) {
        if (regex.matches("^(0|[1-9][0-9]*)$", $token)) {
            $parts[] = strings.repeat("0", 16 - len($token)) + $token;
        } else {
            $parts[] = $token;
        }
    }
    $byKey[strings.join($parts, "/")] = $ptr;
}
for (def key in lists.reverse(lists.sort(maps.keys($byKey)))) {
    $doc = json.remove($doc, $byKey[$key]);
}
```

For a query whose results are in document order without repeats (names,
wildcards, filters, `..`, forward slices), removing from the last pointer to
the first is enough.

## Errors

Every failure is `Error{kind: "jsonpath"}`. A query that is not valid RFC
9535 fails in `compile`, `query`, `paths` and `normalizedPaths` with the
reason and the position:

```
jsonpath: only a singular query can be compared at position 10 of "$[?@.* == 1]"
```

That includes the type rules of RFC 9535 section 2.4.3: an unknown function,
a wrong argument count, a query that can select several nodes where one
value is needed, a function returning a value used as a test. `isValid` asks
without throwing. So does a literal `match` / `search` pattern that RE2
cannot compile ([Query syntax](syntax.md#functions)).

A valid query fails on a document only when it needs more work than its
node limit ([Untrusted queries](untrusted.md)) or when a pattern taken from
the document cannot be compiled by RE2. A selector that does not apply (a
name on an array, an index past the end) selects nothing.

Error messages quote at most 64 code points of the query, around the error
position, so a long query from a user does not produce a long message.

## Requirements

Jennifer 0.25.0 or newer, default or `jennifer-tiny` binary.
