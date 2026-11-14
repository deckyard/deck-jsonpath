# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# jsonpath - white-box tests for the evaluate topic. Spliced into jsonpath_test.j
# via include.

def const STORE as string init '{"store":{"book":[' +
    '{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},' +
    '{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},' +
    '{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99},' +
    '{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings",' +
    '"isbn":"0-395-19395-8","price":22.99}],' + '"bicycle":{"color":"red","price":399}}}';

/**
 * The strings of a list of values.
 *
 * @param vs {list of json.Value} string values
 * @return {list of string} the strings
 */
func texts(vs as list of json.Value) {
    def out as list of string init [];
    for (def v in $vs) {
        $out[] = json.asString($v);
    }
    return $out;
}

func badQuery() {
    query(json.decode('{}'), "$.");
}

func testTheRfcExamples() {
    def doc as json.Value init json.decode(STORE);
    testing.assertEqual(
        texts(query($doc, "$.store.book[*].author")),
        ["Nigel Rees", "Evelyn Waugh", "Herman Melville", "J. R. R. Tolkien"]);
    testing.assertEqual(len(query($doc, "$..author")), 4);
    testing.assertEqual(len(query($doc, "$.store.*")), 2);
    testing.assertEqual(len(query($doc, "$.store..price")), 5);
    testing.assertEqual(texts(query($doc, "$..book[2].title")), ["Moby Dick"]);
    testing.assertEqual(texts(query($doc, "$..book[-1].title")), ["The Lord of the Rings"]);
    testing.assertEqual(len(query($doc, "$..book[:2]")), 2);
    testing.assertEqual(
        texts(query($doc, "$..book[?@.isbn].title")),
        ["Moby Dick", "The Lord of the Rings"]);
    testing.assertEqual(
        texts(query($doc, "$..book[?@.price<10].title")),
        ["Sayings of the Century", "Moby Dick"]);
    testing.assertEqual(len(query($doc, "$..*")), 27);
    testing.assertEqual(texts(query($doc, "$..book[?match(@.author, '.*R\\\\.R.*')].title")), []);
    testing.assertEqual(
        texts(query($doc, "$..book[?search(@.author, 'R\\\\. R')].title")),
        ["The Lord of the Rings"]);
    testing.assertEqual(
        texts(query($doc, "$.store.book[?length(@.title) > 15].title")),
        ["Sayings of the Century", "The Lord of the Rings"]);
    testing.assertEqual(len(query($doc, "$.store[?count(@.*) > 2]")), 1);
}

func testPathsFeedTheJsonWriters() {
    def doc as json.Value init json.decode(STORE);
    def ptrs as list of string init paths($doc, "$..book[?@.price > 10]");
    testing.assertEqual($ptrs, ["/store/book/1", "/store/book/3"]);
    def i as int init len($ptrs) - 1;
    while ($i >= 0) {
        $doc = json.remove($doc, $ptrs[$i]);
        $i = $i - 1;
    }
    testing.assertEqual(json.length($doc, "/store/book"), 2);
    def odd as json.Value init json.set(json.map(), "/a b", json.map());
    $odd = json.set($odd, "/a b/it's", json.decode("[1]"));
    testing.assertEqual(normalizedPaths($odd, "$.*.*[0]"), ["$['a b']['it\\'s'][0]"]);
    testing.assertEqual(paths(json.decode('{"a/b":{"~":1}}'), "$..*"), ["/a~1b", "/a~1b/~0"]);
    testing.assertEqual(paths(json.decode("[1]"), "$"), [""]);
}

func testFindReturnsAllThree() {
    def p as Path init compile("$.a[?@ > 1]");
    def ms as list of Match init find(json.decode('{"a":[1,2,3]}'), $p);
    testing.assertEqual(len($ms), 2);
    testing.assertEqual($ms[0].pointer, "/a/1");
    testing.assertEqual($ms[0].path, "$['a'][1]");
    testing.assertEqual(json.asInt($ms[1].value), 3);
    testing.assertEqual(len(find(json.decode('{"a":[]}'), $p)), 0);
    testing.assertEqual(isValid("$.a[?@ > 1]"), true);
    testing.assertEqual(isValid("$.a[?@ >]"), false);
    testing.assertThrows("badQuery", ERROR_KIND);
}

func testSlices() {
    def doc as json.Value init json.decode("[0,1,2,3,4,5,6,7,8,9]");
    testing.assertEqual(json.encode(json.list(query($doc, "$[1:9:3]"))), "[1,4,7]");
    testing.assertEqual(json.encode(json.list(query($doc, "$[::-3]"))), "[9,6,3,0]");
    testing.assertEqual(json.encode(json.list(query($doc, "$[-2:]"))), "[8,9]");
    testing.assertEqual(json.encode(json.list(query($doc, "$[5:1:-2]"))), "[5,3]");
    testing.assertEqual(json.encode(json.list(query($doc, "$[::0]"))), "[]");
    testing.assertEqual(
        json.encode(json.list(query($doc, "$[-9007199254740991:9007199254740991:4]"))),
        "[0,4,8]");
}

