# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonpath - white-box tests for the core topic, and the compliance suite
# runner. Spliced into jsonpath_test.j via include.

def const CTS_FILE as string init "testdata/cts/cts.json";

# jvc runs the overlays from a copy of src/ alone, where testdata/ is not
# there; the suite then passes without running. testCtsIsThereInTheRepository
# keeps a repository run from silently skipping it.
def hasCts as bool init fs.isFile(CTS_FILE);

/**
 * Mark a call that should have thrown. The error reaches the test's own
 * `catch`, whose assertions on kind and message then fail.
 *
 * @param what {string} what got through
 * @throws {Error} always, with `kind` `"missed"`
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * Whether one compliance case passes.
 *
 * @param t {json.Value} the case
 * @return {string} "" when it passes, else what went wrong
 */
func runCase(t as json.Value) {
    def selector as string init json.asString($t, "/selector");
    if (json.has($t, "/invalid_selector")) {
        if (isValid($selector)) {
            return "accepted an invalid selector";
        }
        return "";
    }
    def got as list of Match init [];
    try {
        $got = find(json.get($t, "/document"), compile($selector));
    } catch (e) {
        return "rejected: " + $e.message;
    }
    def values as list of json.Value init [];
    def norms as list of string init [];
    for (def m in $got) {
        $values[] = $m.value;
        $norms[] = $m.path;
        if (json.get(json.get($t, "/document"), $m.pointer) != $m.value) {
            return "pointer " + $m.pointer + " does not lead to its value";
        }
    }
    def gotValues as json.Value init json.list($values);
    def gotPaths as json.Value init json.list($norms);
    if (json.has($t, "/result")) {
        if ($gotValues != json.get($t, "/result")) {
            return "got " + json.encode($gotValues);
        }
        if (json.has($t, "/result_paths") and $gotPaths != json.get($t, "/result_paths")) {
            return "got paths " + json.encode($gotPaths);
        }
        return "";
    }
    def i as int init 0;
    while ($i < json.length($t, "/results")) {
        def at as string init "/" + convert.toString($i);
        if ($gotValues == json.get($t, "/results" + $at)) {
            if (not json.has($t, "/results_paths") or
                $gotPaths == json.get($t, "/results_paths" + $at)) {
                return "";
            }
        }
        $i = $i + 1;
    }
    return "got " + json.encode($gotValues) + " at " + json.encode($gotPaths);
}

/**
 * Run the compliance cases whose tags or name match.
 *
 * @param pick {string} a regex over `name`; "" for all
 * @return {list of string} one line per failed case
 */
func runCts(pick as string) {
    def failed as list of string init [];
    if (not $hasCts) {
        return $failed;
    }
    def tests as json.Value init json.get(json.decode(fs.readString(CTS_FILE)), "/tests");
    def i as int init 0;
    while ($i < json.length($tests)) {
        def t as json.Value init json.get($tests, "/" + convert.toString($i));
        def name as string init json.asString($t, "/name");
        if ($pick == "" or regex.matches($pick, $name)) {
            def why as string init runCase($t);
            if ($why != "") {
                $failed[] = $name + " [" + json.asString($t, "/selector") + "]: " + $why;
            }
        }
        $i = $i + 1;
    }
    return $failed;
}

func testCtsIsThereInTheRepository() {
    if (fs.isFile("src/jsonpath.j")) {
        testing.assertTrue($hasCts);
    }
}

func testComplianceSuite() {
    testing.assertEqual(strings.join(runCts(""), "\n"), "");
}

func testPointerTokens() {
    testing.assertEqual(pointerToken("a/b~c"), "a~1b~0c");
}

func testNormalNames() {
    testing.assertEqual(normalName("it's"), "it\\'s");
    testing.assertEqual(normalName("a\\b"), "a\\\\b");
    def controls as string init "\n\t" + convert.fromCodepoint(8) + convert.fromCodepoint(12) + "\r";
    testing.assertEqual(normalName($controls), "\\n\\t\\b\\f\\r");
    testing.assertEqual(
        normalName(convert.fromCodepoint(1) + convert.fromCodepoint(31)),
        "\\u0001\\u001f");
    testing.assertEqual(normalName("ü€"), "ü€");
}

func testFailNamesTheDeck() {
    try {
        fail("boom");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
        testing.assertEqual($e.message, "jsonpath: boom");
    }
    testing.assertEqual(kindAt(json.decode('{"a":1}'), "/b/c"), "missing");
    testing.assertEqual(json.asInt(jsonInt(42)), 42);
    testing.assertEqual(json.asString(jsonString("x\"y")), "x\"y");
}
