# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonpath - evaluation (RFC 9535 sections 2.3 to 2.5) and the public
# functions. Spliced into jsonpath.j via include.

/**
 * A node during evaluation. `ptr` and `norm` are built only when the caller
 * asked for them, never for the queries inside a filter.
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

# What `run` builds for each node: bits of a `track` argument.
def const TRACK_POINTER as int init 1;
def const TRACK_PATH as int init 2;

/**
 * The state of one run of a query, passed in place (`$w = f($w, ...)`)
 * through the evaluator. Every query, subqueries included, appends its nodes
 * to `out`; a subquery's are dropped again by resetting `n`.
 *
 * @field out {list of Loc} the node buffer; entries from `n` on are stale
 * @field n {int} how many entries of `out` are live
 * @field from {int} where the result of the last `selectQuery` starts in `out`
 * @field used {int} the work so far, in nodes; at most `Path.maxNodes`
 * @field hit {bool} the result of the last `evalLogical`
 * @field val {Val} the result of the last `evalValue`
 * @field other {Val} the result of the last `evalValue` for a right operand
 * @field count {map of int to int} per `$` query inside a filter: its node count
 * @field first {map of int to json.Value} per `$` query inside a filter: its first node
 * @field rx {map of string to Rx} patterns from the document, translated
 */
def struct Work {
    out as list of Loc,
    n as int,
    from as int,
    used as int,
    hit as bool,
    val as Val,
    other as Val,
    count as map of int to int,
    first as map of int to json.Value,
    rx as map of string to Rx
};

/**
 * Parse a query once, to run it against many documents with `find`.
 *
 * @param path {string} the JSONPath query, e.g. `$.store.book[?@.price < 10].title`
 * @return {Path} the parsed query
 * @throws {Error} kind `"jsonpath"` when the query is not valid RFC 9535,
 *   naming the position of the first error, or when a literal `match` /
 *   `search` pattern is valid I-Regexp that RE2 cannot compile
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
        fail("cannot parse " + quoted(cut($path)) + ": " + $e.message);
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
 * @throws {Error} kind `"jsonpath"` when the query needs more than
 *   `path.maxNodes` nodes of work, when a `match` / `search` pattern from
 *   the document is valid I-Regexp that RE2 cannot compile, or when `path`
 *   does not come from `compile`
 */
export func find(doc as json.Value, path as Path) {
    def w as Work init run($doc, $path, TRACK_POINTER | TRACK_PATH);
    def out as list of Match init [];
    def i as int init $w.from;
    while ($i < $w.n) {
        $out[] = Match{value: $w.out[$i].value, pointer: $w.out[$i].ptr, path: $w.out[$i].norm};
        $i = $i + 1;
    }
    return $out;
}

/**
 * The values a query selects.
 *
 * @param doc {json.Value} the document
 * @param path {string} the query
 * @return {list of json.Value} the values, in order
 * @throws {Error} kind `"jsonpath"` when the query is not valid, when it
 *   needs more than `MAX_NODES` nodes of work, or when a pattern is valid
 *   I-Regexp that RE2 cannot compile
 */
