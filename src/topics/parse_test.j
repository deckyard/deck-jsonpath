# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonpath - white-box tests for the parse topic. Spliced into jsonpath_test.j
# via include.

/**
 * The message `compile` gives for a query.
 *
 * @param path {string} the query
 * @return {string} the message; "" when it compiles
 */
func whyNot(path as string) {
    try {
        compile($path);
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
        return $e.message;
    }
    return "";
}

func testParseBuildsTheTree() {
    def p as Path init parse("$.a[0,'b']..c");
    def q as Node init $p.nodes[$p.root];
    testing.assertEqual($q.kind, KQUERY);
    testing.assertEqual($q.text, "$");
    testing.assertEqual(len($q.kids), 3);
    testing.assertEqual($q.num, 0);
    testing.assertEqual(len($p.nodes[$q.kids[1]].kids), 2);
    testing.assertEqual($p.nodes[$q.kids[2]].num, 1);
    testing.assertEqual(parse("$.a[0]['b']").nodes[parse("$.a[0]['b']").root].num, 1);
}

func testParseErrorsSayWhere() {
    testing.assertEqual(whyNot("$.a"), "");
    testing.assertEqual(whyNot("a.b"), 'jsonpath: a query starts with $ at position 0 of "a.b"');
    testing.assertEqual(whyNot("$.a b"), 'jsonpath: unexpected " " at position 3 of "$.a b"');
    testing.assertEqual(
        whyNot("$[01]"),
        'jsonpath: an integer has no leading zero at position 2 of "$[01]"');
    testing.assertEqual(whyNot("$[-0]"), 'jsonpath: -0 is not an integer at position 2 of "$[-0]"');
    testing.assertEqual(
        whyNot("$[9007199254740992]"),
        'jsonpath: an integer is at most 2^53 - 1 in size at position 2 of "$[9007199254740992]"');
    testing.assertTrue(strings.contains(whyNot("$[?@.a]x"), "unexpected"));
    testing.assertTrue(strings.contains(whyNot("$[?nope(@)]"), "unknown function nope()"));
    testing.assertTrue(strings.contains(
        whyNot("$[?length(@.*)<3]"),
        "argument 1 of length() has the wrong type"));
    testing.assertTrue(strings.contains(
        whyNot("$[?count(@)]"),
        "count() returns a value; compare it"));
    testing.assertTrue(strings.contains(whyNot("$[?match(@.a)]"), "match() takes 2 argument(s)"));
    testing.assertTrue(strings.contains(
        whyNot("$[?@.* == 1]"),
        "only a singular query can be compared"));
    testing.assertTrue(strings.contains(whyNot("$[?1]"), "a literal is not a test"));
    testing.assertTrue(strings.contains(whyNot("$[?@.a && true]"), "a literal is not a test"));
    testing.assertTrue(strings.contains(whyNot("$['\\x']"), "unknown escape"));
    testing.assertTrue(strings.contains(whyNot("$['\\uD800']"), "a high surrogate needs a low one"));
    testing.assertTrue(strings.contains(whyNot("$['a"), "unterminated string"));
    testing.assertTrue(strings.contains(whyNot("$[?@.a == 1e999]"), "number out of range"));
}

func testStringsDecodeEscapes() {
    def p as Path init parse("$['\\u00e9\\uD83D\\uDE00\\n\\'']");
    def seg as Node init $p.nodes[$p.nodes[$p.root].kids[0]];
    testing.assertEqual($p.nodes[$seg.kids[0]].text, "é" + convert.fromCodepoint(128512) + "\n'");
}

func testSlicesParse() {
    def p as Path init parse("$[1:-1:2, ::-1, :]");
    def seg as Node init $p.nodes[$p.nodes[$p.root].kids[0]];
    def a as Node init $p.nodes[$seg.kids[0]];
    testing.assertEqual([$a.start, $a.stop, $a.step], [1, -1, 2]);
    def b as Node init $p.nodes[$seg.kids[1]];
    testing.assertEqual([$b.hasStart, $b.hasStop, $b.step], [false, false, -1]);
    testing.assertEqual($p.nodes[$seg.kids[2]].step, 1);
}

func testDeepNestingIsRefusedEarly() {
    def ok as string init "$[?" + strings.repeat("(", MAX_NESTING - 1) + "@" +
        strings.repeat(")", MAX_NESTING - 1) + "]";
    testing.assertEqual(isValid($ok), true);
    def deep as string init "$[?" + strings.repeat("(", 20000) + "@" + strings.repeat(")", 20000) +
        "]";
    testing.assertTrue(strings.contains(whyNot($deep), "nested deeper than 64 levels"));
    def filters as string init "$" + strings.repeat("[?@", 100) + strings.repeat("]", 100);
    testing.assertTrue(strings.contains(whyNot($filters), "nested deeper than"));
    def calls as string init "$[?" + strings.repeat("length(", 100) + "@" +
        strings.repeat(")", 100) + "==1]";
    testing.assertTrue(strings.contains(whyNot($calls), "nested deeper than"));
}

func testMessagesQuoteTheQueryReadably() {
    testing.assertEqual(
        whyNot("$[?@.a <]"),
        'jsonpath: expected a query, a literal or a function, found "]" at position 8 of "$[?@.a <]"');
    testing.assertEqual(quoted("a<b>&\"\n"), "\"a<b>&\\\"\\n\"");
}

func testErrorMessagesAreBounded() {
    def long as string init "$.a" + strings.repeat("x", 100000) + "]";
    def why as string init whyNot($long);
    testing.assertTrue(len($why) < 200);
    testing.assertTrue(strings.contains($why, "at position 100003 of ...\""));
    testing.assertTrue(strings.endsWith($why, "x]\""));
    testing.assertTrue(len(whyNot("$[?" + strings.repeat("a", 5000) + "(@)]")) < 200);
    testing.assertTrue(len(whyNot("$[?@ == " + strings.repeat("1", 5000) + "e]")) < 200);
    testing.assertEqual(cut("short"), "short");
}
