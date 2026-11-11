# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# jsonpath - white-box tests for the functions topic. Spliced into jsonpath_test.j
# via include.

/**
 * The RE2 form of an I-Regexp.
 *
 * @param pattern {string} the I-Regexp
 * @return {string} the RE2 pattern; "!" when the pattern is invalid
 */
func re2(pattern as string) {
    def rx as Rx init translate($pattern);
    if (not $rx.ok) {
        return "!";
    }
    return $rx.re;
}

func testTranslateIRegexp() {
    testing.assertEqual(re2("a.b"), "a[^\\n\\r]b");
    testing.assertEqual(re2("[.a-z]"), "[.a-z]");
    testing.assertEqual(re2("[-a]"), "[\\-a]");
    testing.assertEqual(re2("[^a-]"), "[^a\\-]");
    testing.assertEqual(
        re2("\\p" + LBRACE + "Lu" + RBRACE + "+\\P" + LBRACE + "Nd" + RBRACE),
        "\\p" + LBRACE + "Lu" + RBRACE + "+\\P" + LBRACE + "Nd" + RBRACE);
    testing.assertEqual(
        re2("[\\p" + LBRACE + "L" + RBRACE + "_]"),
        "[\\p" + LBRACE + "L" + RBRACE + "_]");
    testing.assertEqual(
        re2("(ab|c)" + LBRACE + "2,3" + RBRACE),
        "(ab|c)" + LBRACE + "2,3" + RBRACE);
    testing.assertEqual(re2("\\.\\n\\t"), "\\.\\n\\t");
    testing.assertEqual(re2("^a$"), "^a$");
    testing.assertEqual(re2("[--]"), "[\\-\\-]");
    testing.assertEqual(re2("[a-c-]"), "[a-c\\-]");
    testing.assertEqual(re2("[\\n-\\r]"), "[\\n-\\r]");
    testing.assertEqual(re2("a" + LBRACE + "2,2" + RBRACE), "a" + LBRACE + "2,2" + RBRACE);
}

func testClassHyphenFollowsTheGrammar() {
    for (def bad in [
        "[a-b-c]",
        "[--/]",
        "[a--]",
        "[a-\\p" + LBRACE + "L" + RBRACE + "]",
        "[\\p" + LBRACE + "L" + RBRACE + "-a]",
        "[z-a]",
        "x" + LBRACE + "2,1" + RBRACE
    ]) {
        testing.assertEqual(re2($bad), "!");
    }
    def doc as json.Value init json.decode('["-","a","c","."]');
    testing.assertEqual(len(query($doc, "$[?match(@, '[a-b-c]')]")), 0);
    testing.assertEqual(len(query($doc, "$[?match(@, '[--/]')]")), 0);
}

func testEscapesAreScannedLocally() {
    def chars as list of string init strings.chars(
        "\\p" + LBRACE + "Lu" + RBRACE + "x" + strings.repeat("y", 50) + RBRACE);
    testing.assertEqual(escape($chars, 1).next, 6);
    def far as list of string init strings.chars("\\p" + LBRACE + "Luuuuu" + RBRACE);
    testing.assertEqual(escape($far, 1).ok, false);
}

func badRepeat() {
    compile("$[?match(@, 'a" + LBRACE + "1001" + RBRACE + "')]");
}

func badDocumentRepeat() {
    query(json.decode(json.encode(["a" + LBRACE + "2000" + RBRACE])), "$[?search('a', @)]");
}

func testPatternsRe2CannotRunThrow() {
    testing.assertThrows("badRepeat", ERROR_KIND);
    testing.assertThrows("badDocumentRepeat", ERROR_KIND);
    try {
        badDocumentRepeat();
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "RE2 cannot run a valid I-Regexp"));
    }
    def ok as list of json.Value init query(
        json.decode(json.encode([strings.repeat("a", 1000)])),
        "$[?match(@, 'a" + LBRACE + "1000" + RBRACE + "')]");
    testing.assertEqual(len($ok), 1);
}

func testTranslateRefusesWhatIRegexpLacks() {
    for (def bad in [
        "\\d",
        "\\w",
        "(?:a)",
        "a**",
        "*a",
        "a" + LBRACE,
        "a" + LBRACE + "x" + RBRACE,
        "[a",
        "[]",
        "[^]",
        "(a",
        "a)",
        "]",
        RBRACE,
        "\\p" + LBRACE + "Foo" + RBRACE,
        "\\p",
        "a*?",
        "[[a]]"
    ]) {
        testing.assertEqual(re2($bad), "!");
    }
}

func testSignatures() {
    testing.assertEqual(signature("length"), [TVALUE, TVALUE]);
    testing.assertEqual(signature("count"), [TVALUE, TNODES]);
    testing.assertEqual(signature("search"), [TLOGICAL, TVALUE, TVALUE]);
    testing.assertEqual(signature("nope"), []);
}

func testFunctions() {
    def s as Val init Val{present: true, value: jsonString("héllo")};
    testing.assertEqual(json.asInt(fnLength($s).value), 5);
    testing.assertEqual(
        json.asInt(fnLength(Val{present: true, value: json.decode('{"a":1,"b":2}')}).value),
        2);
    testing.assertEqual(fnLength(Val{present: true, value: json.decode("1")}).present, false);
    testing.assertEqual(fnLength(nothing()).present, false);
    def re as Rx init translate("l+");
    testing.assertEqual(fnMatch($s, $re, false), true);
    testing.assertEqual(fnMatch($s, $re, true), false);
    testing.assertEqual(fnMatch($s, translate("h.llo"), true), true);
    testing.assertEqual(fnMatch($s, translate("\\d"), false), false);
    testing.assertEqual(fnMatch(Val{present: true, value: jsonInt(1)}, $re, false), false);
}