func testComparisons() {
    def doc as json.Value init json.decode('[{"a":1},{"a":1.0},{"a":"1"},{"a":[1]},{"a":null},{}]');
    testing.assertEqual(len(query($doc, "$[?@.a == 1]")), 2);
    testing.assertEqual(len(query($doc, "$[?@.a != 1]")), 4);
    testing.assertEqual(len(query($doc, "$[?@.a == @.b]")), 1);
    testing.assertEqual(len(query($doc, "$[?@.a <= 1]")), 2);
    testing.assertEqual(len(query($doc, "$[?@.a < '2']")), 1);
    testing.assertEqual(len(query($doc, "$[?@.a == null]")), 1);
    testing.assertEqual(len(query($doc, "$[?!@.a]")), 1);
    testing.assertEqual(len(query($doc, "$[?value(@.a) == 1 || @.a == '1']")), 3);
}

func testDeepDocumentsWalkWithoutRecursion() {
    def doc as json.Value init json.decode(strings.repeat("[", 900) + "7" +
        strings.repeat("]", 900));
    def found as list of json.Value init query($doc, "$..*");
    testing.assertEqual(len($found), 900);
    testing.assertEqual(json.asInt($found[899]), 7);
}

func testSingularQueriesRespectTypes() {
    def doc as json.Value init json.decode('[{"a":{"0":"key"},"b":["el"]},{"a":["el"],"b":{"0":"key"}}]');
    testing.assertEqual(paths($doc, "$[?@.a[0]]"), ["/1"]);
    testing.assertEqual(len(query($doc, "$[?@.a['0'] == 'key']")), 1);
    testing.assertEqual(len(query($doc, "$[?@.b[-1] == 'el']")), 1);
    testing.assertEqual(len(query($doc, "$[?@.b[-2]]")), 0);
}

func testAbsoluteSubqueriesRunOnce() {
    def doc as json.Value init json.decode('{"max":2,"items":[1,2,3],"names":{"x":1}}');
    testing.assertEqual(json.encode(json.list(query($doc, "$.items[?@ <= $.max]"))), "[1,2]");
    testing.assertEqual(len(query($doc, "$.items[?count($.items[*]) == 3]")), 3);
    testing.assertEqual(len(query($doc, "$.items[?value($.names.x) == @]")), 1);
    testing.assertEqual(len(query($doc, "$.items[?$.nope]")), 0);
    def p as Path init compile("$.items[?@ <= $.max]");
    def before as list of Node init $p.nodes;
    def w as Work init run($doc, $p, 0);
    testing.assertEqual(len($w.count), 1);
    testing.assertEqual($p.nodes, $before);
    testing.assertEqual($p.nodes[$p.root].start, 1);
    def plain as Path init compile("$.items[?@ <= 2]");
    testing.assertEqual($plain.nodes[$plain.root].start, 0);
    testing.assertEqual(len(run($doc, $plain, 0).count), 0);
}

func testRunawayQueriesStop() {
    def doc as json.Value init json.decode(strings.repeat("[", 300) + strings.repeat("]", 300));
    def p as Path init compile("$..*..*..*");
    testing.assertEqual($p.maxNodes, MAX_NODES);
    $p.maxNodes = 20000;
    try {
        find($doc, $p);
        missed("a runaway query finished");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertTrue(strings.contains($e.message, "more than 20000 nodes of work"));
    }
    $p.maxNodes = 10;
    try {
        find(json.decode("[[[[[[[[[[[[1]]]]]]]]]]]]"), compile("$..*"));
        find(json.decode("[[[[[[[[[[[[1]]]]]]]]]]]]"), $p);
        missed("a deep descent passed a limit of 10");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertTrue(strings.contains($e.message, "more than 10 nodes of work"));
    }
}

/**
 * Run a query with a work limit.
 *
 * @param doc {json.Value} the document
 * @param query {string} the query
 * @param limit {int} `maxNodes`
 * @return {string} "" when it finished, else the error message
 */
func limited(doc as json.Value, query as string, limit as int) {
    def p as Path init compile($query);
    $p.maxNodes = $limit;
    try {
        find($doc, $p);
    } catch (e) {
        if ($e.kind != "limit") {
            testing.assertEqual($e.kind, ERROR_KIND);
        }
        return $e.message;
    }
    return "";
}

