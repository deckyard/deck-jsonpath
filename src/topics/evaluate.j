# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonpath - evaluation (RFC 9535 sections 2.3 to 2.5) and the public
# functions. Spliced into jsonpath.j via include.

/**
 * A node during evaluation. `ptr` and `norm` are built only for the query
 * the caller asked for, never for the queries inside a filter.
 *
 * @field value {json.Value} the value
 * @field ptr {string} its JSON Pointer
 * @field norm {string} its normalized path
 */
def struct Loc {
    value as json.Value,
    ptr as string,
    norm as string
};

/**
 * Parse a query once, to run it against many documents with `find`.
 *
 * @param path {string} the JSONPath query, e.g. `$.store.book[?@.price < 10].title`
 * @return {Path} the parsed query
 * @throws {Error} kind `"jsonpath"` when the query is not valid RFC 9535,
 *   naming the position of the first error
 * @example
 *   def cheap as jsonpath.Path init jsonpath.compile("$..book[?@.price < 10]");
 */
export func compile(path as string) {
    try {
        return parse($path);
    } catch (e) {
        if ($e.kind == ERROR_KIND) {
            throw $e;
        }
        fail("cannot parse " + quoted($path) + ": " + $e.message);
    }
}

/**
 * Whether a string is a valid RFC 9535 query.
 *
 * @param path {string} the query
 * @return {bool} true when `compile` accepts it
 */
export func isValid(path as string) {
    try {
        compile($path);
    } catch (e) {
        return false;
    }
    return true;
}

/**
 * Run a compiled query: every node it selects, with its JSON Pointer and its
 * normalized path, in the order RFC 9535 gives them.
 *
 * @param doc {json.Value} the document
 * @param path {Path} the query, from `compile`
 * @return {list of Match} the matches; empty when nothing matches
 */
export func find(doc as json.Value, path as Path) {
    def p as Path init prepare($path, $doc);
    def out as list of Match init [];
    for (def loc in selectQuery($p, $p.root, $doc, $doc, true)) {
        $out[] = Match{value: $loc.value, pointer: $loc.ptr, path: $loc.norm};
    }
    return $out;
}

/**
 * The values a query selects.
 *
 * @param doc {json.Value} the document
 * @param path {string} the query
 * @return {list of json.Value} the values, in order
 * @throws {Error} kind `"jsonpath"` when the query is not valid
 */
export func query(doc as json.Value, path as string) {
    def p as Path init prepare(compile($path), $doc);
    def out as list of json.Value init [];
    for (def loc in selectQuery($p, $p.root, $doc, $doc, false)) {
        $out[] = $loc.value;
    }
    return $out;
}

/**
 * The JSON Pointers of the nodes a query selects, ready for `json.get`,
 * `json.set` and `json.remove`.
 *
 * @param doc {json.Value} the document
 * @param path {string} the query
 * @return {list of string} the pointers, in order; `""` is the root
 * @throws {Error} kind `"jsonpath"` when the query is not valid
 */
export func paths(doc as json.Value, path as string) {
    def out as list of string init [];
    for (def m in find($doc, compile($path))) {
        $out[] = $m.pointer;
    }
    return $out;
}

/**
 * The normalized paths (RFC 9535 section 2.7) of the nodes a query selects.
 *
 * @param doc {json.Value} the document
 * @param path {string} the query
 * @return {list of string} the paths, e.g. `$['store']['book'][0]`
 * @throws {Error} kind `"jsonpath"` when the query is not valid
 */
export func normalizedPaths(doc as json.Value, path as string) {
    def out as list of string init [];
    for (def m in find($doc, compile($path))) {
        $out[] = $m.path;
    }
    return $out;
}

