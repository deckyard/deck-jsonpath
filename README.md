# @deckyard/jsonpath

[![test](https://github.com/deckyard/deck-jsonpath/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-jsonpath/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-jsonpath/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-jsonpath)](https://github.com/deckyard/deck-jsonpath/releases/latest)

[RFC 9535](https://www.rfc-editor.org/rfc/rfc9535) JSONPath queries for
[Jennifer](https://jennifer-lang.dev/), over `json.Value`. The whole RFC:
name, wildcard, index, slice and filter selectors, descendant segments,
comparisons and logic, and the functions `length`, `count`, `match`,
`search` and `value`, with I-Regexp patterns. Every case of the official
JSONPath Compliance Test Suite passes. Results come as values, as JSON
Pointers for the `json` writers, or as normalized paths.

**[Documentation](https://deckyard.github.io/deck-jsonpath/)**

## Install

```sh
jvc add @deckyard/jsonpath
```

Or unpack `src/` from a release archive (`deckyard-jsonpath-<version>.tar.gz`)
into `vendor/deckyard/jsonpath/`.

## Usage

```jennifer
use fs;
use io;
use json;
import "@deckyard/jsonpath/" as jsonpath;

def doc as json.Value init json.decode(fs.readString("store.json"));

for (def title in jsonpath.query($doc, "$..book[?@.price < 10].title")) {
    io.printf("%s\n", json.asString($title));
}

def p as jsonpath.Path init jsonpath.compile("$..book[?search(@.author, 'Tolkien')]");
for (def m in jsonpath.find($doc, $p)) {
    io.printf("%s at %s\n", json.encode($m.value), $m.pointer);
}
```

## Requirements

Jennifer 0.25.0 or newer, default or `jennifer-tiny` binary. No capability.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/jsonpath_test.j    # unit tests and the compliance suite
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

`testdata/cts` is the vendored compliance suite (BSD-2, see its README).

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.