func testWorkIsCountedPerFind() {
    def grid as json.Value init json.decode("[[1,2],[3,4]]");
    testing.assertEqual(limited($grid, "$[*][*]", 6), "");
    testing.assertTrue(strings.contains(limited($grid, "$[*][*]", 5), "more than 5 nodes"));
    # Filter subqueries count too: 2 tests, then 2 elements per subquery.
    testing.assertEqual(limited($grid, "$[?@[*]]", 6), "");
    testing.assertTrue(strings.contains(limited($grid, "$[?@[*]]", 5), "more than 5 nodes"));
    def chain as json.Value init json.decode(strings.repeat("[", 60) + strings.repeat("]", 60));
    testing.assertTrue(strings.contains(limited($chain, "$..[?@..[?@..*]]", 5000), "more than"));
    def short as json.Value init json.decode(strings.repeat("[", 20) + strings.repeat("]", 20));
    testing.assertEqual(len(query($short, "$..[?@..[?@..*]]")), 17);
}

func testWorkIsCheckedBeforeItIsDone() {
    def wide as list of json.Value init [];
    def i as int init 0;
    while ($i < 2000) {
        $wide[] = jsonInt($i);
        $i = $i + 1;
    }
    def stars as string init "$[" + strings.join(lists.map(lists.range(0, 200), star), ",") + "]";
    testing.assertEqual(
        limited(json.list($wide), $stars, 1000),
        "jsonpath: the query needs more than 1000 nodes of work");
}

/**
 * A wildcard selector.
 *
 * @param i {int} ignored
 * @return {string} `*`
 */
func star(i as int) {
    return "*";
}

func badPath() {
    def p as Path;
    find(json.decode("[1]"), $p);
}

func testFindRefusesAForgedPath() {
    testing.assertThrows("badPath", ERROR_KIND);
    def p as Path init compile("$[0]");
    $p.root = 99;
    try {
        find(json.decode("[1]"), $p);
        missed("a forged root ran");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}

func testTrackBuildsOnlyWhatIsAsked() {
    def doc as json.Value init json.decode('{"a":[1]}');
    def p as Path init compile("$.a[0]");
    def w as Work init run($doc, $p, TRACK_POINTER);
    testing.assertEqual([$w.out[$w.from].ptr, $w.out[$w.from].norm], ["/a/0", ""]);
    $w = run($doc, $p, TRACK_PATH);
    testing.assertEqual([$w.out[$w.from].ptr, $w.out[$w.from].norm], ["", "$['a'][0]"]);
}

func testDocumentPatternsAreTranslatedOncePerRun() {
    def doc as json.Value init json.decode('[{"s":"ab","p":"a."},{"s":"xy","p":"a."},{"s":"c","p":"c"}]');
    def w as Work init run($doc, compile("$[?match(@.s, @.p)]"), 0);
    testing.assertEqual($w.n - $w.from, 2);
    testing.assertEqual(len($w.rx), 2);
}

/**
 * Remove every node a query selects, as `docs/index.md` shows: deepest and
 * highest index first, each pointer once.
 *
 * @param doc {json.Value} the document
 * @param query {string} the query
 * @return {json.Value} the document without those nodes
 */
func removeAll(doc as json.Value, query as string) {
    def byKey as map of string to string init {};
    for (def ptr in paths($doc, $query)) {
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
    return $doc;
}

func testRemovingWhatAQueryFound() {
    def doc as json.Value init json.decode('["a","b","c","d"]');
    testing.assertEqual(json.encode(removeAll($doc, "$[3,1]")), '["a","c"]');
    testing.assertEqual(json.encode(removeAll($doc, "$[::-1]")), "[]");
    testing.assertEqual(json.encode(removeAll($doc, "$[1,1,0]")), '["c","d"]');
    def big as json.Value init json.decode('{"x":[0,1,2,3,4,5,6,7,8,9,10,11],"y":[[1],[2]]}');
    testing.assertEqual(
        json.encode(removeAll($big, "$.x[2,10,9]")),
        '{"x":[0,1,3,4,5,6,7,8,11],"y":[[1],[2]]}');
    testing.assertEqual(
        json.encode(removeAll($big, "$.y..[0]")),
        '{"x":[0,1,2,3,4,5,6,7,8,9,10,11],"y":[[]]}');
}

func testLiteralPatternsAreTranslatedOnce() {
    def p as Path init compile("$[?match(@, 'a.') || search(@, '\\\\d')]");
    def flags as list of int init [];
    for (def n in $p.nodes) {
        if ($n.kind == KFUNC) {
            $flags[] = $n.start;
        }
    }
    testing.assertEqual($flags, [1, 2]);
    testing.assertEqual(
        texts(query(json.decode('["ab","a\\nb","b"]'), "$[?match(@, 'a.')]")),
        ["ab"]);
}
