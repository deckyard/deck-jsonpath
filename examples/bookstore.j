#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * bookstore example: the queries of RFC 9535's own example, on its document.
 *
 * Run with: jennifer run examples/bookstore.j
 */

use io;
use json;

import "../src/jsonpath.j" as jsonpath;

def doc as json.Value init json.decode('{"store": {"book": [' +
    '{"category": "reference", "author": "Nigel Rees", ' +
    '"title": "Sayings of the Century", "price": 8.95},' +
    '{"category": "fiction", "author": "Evelyn Waugh", ' +
    '"title": "Sword of Honour", "price": 12.99},' +
    '{"category": "fiction", "author": "Herman Melville", "title": "Moby Dick", ' +
    '"isbn": "0-553-21311-3", "price": 8.99},' +
    '{"category": "fiction", "author": "J. R. R. Tolkien", "title": "The Lord of the Rings", ' +
    '"isbn": "0-395-19395-8", "price": 22.99}],' + '"bicycle": {"color": "red", "price": 399}}}');

for (def q in [
    "$.store.book[*].author",
    "$..price",
    "$..book[-1].title",
    "$..book[?@.isbn].title",
    "$..book[?@.price < 10].title",
    "$..book[?search(@.author, 'Waugh|Melville')].title"
]) {
    io.printf("%s\n", $q);
    for (def v in jsonpath.query($doc, $q)) {
        io.printf("    %s\n", json.encode($v));
    }
}

# A compiled query runs many times; find gives the pointer and the normalized path too.
def cheap as jsonpath.Path init jsonpath.compile("$..book[?@.price < 10]");
for (def m in jsonpath.find($doc, $cheap)) {
    io.printf("%s  %s\n", $m.pointer, $m.path);
}

# The pointers feed json.remove: delete every book over 10, last first.
def ptrs as list of string init jsonpath.paths($doc, "$..book[?@.price > 10]");
def i as int init len($ptrs) - 1;
while ($i >= 0) {
    $doc = json.remove($doc, $ptrs[$i]);
    $i = $i - 1;
}
io.printf("%d books left\n", len(jsonpath.query($doc, "$.store.book[*]")));

if (not jsonpath.isValid("$.store.book[?@.price <]")) {
    try {
        jsonpath.compile("$.store.book[?@.price <]");
    } catch (e) {
        io.printf("%s\n", $e.message);
    }
}
