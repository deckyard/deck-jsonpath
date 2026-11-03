# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonpath - the shared types, errors and path escaping. Spliced into
# jsonpath.j via include.

/** The `kind` of every error the deck throws. */
export def const ERROR_KIND as string init "jsonpath";

/** How deep parentheses, filters and function calls may nest in a query. */
export def const MAX_NESTING as int init 64;

/**
 * The most nodes one segment may produce. Chained descendant segments
 * (`$..*..*..*`) multiply; past this a query fails instead of exhausting
 * memory.
 */
export def const MAX_NODES as int init 1000000;

/** The largest index or slice bound RFC 9535 allows, 2^53 - 1. */
export def const MAX_INDEX as int init 9007199254740991;

# Node kinds of a parsed path.
def const KQUERY as int init 1;
def const KSEGMENT as int init 2;
def const KNAME as int init 3;
def const KWILD as int init 4;
def const KINDEX as int init 5;
def const KSLICE as int init 6;
def const KFILTER as int init 7;
def const KOR as int init 8;
def const KAND as int init 9;
def const KNOT as int init 10;
def const KTEST as int init 11;
def const KCMP as int init 12;
def const KLITERAL as int init 13;
def const KFUNC as int init 14;
# A `$` query inside a filter, run once: `num` is its node count, `lit` the first.
def const KCACHED as int init 15;

# Braces, which no string literal can hold without starting an interpolation.
def const LBRACE as string init "\{";
def const RBRACE as string init "\}";

# The types of RFC 9535 section 2.4.1.
def const TVALUE as int init 1;
def const TLOGICAL as int init 2;
def const TNODES as int init 3;

/**
 * One node of a parsed path. Nodes refer to each other by their index in
 * `Path.nodes`.
 *
 * @field kind {int} what the node is
 * @field text {string} a member name, a function name or an operator
 * @field num {int} an index; a query's singular flag (1); a segment's
 *   descendant flag (1); a function's result type; a cached query's count
 * @field start {int} a slice's start; for `match` / `search` with a literal
 *   pattern, 1 when `lit` holds it translated, 2 when it is invalid
 * @field stop {int} a slice's end
 * @field step {int} a slice's step
 * @field hasStart {bool} the slice gives a start
 * @field hasStop {bool} the slice gives an end
 * @field lit {json.Value} a literal's value; a translated pattern; a cached
 *   query's first node
 * @field kids {list of int} the child nodes
 */
export def struct Node {
    kind as int,
    text as string,
    num as int,
    start as int,
    stop as int,
    step as int,
    hasStart as bool,
    hasStop as bool,
    lit as json.Value,
    kids as list of int
};

/**
 * A parsed JSONPath query, from `compile`. Reuse it to run one query
 * against many documents.
 *
 * @field source {string} the query as written
 * @field nodes {list of Node} the parsed form; read it through the deck
 * @field root {int} the index of the query node
 * @field maxNodes {int} the most nodes one segment may produce; `MAX_NODES`
 *   unless lowered, e.g. for queries from untrusted users
 */
export def struct Path {
    source as string,
    nodes as list of Node,
    root as int,
    maxNodes as int
};

/**
 * One node a query selected.
 *
 * @field value {json.Value} the value
 * @field pointer {string} its JSON Pointer, for `json.get` / `json.set` / `json.remove`
 * @field path {string} its RFC 9535 normalized path, e.g. `$['store']['book'][0]`
 */
export def struct Match {
    value as json.Value,
    pointer as string,
    path as string
};

/**
 * Raise a deck error.
 *
 * @param message {string} what went wrong
 * @throws {Error} always, with `kind` `"jsonpath"`
 */
func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: "jsonpath: " + $message};
}

/**
 * The type of a node, `missing` when the pointer does not resolve. Jennifer
 * 0.25.0's `json.typeOf` throws for a missing member instead.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer; "" for the root
 * @return {string} `null`, `bool`, `int`, `float`, `string`, `list`, `map` or `missing`
 */
func kindAt(v as json.Value, ptr as string) {
    if ($ptr == "") {
        return json.typeOf($v);
    }
    if (not json.has($v, $ptr)) {
        return "missing";
    }
    return json.typeOf($v, $ptr);
}

/**
 * Escape a member name for a JSON Pointer.
 *
 * @param name {string} the name
 * @return {string} the name with `~` and `/` escaped
 */
func pointerToken(name as string) {
    return strings.replace(strings.replace($name, "~", "~0"), "/", "~1");
}

/**
 * A member name as a normalized path writes it (RFC 9535 section 2.7):
 * `'` and `\` escaped, control characters as `\b \f \n \r \t` or `\u00xx`.
 *
 * @param name {string} the name
 * @return {string} the name between the quotes of `['...']`
 */
func normalName(name as string) {
    def out as list of string init [];
    for (def ch in strings.chars($name)) {
        def cp as int init convert.toCodepoint($ch);
        if ($ch == "'") {
            $out[] = "\\'";
        } elseif ($ch == "\\") {
            $out[] = "\\\\";
        } elseif ($cp >= 32) {
            $out[] = $ch;
        } elseif ($cp == 8) {
            $out[] = "\\b";
        } elseif ($cp == 12) {
            $out[] = "\\f";
        } elseif ($cp == 10) {
            $out[] = "\\n";
        } elseif ($cp == 13) {
            $out[] = "\\r";
        } elseif ($cp == 9) {
            $out[] = "\\t";
        } else {
            def hex as string init convert.toString($cp, 16);
            $out[] = "\\u" + strings.repeat("0", 4 - len($hex)) + $hex;
        }
    }
    return strings.join($out, "");
}

/**
 * A JSON string value.
 *
 * @param s {string} the text
 * @return {json.Value} the string node
 */
func jsonString(s as string) {
    return json.decode(json.encode($s));
}

/**
 * A JSON number value.
 *
 * @param n {int} the number
 * @return {json.Value} the number node
 */
func jsonInt(n as int) {
    return json.decode(convert.toString($n));
}