/**
 * Run every `$` query inside a filter once, before the filter tests each
 * node: its result does not depend on `@`. A query such as
 * `$..*[?count($..*) > 0]` would otherwise walk the document once per node.
 * Inner queries have lower indexes than outer ones, so they are cached first.
 *
 * @param path {Path} the parsed query
 * @param doc {json.Value} the document
 * @return {Path} the query with those subqueries replaced by their summary
 */
func prepare(path as Path, doc as json.Value) {
    def i as int init 0;
    while ($i < len($path.nodes)) {
        if ($i != $path.root and $path.nodes[$i].kind == KQUERY and $path.nodes[$i].text == "$") {
            def locs as list of Loc init selectQuery($path, $i, $doc, $doc, false);
            def cached as Node init newNode(KCACHED);
            $cached.num = len($locs);
            if (len($locs) > 0) {
                $cached.lit = $locs[0].value;
            }
            $path.nodes[$i] = $cached;
        }
        $i = $i + 1;
    }
    return $path;
}

/**
 * Run a query node from its identifier: `$` from the root, `@` from the
 * current node.
 *
 * @param path {Path} the parsed query
 * @param q {int} the query node
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node of a filter
 * @param track {bool} build pointers and normalized paths
 * @return {list of Loc} the selected nodes
 */
func selectQuery(path as Path, q as int, root as json.Value, cur as json.Value, track as bool) {
    def start as json.Value init $cur;
    if ($path.nodes[$q].text == "$") {
        $start = $root;
    }
    def locs as list of Loc init [Loc{value: $start, ptr: "", norm: "$"}];
    for (def seg in $path.nodes[$q].kids) {
        $locs = applySegment($path, $seg, $locs, $root, $track);
        if (len($locs) == 0) {
            break;
        }
    }
    return $locs;
}

/**
 * Apply a segment to every input node.
 *
 * @param path {Path} the parsed query
 * @param seg {int} the segment node
 * @param locs {list of Loc} the input nodes
 * @param root {json.Value} the document
 * @param track {bool} build pointers and normalized paths
 * @return {list of Loc} the output nodes
 */
func applySegment(
    path as Path,
    seg as int,
    locs as list of Loc,
    root as json.Value,
    track as bool) {
    def out as list of Loc init [];
    def descendant as bool init $path.nodes[$seg].num == 1;
    for (def loc in $locs) {
        if ($descendant) {
            for (def d in descendants($loc, $track, $path.maxNodes)) {
                $out = applySelectors($path, $seg, $d, $root, $track, $out);
            }
        } else {
            $out = applySelectors($path, $seg, $loc, $root, $track, $out);
        }
        if (len($out) > $path.maxNodes) {
            fail("a segment selected more than " + convert.toString($path.maxNodes) + " nodes");
        }
    }
    return $out;
}

/**
 * Apply a segment's selectors, in order, to one node.
 *
 * @param path {Path} the parsed query
 * @param seg {int} the segment node
 * @param loc {Loc} the node
 * @param root {json.Value} the document
 * @param track {bool} build pointers and normalized paths
 * @param out {list of Loc} the results so far
 * @return {list of Loc} the results with this node's added
 */
func applySelectors(
    path as Path,
    seg as int,
    loc as Loc,
    root as json.Value,
    track as bool,
    out as list of Loc) {
    for (def sel in $path.nodes[$seg].kids) {
        $out = applySelector($path, $sel, $loc, $root, $track, $out);
    }
    return $out;
}

/**
 * Apply one selector to one node.
 *
 * @param path {Path} the parsed query
 * @param sel {int} the selector node
 * @param loc {Loc} the node
 * @param root {json.Value} the document
 * @param track {bool} build pointers and normalized paths
 * @param out {list of Loc} the results so far
 * @return {list of Loc} the results with this selector's added
 */