export func query(doc as json.Value, path as string) {
    def w as Work init run($doc, compile($path), 0);
    def out as list of json.Value init [];
    def i as int init $w.from;
    while ($i < $w.n) {
        $out[] = $w.out[$i].value;
        $i = $i + 1;
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
 * @throws {Error} kind `"jsonpath"` when the query is not valid, when it
 *   needs more than `MAX_NODES` nodes of work, or when a pattern is valid
 *   I-Regexp that RE2 cannot compile
 */
export func paths(doc as json.Value, path as string) {
    def w as Work init run($doc, compile($path), TRACK_POINTER);
    def out as list of string init [];
    def i as int init $w.from;
    while ($i < $w.n) {
        $out[] = $w.out[$i].ptr;
        $i = $i + 1;
    }
    return $out;
}

/**
 * The normalized paths (RFC 9535 section 2.7) of the nodes a query selects.
 *
 * @param doc {json.Value} the document
 * @param path {string} the query
 * @return {list of string} the paths, e.g. `$['store']['book'][0]`
 * @throws {Error} kind `"jsonpath"` when the query is not valid, when it
 *   needs more than `MAX_NODES` nodes of work, or when a pattern is valid
 *   I-Regexp that RE2 cannot compile
 */
export func normalizedPaths(doc as json.Value, path as string) {
    def w as Work init run($doc, compile($path), TRACK_PATH);
    def out as list of string init [];
    def i as int init $w.from;
    while ($i < $w.n) {
        $out[] = $w.out[$i].norm;
        $i = $i + 1;
    }
    return $out;
}

/**
 * Run a parsed query. First every `$` query inside a filter runs once and
 * its count and first node are kept in `Work`: its result does not depend
 * on `@`, and `$..*[?count($..*) > 0]` would otherwise walk the document
 * once per node. Inner queries have lower indexes than outer ones, so they
 * are cached first. The `Path` itself is only read, never copied.
 *
 * @param doc {json.Value} the document
 * @param path {Path} the parsed query
 * @param track {int} `TRACK_POINTER` and `TRACK_PATH` bits: what to build
 * @return {Work} the state; the result is `out[from:n]`
 * @throws {Error} kind `"jsonpath"` when `path` is no compiled query, or
 *   the query needs more than `path.maxNodes` nodes of work
 */
func run(doc as json.Value, path as Path, track as int) {
    if ($path.root < 0 or $path.root >= len($path.nodes) or
        $path.nodes[$path.root].kind != KQUERY) {
        fail("not a compiled Path; build one with compile");
    }
    def w as Work init Work{
        out: [],
        n: 0,
        from: 0,
        used: 0,
        hit: false,
        val: nothing(),
        other: nothing(),
        count: {},
        first: {},
        rx: {}
    };
    def i as int init 0;
    if ($path.nodes[$path.root].start != 1) {
        $i = len($path.nodes);
    }
    while ($i < len($path.nodes)) {
        if ($i != $path.root and $path.nodes[$i].kind == KQUERY and $path.nodes[$i].text == "$") {
            def mark as int init $w.n;
            $w = selectQuery($path, $i, $doc, $doc, 0, $w);
            $w.count[$i] = $w.n - $w.from;
            if ($w.n > $w.from) {
                $w.first[$i] = $w.out[$w.from].value;
            }
            $w.n = $mark;
        }
        $i = $i + 1;
    }
    $w = selectQuery($path, $path.root, $doc, $doc, $track, $w);
    return $w;
}

/**
 * Count work against the limit before doing it.
 *
 * @param w {Work} the state
 * @param nodes {int} the nodes about to be produced, tested or visited
 * @param limit {int} `Path.maxNodes`
 * @return {Work} the state with the work counted
 * @throws {Error} kind `"jsonpath"` when the total would pass `limit`
 */
func spend(w as Work, nodes as int, limit as int) {
    if ($w.used + $nodes > $limit) {
        overLimit($limit);
    }
    $w.used = $w.used + $nodes;
    return $w;
}

/**
 * Raise the work-limit error.
 *
 * @param limit {int} `Path.maxNodes`
 * @throws {Error} always, with `kind` `"jsonpath"`
 */
func overLimit(limit as int) {
    fail("the query needs more than " + convert.toString($limit) + " nodes of work");
}

/**
 * Append a node to the buffer. The per-node loops inline this.
 *
 * @param w {Work} the state
 * @param loc {Loc} the node
 * @return {Work} the state holding it
 */
func put(w as Work, loc as Loc) {
    if ($w.n < len($w.out)) {
        $w.out[$w.n] = $loc;
    } else {
        $w.out[] = $loc;
    }
    $w.n = $w.n + 1;
    return $w;
}

/**
 * Run a query node from its identifier: `$` from the root, `@` from the
 * current node. Each segment reads the previous one's nodes from
 * `out[from:to]` and appends its own after them.
 *
 * @param path {Path} the parsed query
 * @param q {int} the query node
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node of a filter
 * @param track {int} what to build, `TRACK_POINTER` / `TRACK_PATH` bits
 * @param w {Work} the state
 * @return {Work} the state; the selected nodes are `out[from:n]`
 */
func selectQuery(
    path as Path,
    q as int,
    root as json.Value,
    cur as json.Value,
    track as int,
    w as Work) {
    def start as json.Value init $cur;
    if ($path.nodes[$q].text == "$") {
        $start = $root;
    }
    $w = put($w, Loc{value: $start, ptr: "", norm: "$"});
    def from as int init $w.n - 1;
    for (def seg in $path.nodes[$q].kids) {
        def end as int init $w.n;
        $w = applySegment($path, $seg, $from, $end, $root, $track, $w);
        $from = $end;
        if ($w.n == $from) {
            break;
        }
    }
    $w.from = $from;
    return $w;
}

/**
 * Apply a segment to every input node.
 *
 * @param path {Path} the parsed query
 * @param seg {int} the segment node
 * @param from {int} the first input node in `out`
 * @param end {int} the end of the input nodes in `out`
 * @param root {json.Value} the document
 * @param track {int} what to build
 * @param w {Work} the state
 * @return {Work} the state with the output nodes appended
 */
func applySegment(
    path as Path,
    seg as int,
    from as int,
    end as int,
    root as json.Value,
    track as int,
    w as Work) {
    def descendant as bool init $path.nodes[$seg].num == 1;
    # Name and index selectors take one node of work per input node, counted
    # up front; the other selectors count what they produce or test.
    def fixed as int init 0;
    for (def sel in $path.nodes[$seg].kids) {
        if ($path.nodes[$sel].kind == KNAME or $path.nodes[$sel].kind == KINDEX) {
            $fixed = $fixed + 1;
        }
    }
    if (not $descendant) {
        $w = spend($w, ($end - $from) * $fixed, $path.maxNodes);
    }
    def i as int init $from;
    while ($i < $end) {
        # A copy: passing $w.out[$i] beside $w would copy all of $w.
        def loc as Loc init $w.out[$i];
        if ($descendant) {
            def ds as list of Loc init descendants(
                $loc,
                $track,
                $path.maxNodes - $w.used,
                $path.maxNodes);
            $w.used = $w.used + len($ds);
            $w = spend($w, len($ds) * $fixed, $path.maxNodes);
            for (def d in $ds) {
                $w = applySelectors($path, $seg, $d, $root, $track, $w);
            }
        } else {
            $w = applySelectors($path, $seg, $loc, $root, $track, $w);
        }
        $i = $i + 1;
    }
    return $w;
}

/**
 * Apply a segment's selectors, in order, to one node.
 *
 * @param path {Path} the parsed query
 * @param seg {int} the segment node
 * @param loc {Loc} the node
 * @param root {json.Value} the document
 * @param track {int} what to build
 * @param w {Work} the state
 * @return {Work} the state with this node's results appended
 */
func applySelectors(
    path as Path,
    seg as int,
    loc as Loc,
    root as json.Value,
    track as int,
    w as Work) {
    for (def sel in $path.nodes[$seg].kids) {
        $w = applySelector($path, $sel, $loc, $root, $track, $w);
    }
    return $w;
}

/**
 * Apply one selector to one node, counting its work first.
 *
 * @param path {Path} the parsed query
 * @param sel {int} the selector node
 * @param loc {Loc} the node
 * @param root {json.Value} the document
 * @param track {int} what to build
 * @param w {Work} the state
 * @return {Work} the state with this selector's results appended
 */
func applySelector(
    path as Path,
    sel as int,
    loc as Loc,
    root as json.Value,
    track as int,
    w as Work) {
    def kind as int init $path.nodes[$sel].kind;
    def type as string init json.typeOf($loc.value);
    if ($kind == KNAME) {
        def name as string init $path.nodes[$sel].text;
        def token as string init pointerToken($name);
        def ptr as string init "/" + $token;
        if ($type == "map" and json.has($loc.value, $ptr)) {
            def next as Loc init member($loc, $name, $token, json.get($loc.value, $ptr), $track);
            if ($w.n < len($w.out)) {
                $w.out[$w.n] = $next;
            } else {
                $w.out[] = $next;
            }
            $w.n = $w.n + 1;
        }
    } elseif ($kind == KWILD) {
        $w = children($path, $loc, $track, $w);
    } elseif ($kind == KINDEX and $type == "list") {
        def size as int init json.length($loc.value);
        def i as int init $path.nodes[$sel].num;
        if ($i < 0) {
            $i = $i + $size;
        }
        if ($i >= 0 and $i < $size) {
            def next as Loc init element($loc, $i, $track);
            if ($w.n < len($w.out)) {
                $w.out[$w.n] = $next;
            } else {
                $w.out[] = $next;
            }
            $w.n = $w.n + 1;
        }
    } elseif ($kind == KSLICE and $type == "list") {
        def picked as list of int init sliceIndexes($path.nodes[$sel], json.length($loc.value));
        $w = spend($w, len($picked), $path.maxNodes);
        for (def i in $picked) {
            def next as Loc init element($loc, $i, $track);
            if ($w.n < len($w.out)) {
                $w.out[$w.n] = $next;
            } else {
                $w.out[] = $next;
            }
            $w.n = $w.n + 1;
        }
    } elseif ($kind == KFILTER and ($type == "list" or $type == "map")) {
        $w = applyFilter($path, $path.nodes[$sel].kids[0], $loc, $root, $track, $w);
    }
    return $w;
}

/**
 * Apply a filter to an array's elements or an object's members, building
 * a full result entry only for those that pass. Every tested child counts
 * as work.
 *
 * @param path {Path} the parsed query
 * @param test {int} the filter's expression
 * @param loc {Loc} the array or object
 * @param root {json.Value} the document
 * @param track {int} what to build
 * @param w {Work} the state
 * @return {Work} the state with the passing children appended
 */
func applyFilter(
    path as Path,
    test as int,
    loc as Loc,
    root as json.Value,
    track as int,
    w as Work) {
    def cost as int init $path.nodes[$test].step;
    if (json.typeOf($loc.value) == "list") {
        def n as int init json.length($loc.value);
        $w = spend($w, $n * (1 + clamp($cost, 0, $cost)), $path.maxNodes);
        def i as int init 0;
        while ($i < $n) {
            def item as json.Value init json.get($loc.value, "/" + convert.toString($i));
            if ($cost >= 0) {
                $w.hit = holds($path, $test, $root, $item, $w);
            } else {
                $w = evalLogical($path, $test, $root, $item, $w);
            }
            if ($w.hit) {
                def next as Loc init element($loc, $i, $track);
                if ($w.n < len($w.out)) {
                    $w.out[$w.n] = $next;
                } else {
                    $w.out[] = $next;
                }
                $w.n = $w.n + 1;
            }
            $i = $i + 1;
        }
        return $w;
    }
    def keys as list of string init json.keys($loc.value);
    $w = spend($w, len($keys) * (1 + clamp($cost, 0, $cost)), $path.maxNodes);
    for (def key in $keys) {
        def token as string init $key;
        if (strings.contains($key, "~") or strings.contains($key, "/")) {
            $token = pointerToken($key);
        }
        def item as json.Value init json.get($loc.value, "/" + $token);
        if ($cost >= 0) {
            $w.hit = holds($path, $test, $root, $item, $w);
        } else {
            $w = evalLogical($path, $test, $root, $item, $w);
        }
        if ($w.hit) {
            def next as Loc init member($loc, $key, $token, $item, $track);
            if ($w.n < len($w.out)) {
                $w.out[$w.n] = $next;
            } else {
                $w.out[] = $next;
            }
            $w.n = $w.n + 1;
        }
    }
    return $w;
}

/**
 * A member of an object node.
 *
 * @param loc {Loc} the object node
 * @param name {string} the member name
 * @param token {string} the name escaped for a JSON Pointer
 * @param value {json.Value} the member's value
 * @param track {int} what to build
 * @return {Loc} the member
 */
func member(loc as Loc, name as string, token as string, value as json.Value, track as int) {
    def out as Loc init Loc{value: $value, ptr: "", norm: ""};
    if (($track & TRACK_POINTER) != 0) {
        $out.ptr = $loc.ptr + "/" + $token;
    }
    if (($track & TRACK_PATH) != 0) {
        $out.norm = $loc.norm + "['" + normalName($name) + "']";
    }
    return $out;
}

/**
 * An element of an array node.
 *
 * @param loc {Loc} the array node
 * @param i {int} the index, within the array
 * @param track {int} what to build
 * @return {Loc} the element
 */
func element(loc as Loc, i as int, track as int) {
    def index as string init convert.toString($i);
    def out as Loc init Loc{value: json.get($loc.value, "/" + $index), ptr: "", norm: ""};
    if (($track & TRACK_POINTER) != 0) {
        $out.ptr = $loc.ptr + "/" + $index;
    }
    if (($track & TRACK_PATH) != 0) {
        $out.norm = $loc.norm + "[" + $index + "]";
    }
    return $out;
}

/**
 * Append a node's children: an array's elements, an object's member values
 * in document order; nothing for a scalar.
 *
 * @param path {Path} the parsed query, for its limit
 * @param loc {Loc} the node
 * @param track {int} what to build
 * @param w {Work} the state
 * @return {Work} the state with the children appended
 */
func children(path as Path, loc as Loc, track as int, w as Work) {
    def type as string init json.typeOf($loc.value);
    if ($type == "list") {
        def n as int init json.length($loc.value);
        $w = spend($w, $n, $path.maxNodes);
        def i as int init 0;
        while ($i < $n) {
            def next as Loc init element($loc, $i, $track);
            if ($w.n < len($w.out)) {
                $w.out[$w.n] = $next;
            } else {
                $w.out[] = $next;
            }
            $w.n = $w.n + 1;
            $i = $i + 1;
        }
    } elseif ($type == "map") {
        def keys as list of string init json.keys($loc.value);
        $w = spend($w, len($keys), $path.maxNodes);
        for (def key in $keys) {
            def token as string init $key;
            if (strings.contains($key, "~") or strings.contains($key, "/")) {
                $token = pointerToken($key);
            }
            def next as Loc init member(
                $loc,
                $key,
                $token,
                json.get($loc.value, "/" + $token),
                $track);
            if ($w.n < len($w.out)) {
                $w.out[$w.n] = $next;
            } else {
                $w.out[] = $next;
            }
            $w.n = $w.n + 1;
        }
    }
    return $w;
}

/**
 * A node and all its descendants that are arrays or objects, each before its
 * own descendants, children in order. Scalars are left out: no selector
 * selects anything from them. Walks with a stack, so a deep document does
 * not reach the call depth limit.
 *
 * @param loc {Loc} the node
 * @param track {int} what to build
 * @param room {int} the most nodes to visit, visited and queued together
 * @param limit {int} `Path.maxNodes`, for the error
 * @return {list of Loc} the node and its container descendants
 * @throws {Error} kind `"jsonpath"` past `room`
 */
func descendants(loc as Loc, track as int, room as int, limit as int) {
    if ($room < 1) {
        overLimit($limit);
    }
    def out as list of Loc init [];
    def stack as list of Loc init [$loc];
    def top as int init 1;
    while ($top > 0) {
        $top = $top - 1;
        $out[] = $stack[$top];
        def kids as list of Loc init containerChildren($out[len($out) - 1], $track);
        if (len($out) + $top + len($kids) > $room) {
            overLimit($limit);
        }
        def k as int init len($kids) - 1;
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
 * @param track {int} what to build
 * @return {list of Loc} those children, in order
 */
func containerChildren(loc as Loc, track as int) {
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
            def token as string init $key;
            if (strings.contains($key, "~") or strings.contains($key, "/")) {
                $token = pointerToken($key);
            }
            def child as json.Value init json.get($loc.value, "/" + $token);
            def kind as string init json.typeOf($child);
            if ($kind == "list" or $kind == "map") {
                $out[] = member($loc, $key, $token, $child, $track);
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
 * @param w {Work} the state
 * @return {Work} the state; `hit` is the result
 */
func evalLogical(path as Path, idx as int, root as json.Value, cur as json.Value, w as Work) {
    def cost as int init $path.nodes[$idx].step;
    if ($cost >= 0) {
        $w = spend($w, $cost, $path.maxNodes);
        $w.hit = holds($path, $idx, $root, $cur, $w);
        return $w;
    }
    def kind as int init $path.nodes[$idx].kind;
    if ($kind == KOR) {
        for (def k in $path.nodes[$idx].kids) {
            $w = evalLogical($path, $k, $root, $cur, $w);
            if ($w.hit) {
                return $w;
            }
        }
        return $w;
    }
    if ($kind == KAND) {
        for (def k in $path.nodes[$idx].kids) {
            $w = evalLogical($path, $k, $root, $cur, $w);
            if (not $w.hit) {
                return $w;
            }
        }
        return $w;
    }
    if ($kind == KNOT) {
        $w = evalLogical($path, $path.nodes[$idx].kids[0], $root, $cur, $w);
        $w.hit = not $w.hit;
        return $w;
    }
    if ($kind == KTEST) {
        $w = evalLogical($path, $path.nodes[$idx].kids[0], $root, $cur, $w);
        return $w;
    }
    if ($kind == KQUERY) {
        def mark as int init $w.n;
        $w = selectQuery($path, $idx, $root, $cur, 0, $w);
        $w.hit = $w.n > $w.from;
        $w.n = $mark;
        return $w;
    }
    if ($kind == KCMP) {
        def kids as list of int init $path.nodes[$idx].kids;
        $w = evalValue($path, $kids[0], $root, $cur, false, $w);
        $w = evalValue($path, $kids[1], $root, $cur, true, $w);
        $w.hit = compare($w.val, $w.other, $path.nodes[$idx].text);
        return $w;
    }
    $w.hit = false;
    if ($kind == KFUNC and $path.nodes[$idx].num == TLOGICAL) {
        $w = evalMatch($path, $idx, $root, $cur, $w);
    }
    return $w;
}

/**
 * Evaluate `match` or `search`. A pattern from the document is translated
 * once per run and kept in `Work.rx`.
 *
 * @param path {Path} the parsed query
 * @param idx {int} the call
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node, `@`
 * @param w {Work} the state
 * @return {Work} the state; `hit` is the result
 * @throws {Error} kind `"jsonpath"` when RE2 cannot compile the pattern
 */
func evalMatch(path as Path, idx as int, root as json.Value, cur as json.Value, w as Work) {
    def kids as list of int init $path.nodes[$idx].kids;
    $w = evalValue($path, $kids[0], $root, $cur, false, $w);
    def whole as bool init $path.nodes[$idx].text == "match";
    def compiled as int init $path.nodes[$idx].start;
    $w.hit = false;
    if ($compiled == 1) {
        $w.hit = matchRe2($w.val, json.asString($path.nodes[$idx].lit), $whole);
        return $w;
    }
    if ($compiled == 2) {
        return $w;
    }
    $w = evalValue($path, $kids[1], $root, $cur, true, $w);
    if (not $w.other.present or json.typeOf($w.other.value) != "string") {
        return $w;
    }
    def text as string init json.asString($w.other.value);
    if (not maps.has($w.rx, $text)) {
        $w.rx[$text] = translate($text);
    }
    $w.hit = fnMatch($w.val, $w.rx[$text], $whole);
    return $w;
}

/**
 * Evaluate a comparable: a literal, a singular query or a function returning
 * a value. The result goes to `Work.val`, or `Work.other` for the right side
 * of a comparison, so `compare` reads both without copying them.
 *
 * @param path {Path} the parsed query
 * @param idx {int} the node
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node
 * @param right {bool} store the result in `other`, not `val`
 * @param w {Work} the state
 * @return {Work} the state with the value, or Nothing, stored
 */
func evalValue(
    path as Path,
    idx as int,
    root as json.Value,
    cur as json.Value,
    right as bool,
    w as Work) {
    def cost as int init $path.nodes[$idx].step;
    if ($cost >= 0) {
        $w = spend($w, $cost, $path.maxNodes);
        if ($right) {
            $w.other = simpleValue($path, $idx, $root, $cur, $w);
        } else {
            $w.val = simpleValue($path, $idx, $root, $cur, $w);
        }
        return $w;
    }
    # Not simple: `length` of such an argument, or `count` / `value` of an
    # `@` query.
    def arg as int init $path.nodes[$idx].kids[0];
    if ($path.nodes[$idx].text == "length") {
        $w = evalValue($path, $arg, $root, $cur, $right, $w);
        if ($right) {
            $w.other = fnLength($w.other);
        } else {
            $w.val = fnLength($w.val);
        }
        return $w;
    }
    def mark as int init $w.n;
    $w = selectQuery($path, $arg, $root, $cur, 0, $w);
    def v as Val init nothing();
    if ($path.nodes[$idx].text == "count") {
        $v = Val{present: true, value: jsonInt($w.n - $w.from)};
    } elseif ($w.n - $w.from == 1) {
        $v = Val{present: true, value: $w.out[$w.from].value};
    }
    $w.n = $mark;
    if ($right) {
        $w.other = $v;
    } else {
        $w.val = $v;
    }
    return $w;
}

/**
 * Evaluate a simple logical expression (`staticCost` >= 0). Its work was
 * counted by the caller.
 *
 * @param path {Path} the parsed query
 * @param idx {int} the expression node
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node, `@`
 * @param w {Work} the state, read only: the `$` query results
 * @return {bool} the result
 */
func holds(path as Path, idx as int, root as json.Value, cur as json.Value, w as Work) {
    def kind as int init $path.nodes[$idx].kind;
    if ($kind == KOR) {
        for (def k in $path.nodes[$idx].kids) {
            if (holds($path, $k, $root, $cur, $w)) {
                return true;
            }
        }
        return false;
    }
    if ($kind == KAND) {
        for (def k in $path.nodes[$idx].kids) {
            if (not holds($path, $k, $root, $cur, $w)) {
                return false;
            }
        }
        return true;
    }
    if ($kind == KNOT) {
        return not holds($path, $path.nodes[$idx].kids[0], $root, $cur, $w);
    }
    if ($kind == KTEST) {
        return holds($path, $path.nodes[$idx].kids[0], $root, $cur, $w);
    }
    if ($kind == KQUERY and $path.nodes[$idx].text == "$") {
        return $w.count[$idx] > 0;
    }
    if ($kind == KQUERY) {
        return singularValue($path, $idx, $root, $cur).present;
    }
    if ($kind == KCMP) {
        def kids as list of int init $path.nodes[$idx].kids;
        return compare(
            simpleValue($path, $kids[0], $root, $cur, $w),
            simpleValue($path, $kids[1], $root, $cur, $w),
            $path.nodes[$idx].text);
    }
    if ($kind == KFUNC and $path.nodes[$idx].start == 1) {
        return matchRe2(
            simpleValue($path, $path.nodes[$idx].kids[0], $root, $cur, $w),
            json.asString($path.nodes[$idx].lit),
            $path.nodes[$idx].text == "match");
    }
    return false;
}

/**
 * Evaluate a simple comparable (`staticCost` >= 0). Its work was counted by
 * the caller.
 *
 * @param path {Path} the parsed query
 * @param idx {int} the node
 * @param root {json.Value} the document
 * @param cur {json.Value} the current node
 * @param w {Work} the state, read only: the `$` query results
 * @return {Val} the value, or Nothing
 */
func simpleValue(path as Path, idx as int, root as json.Value, cur as json.Value, w as Work) {
    def kind as int init $path.nodes[$idx].kind;
    if ($kind == KLITERAL) {
        return Val{present: true, value: $path.nodes[$idx].lit};
    }
    if ($kind == KQUERY and $path.nodes[$idx].text != "$") {
        return singularValue($path, $idx, $root, $cur);
    }
    if ($kind == KFUNC and $path.nodes[$idx].text == "length") {
        return fnLength(simpleValue($path, $path.nodes[$idx].kids[0], $root, $cur, $w));
    }
    def q as int init $idx;
    if ($kind == KFUNC) {
        $q = $path.nodes[$idx].kids[0];
    }
    if ($kind == KFUNC and $path.nodes[$idx].text == "count") {
        return Val{present: true, value: jsonInt($w.count[$q])};
    }
    if ($w.count[$q] == 1) {
        return Val{present: true, value: $w.first[$q]};
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