func applySelector(
    path as Path,
    sel as int,
    loc as Loc,
    root as json.Value,
    track as bool,
    out as list of Loc) {
    def kind as int init $path.nodes[$sel].kind;
    def type as string init json.typeOf($loc.value);
    if ($kind == KNAME) {
        def name as string init $path.nodes[$sel].text;
        if ($type == "map" and json.has($loc.value, "/" + pointerToken($name))) {
            $out[] = member($loc, $name, $track);
        }
    } elseif ($kind == KWILD) {
        $out = children($loc, $track, $out);
    } elseif ($kind == KINDEX and $type == "list") {
        def size as int init json.length($loc.value);
        def i as int init $path.nodes[$sel].num;
        if ($i < 0) {
            $i = $i + $size;
        }
        if ($i >= 0 and $i < $size) {
            $out[] = element($loc, $i, $track);
        }
    } elseif ($kind == KSLICE and $type == "list") {
        for (def i in sliceIndexes($path.nodes[$sel], json.length($loc.value))) {
            $out[] = element($loc, $i, $track);
        }
    } elseif ($kind == KFILTER and ($type == "list" or $type == "map")) {
        $out = applyFilter($path, $path.nodes[$sel].kids[0], $loc, $root, $track, $out);
    }
    return $out;
}

/**
 * Apply a filter to an array's elements or an object's members, building
 * a full result entry only for those that pass.
 *
 * @param path {Path} the parsed query
 * @param test {int} the filter's expression
 * @param loc {Loc} the array or object
 * @param root {json.Value} the document
 * @param track {bool} build pointers and normalized paths
 * @param out {list of Loc} the results so far
 * @return {list of Loc} the results with the passing children added
 */
func applyFilter(
    path as Path,
    test as int,
    loc as Loc,
    root as json.Value,
    track as bool,
    out as list of Loc) {
    if (json.typeOf($loc.value) == "list") {
        def n as int init json.length($loc.value);
        def i as int init 0;
        while ($i < $n) {
            if (evalLogical($path, $test, $root, json.get($loc.value, "/" + convert.toString($i)))) {
                $out[] = element($loc, $i, $track);
            }
            $i = $i + 1;
        }
        return $out;
    }
    for (def key in json.keys($loc.value)) {
        if (evalLogical($path, $test, $root, json.get($loc.value, "/" + pointerToken($key)))) {
            $out[] = member($loc, $key, $track);
        }
    }
    return $out;
}

/**
 * A member of an object node.
 *
 * @param loc {Loc} the object node
 * @param name {string} the member name
 * @param track {bool} build pointers and normalized paths
 * @return {Loc} the member
 */
func member(loc as Loc, name as string, track as bool) {
    def token as string init pointerToken($name);
    def out as Loc init Loc{value: json.get($loc.value, "/" + $token), ptr: "", norm: ""};
    if ($track) {
        $out.ptr = $loc.ptr + "/" + $token;
        $out.norm = $loc.norm + "['" + normalName($name) + "']";
    }
    return $out;
}

/**
 * An element of an array node.
 *
 * @param loc {Loc} the array node
 * @param i {int} the index, within the array
 * @param track {bool} build pointers and normalized paths
 * @return {Loc} the element
 */
func element(loc as Loc, i as int, track as bool) {
    def index as string init convert.toString($i);
    def out as Loc init Loc{value: json.get($loc.value, "/" + $index), ptr: "", norm: ""};
    if ($track) {
        $out.ptr = $loc.ptr + "/" + $index;
        $out.norm = $loc.norm + "[" + $index + "]";
    }
    return $out;
}

/**
 * Add a node's children: an array's elements, an object's member values in
 * document order; nothing for a scalar.
 *
 * @param loc {Loc} the node
 * @param track {bool} build pointers and normalized paths
 * @param out {list of Loc} the results so far
 * @return {list of Loc} the results with the children added
 */
func children(loc as Loc, track as bool, out as list of Loc) {
    def type as string init json.typeOf($loc.value);
    if ($type == "list") {
        def n as int init json.length($loc.value);
        def i as int init 0;
        while ($i < $n) {
            $out[] = element($loc, $i, $track);
            $i = $i + 1;
        }
    } elseif ($type == "map") {
        for (def key in json.keys($loc.value)) {
            $out[] = member($loc, $key, $track);
        }
    }
    return $out;
}

/**
 * A node and all its descendants that are arrays or objects, each before its
 * own descendants, children in order. Scalars are left out: no selector
 * selects anything from them. Walks with a stack, so a deep document does
 * not reach the call depth limit.
 *
 * @param loc {Loc} the node
 * @param track {bool} build pointers and normalized paths
 * @param limit {int} the most nodes to visit
 * @return {list of Loc} the node and its container descendants
 */
func descendants(loc as Loc, track as bool, limit as int) {
    def out as list of Loc init [];
    def stack as list of Loc init [$loc];
    def top as int init 1;
    while ($top > 0) {
        $top = $top - 1;
        def cur as Loc init $stack[$top];
        $out[] = $cur;
        def kids as list of Loc init containerChildren($cur, $track);
        def k as int init len($kids) - 1;
        if (len($out) + $top + len($kids) > $limit) {
            fail("a descendant segment visited more than " + convert.toString($limit) + " nodes");
        }
        while ($k >= 0) {
            if ($top < len($stack)) {
                $stack[$top] = $kids[$k];
            } else {
                $stack[] = $kids[$k];
            }
            $top = $top + 1;
            $k = $k - 1;
        }
    }
    return $out;
}

/**
 * A node's children that are arrays or objects.
 *
 * @param loc {Loc} the node
 * @param track {bool} build pointers and normalized paths
 * @return {list of Loc} those children, in order
 */
func containerChildren(loc as Loc, track as bool) {
    def out as list of Loc init [];
    def type as string init json.typeOf($loc.value);
    if ($type == "list") {
        def n as int init json.length($loc.value);
        def i as int init 0;
        while ($i < $n) {
            def kind as string init json.typeOf($loc.value, "/" + convert.toString($i));
            if ($kind == "list" or $kind == "map") {
                $out[] = element($loc, $i, $track);
            }
            $i = $i + 1;
        }
    } elseif ($type == "map") {
        for (def key in json.keys($loc.value)) {
            def kind as string init json.typeOf($loc.value, "/" + pointerToken($key));
            if ($kind == "list" or $kind == "map") {
                $out[] = member($loc, $key, $track);
            }
        }
    }
    return $out;
}

/**
 * The indexes a slice selects (RFC 9535 section 2.3.4.2.2).
 *
 * @param n {Node} the slice
 * @param size {int} the array's length
 * @return {list of int} the indexes, in selection order
 */
func sliceIndexes(n as Node, size as int) {
    def out as list of int init [];
    def step as int init $n.step;
    if ($step == 0) {
        return $out;
    }
    def start as int init 0;
    def stop as int init $size;
    if ($step < 0) {
        $start = $size - 1;
        $stop = 0 - $size - 1;
    }
    if ($n.hasStart) {
        $start = $n.start;
    }
    if ($n.hasStop) {
        $stop = $n.stop;
    }
    if ($start < 0) {
        $start = $start + $size;
    }
    if ($stop < 0) {
        $stop = $stop + $size;
    }
    if ($step > 0) {
        def i as int init clamp($start, 0, $size);
        def upper as int init clamp($stop, 0, $size);
        while ($i < $upper) {
            $out[] = $i;
            $i = $i + $step;
        }
        return $out;
    }
    def i as int init clamp($start, -1, $size - 1);
    def lower as int init clamp($stop, -1, $size - 1);
    while ($lower < $i) {
        $out[] = $i;
        $i = $i + $step;
    }
    return $out;
}

/**
 * Clamp a number into a range.
 *
 * @param x {int} the number
 * @param low {int} the lowest result
 * @param high {int} the highest result
 * @return {int} `x`, or the bound it passed
 */
func clamp(x as int, low as int, high as int) {
    if ($x < $low) {
        return $low;
    }
    if ($x > $high) {
        return $high;
    }
    return $x;
}

/**
 * Evaluate a logical expression for one current node.
 *
 * @param path {Path} the parsed query
 * @param idx {int} the expression node
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node, `@`
 * @return {bool} the result
 */
func evalLogical(path as Path, idx as int, root as json.Value, cur as json.Value) {
    def kind as int init $path.nodes[$idx].kind;
    if ($kind == KOR) {
        for (def k in $path.nodes[$idx].kids) {
            if (evalLogical($path, $k, $root, $cur)) {
                return true;
            }
        }
        return false;
    }
    if ($kind == KAND) {
        for (def k in $path.nodes[$idx].kids) {
            if (not evalLogical($path, $k, $root, $cur)) {
                return false;
            }
        }
        return true;
    }
    if ($kind == KNOT) {
        return not evalLogical($path, $path.nodes[$idx].kids[0], $root, $cur);
    }
    if ($kind == KTEST) {
        return evalLogical($path, $path.nodes[$idx].kids[0], $root, $cur);
    }
    if ($kind == KQUERY and $path.nodes[$idx].num == 1) {
        return singularValue($path, $idx, $root, $cur).present;
    }
    if ($kind == KQUERY) {
        return len(selectQuery($path, $idx, $root, $cur, false)) > 0;
    }
    if ($kind == KCACHED) {
        return $path.nodes[$idx].num > 0;
    }
    if ($kind == KCMP) {
        def kids as list of int init $path.nodes[$idx].kids;
        def a as Val init evalValue($path, $kids[0], $root, $cur);
        def b as Val init evalValue($path, $kids[1], $root, $cur);
        return compare($a, $b, $path.nodes[$idx].text);
    }
    if ($kind == KFUNC and $path.nodes[$idx].num == TLOGICAL) {
        def kids as list of int init $path.nodes[$idx].kids;
        def subject as Val init evalValue($path, $kids[0], $root, $cur);
        def whole as bool init $path.nodes[$idx].text == "match";
        def compiled as int init $path.nodes[$idx].start;
        if ($compiled == 1) {
            return matchRe2($subject, json.asString($path.nodes[$idx].lit), $whole);
        }
        if ($compiled == 2) {
            return false;
        }
        return fnMatch($subject, evalValue($path, $kids[1], $root, $cur), $whole);
    }
    return false;
}

/**
 * Evaluate a comparable: a literal, a singular query or a function returning
 * a value.
 *
 * @param path {Path} the parsed query
 * @param idx {int} the node
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node
 * @return {Val} the value, or Nothing
 */
func evalValue(path as Path, idx as int, root as json.Value, cur as json.Value) {
    def kind as int init $path.nodes[$idx].kind;
    if ($kind == KLITERAL) {
        return Val{present: true, value: $path.nodes[$idx].lit};
    }
    if ($kind == KQUERY) {
        return singularValue($path, $idx, $root, $cur);
    }
    if ($kind == KCACHED) {
        if ($path.nodes[$idx].num == 1) {
            return Val{present: true, value: $path.nodes[$idx].lit};
        }
        return nothing();
    }
    if ($kind != KFUNC) {
        return nothing();
    }
    def name as string init $path.nodes[$idx].text;
    def arg as int init $path.nodes[$idx].kids[0];
    if ($name == "length") {
        return fnLength(evalValue($path, $arg, $root, $cur));
    }
    def count as int init 0;
    def first as json.Value init json.decode("null");
    if ($path.nodes[$arg].kind == KCACHED) {
        $count = $path.nodes[$arg].num;
        $first = $path.nodes[$arg].lit;
    } elseif ($path.nodes[$arg].kind == KQUERY) {
        def nodes as list of Loc init selectQuery($path, $arg, $root, $cur, false);
        $count = len($nodes);
        if ($count > 0) {
            $first = $nodes[0].value;
        }
    }
    if ($name == "count") {
        return Val{present: true, value: jsonInt($count)};
    }
    if ($count == 1) {
        return Val{present: true, value: $first};
    }
    return nothing();
}

/**
 * Walk a singular query (names and indexes only) straight down, without
 * building node lists: the operand of nearly every comparison.
 *
 * @param path {Path} the parsed query
 * @param q {int} the query node, singular
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node
 * @return {Val} the node's value, or Nothing
 */
func singularValue(path as Path, q as int, root as json.Value, cur as json.Value) {
    def v as json.Value init $cur;
    if ($path.nodes[$q].text == "$") {
        $v = $root;
    }
    for (def seg in $path.nodes[$q].kids) {
        def sel as int init $path.nodes[$seg].kids[0];
        def type as string init json.typeOf($v);
        if ($path.nodes[$sel].kind == KNAME) {
            def ptr as string init "/" + pointerToken($path.nodes[$sel].text);
            if ($type != "map" or not json.has($v, $ptr)) {
                return nothing();
            }
            $v = json.get($v, $ptr);
        } else {
            if ($type != "list") {
                return nothing();
            }
            def i as int init $path.nodes[$sel].num;
            def size as int init json.length($v);
            if ($i < 0) {
                $i = $i + $size;
            }
            if ($i < 0 or $i >= $size) {
                return nothing();
            }
            $v = json.get($v, "/" + convert.toString($i));
        }
    }
    return Val{present: true, value: $v};
}

/**
 * Compare two values (RFC 9535 section 2.3.5.2.2).
 *
 * @param a {Val} the left side
 * @param b {Val} the right side
 * @param op {string} `==`, `!=`, `<`, `<=`, `>` or `>=`
 * @return {bool} the result
 */
func compare(a as Val, b as Val, op as string) {
    if ($op == "==") {
        return same($a, $b);
    } elseif ($op == "!=") {
        return not same($a, $b);
    } elseif ($op == "<") {
        return before($a, $b);
    } elseif ($op == ">") {
        return before($b, $a);
    } elseif ($op == "<=") {
        return before($a, $b) or same($a, $b);
    }
    return before($b, $a) or same($a, $b);
}

/**
 * Whether a value is a number.
 *
 * @param v {json.Value} the value
 * @return {bool} true for an int or a float
 */
func isNumber(v as json.Value) {
    def kind as string init json.typeOf($v);
    return $kind == "int" or $kind == "float";
}

/**
 * Equality: Nothing equals only Nothing, numbers by value, everything else
 * structurally.
 *
 * @param a {Val} one value
 * @param b {Val} the other
 * @return {bool} whether they are equal
 */
func same(a as Val, b as Val) {
    if (not $a.present or not $b.present) {
        return $a.present == $b.present;
    }
    if (isNumber($a.value) and isNumber($b.value)) {
        if (json.typeOf($a.value) == "int" and json.typeOf($b.value) == "int") {
            return json.asInt($a.value) == json.asInt($b.value);
        }
        return json.asFloat($a.value) == json.asFloat($b.value);
    }
    return $a.value == $b.value;
}

/**
 * Order: only two numbers or two strings are ordered.
 *
 * @param a {Val} one value
 * @param b {Val} the other
 * @return {bool} whether `a` comes before `b`
 */
func before(a as Val, b as Val) {
    if (not $a.present or not $b.present) {
        return false;
    }
    if (isNumber($a.value) and isNumber($b.value)) {
        if (json.typeOf($a.value) == "int" and json.typeOf($b.value) == "int") {
            return json.asInt($a.value) < json.asInt($b.value);
        }
        return json.asFloat($a.value) < json.asFloat($b.value);
    }
    if (json.typeOf($a.value) == "string" and json.typeOf($b.value) == "string") {
        return json.asString($a.value) < json.asString($b.value);
    }
    return false;
}
