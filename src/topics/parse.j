# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# jsonpath - the parser: RFC 9535's grammar (section 2 and appendix A) and the
# well-typedness rules of section 2.4.3. Spliced into jsonpath.j via include.

/**
 * The parser's state. Every parse function takes it and returns it, with
 * `last` set to the index of the node it built.
 *
 * @field source {string} the query
 * @field chars {list of string} its code points
 * @field pos {int} the next code point to read
 * @field nodes {list of Node} the nodes built so far
 * @field last {int} the node the last parse function built
 * @field num {int} the integer `parseInt` read
 * @field depth {int} how deep parentheses, filters and calls nest here
 */
def struct Parser {
    source as string,
    chars as list of string,
    pos as int,
    nodes as list of Node,
    last as int,
    num as int,
    depth as int
};

/**
 * Parse a query, or say why it is not one.
 *
 * @param source {string} the query
 * @return {Path} the parsed query
 * @throws {Error} kind `"jsonpath"` naming the position of the first error
 */
func parse(source as string) {
    def p as Parser init Parser{
        source: $source,
        chars: strings.chars($source),
        pos: 0,
        nodes: [],
        last: -1,
        num: 0,
        depth: 0
    };
    if (peek($p) != "$") {
        failAt($p, "a query starts with $");
    }
    $p = parseQuery($p);
    if ($p.pos < len($p.chars)) {
        failAt($p, "unexpected " + describeChar(peek($p)));
    }
    # The root query's `start` is 1 when a filter holds a `$` query.
    def i as int init 0;
    while ($i < len($p.nodes)) {
        def kind as int init $p.nodes[$i].kind;
        if ($kind == KQUERY and $p.nodes[$i].text == "$" and $i != $p.last) {
            $p.nodes[$p.last].start = 1;
        }
        if ($kind != KSEGMENT and $kind != KSLICE and $kind != KNAME and $kind != KWILD and
            $kind != KINDEX and $kind != KFILTER) {
            $p.nodes[$i].step = staticCost($p.nodes, $i);
        }
        $i = $i + 1;
    }
    return Path{source: $source, nodes: $p.nodes, root: $p.last, maxNodes: MAX_NODES};
}

/**
 * The static work of an expression node that needs no node lists: built
 * from literals, singular queries, `$` queries (run once by `run`),
 * comparisons, logic, `length`, `count` / `value` of a `$` query, and
 * `match` / `search` with a literal pattern. The evaluator runs such an
 * expression through `holds` / `simpleValue`, without passing `Work` in
 * place. Kids have lower indexes, so their cost is already in their `step`.
 *
 * @param nodes {list of Node} the nodes
 * @param i {int} the node
 * @return {int} the singular query steps it may take; -1 when not simple
 */
func staticCost(nodes as list of Node, i as int) {
    def kind as int init $nodes[$i].kind;
    def kids as list of int init $nodes[$i].kids;
    if ($kind == KLITERAL) {
        return 0;
    }
    if ($kind == KQUERY) {
        if ($nodes[$i].text == "$") {
            return 0;
        }
        if ($nodes[$i].num == 1) {
            return len($kids);
        }
        return -1;
    }
    def name as string init $nodes[$i].text;
    if ($kind == KFUNC and ($name == "count" or $name == "value")) {
        if ($nodes[$kids[0]].kind == KQUERY and $nodes[$kids[0]].text == "$") {
            return 0;
        }
        return -1;
    }
    if ($kind == KFUNC and $name != "length" and $nodes[$i].start == 0) {
        return -1;
    }
    if ($kind == KFUNC and $name != "length") {
        return $nodes[$kids[0]].step;
    }
    if ($kind != KFUNC and $kind != KCMP and $kind != KOR and $kind != KAND and
        $kind != KNOT and $kind != KTEST) {
        return -1;
    }
    def sum as int init 0;
    for (def k in $kids) {
        if ($nodes[$k].step < 0) {
            return -1;
        }
        $sum = $sum + $nodes[$k].step;
    }
    return $sum;
}

/**
 * Raise a parse error at the current position.
 *
 * @param p {Parser} the parser
 * @param message {string} what is wrong
 * @throws {Error} always, with `kind` `"jsonpath"`
 */
func failAt(p as Parser, message as string) {
    fail($message + " at position " + convert.toString($p.pos) + " of " + excerpt($p));
}

/**
 * The query for an error message: whole when it is short, else the
 * `EXCERPT` code points around the error position, with `...` for the cut.
 * The query may be untrusted and long; the message stays bounded.
 *
 * @param p {Parser} the parser
 * @return {string} the quoted query or excerpt
 */
func excerpt(p as Parser) {
    def n as int init len($p.chars);
    if ($n <= EXCERPT) {
        return quoted($p.source);
    }
    def start as int init $p.pos - EXCERPT // 2;
    if ($start > $n - EXCERPT) {
        $start = $n - EXCERPT;
    }
    if ($start < 0) {
        $start = 0;
    }
    def text as string init quoted(strings.join(
        lists.slice($p.chars, $start, $start + EXCERPT),
        ""));
    if ($start > 0) {
        $text = "..." + $text;
    }
    if ($start + EXCERPT < $n) {
        $text = $text + "...";
    }
    return $text;
}

/**
 * A character for an error message.
 *
 * @param ch {string} the character, or "" at the end
 * @return {string} the character quoted, or `end of query`
 */
func describeChar(ch as string) {
    if ($ch == "") {
        return "end of query";
    }
    return quoted($ch);
}

/**
 * The next code point.
 *
 * @param p {Parser} the parser
 * @return {string} the code point; "" at the end
 */
func peek(p as Parser) {
    if ($p.pos < len($p.chars)) {
        return $p.chars[$p.pos];
    }
    return "";
}

/**
 * A code point further on.
 *
 * @param p {Parser} the parser
 * @param k {int} how far after the next one
 * @return {string} the code point; "" past the end
 */
func peekAt(p as Parser, k as int) {
    if ($p.pos + $k < len($p.chars)) {
        return $p.chars[$p.pos + $k];
    }
    return "";
}

/**
 * Skip blank space: space, tab, line feed, carriage return.
 *
 * @param p {Parser} the parser
 * @return {Parser} the parser past the blanks
 */
func skipS(p as Parser) {
    while ($p.pos < len($p.chars) and isBlank($p.chars[$p.pos])) {
        $p.pos = $p.pos + 1;
    }
    return $p;
}

/**
 * Whether a code point is RFC 9535 blank space.
 *
 * @param ch {string} the code point
 * @return {bool} true for space, tab, LF and CR
 */
func isBlank(ch as string) {
    return $ch == " " or $ch == "\t" or $ch == "\n" or $ch == "\r";
}

/**
 * Whether a code point is an ASCII digit.
 *
 * @param ch {string} the code point
 * @return {bool} true for 0 to 9
 */
func isDigit(ch as string) {
    return $ch != "" and $ch >= "0" and $ch <= "9";
}

/**
 * Whether a code point can start a member-name shorthand.
 *
 * @param ch {string} the code point
 * @return {bool} true for ASCII letters, `_` and anything from U+0080
 */
func isNameFirst(ch as string) {
    if ($ch == "") {
        return false;
    }
    def cp as int init convert.toCodepoint($ch);
    return ($ch >= "a" and $ch <= "z") or ($ch >= "A" and $ch <= "Z") or $ch == "_" or $cp >= 128;
}

/**
 * Whether a code point can follow in a member-name shorthand.
 *
 * @param ch {string} the code point
 * @return {bool} true for name-first characters and digits
 */
func isNameChar(ch as string) {
    return isNameFirst($ch) or isDigit($ch);
}

/**
 * A fresh node.
 *
 * @param kind {int} its kind
 * @return {Node} the node, everything else empty
 */
func newNode(kind as int) {
    def n as Node;
    $n.kind = $kind;
    $n.lit = json.decode("null");
    return $n;
}

/**
 * Add a node and make it `last`.
 *
 * @param p {Parser} the parser
 * @param n {Node} the node
 * @return {Parser} the parser holding it
 */
func emit(p as Parser, n as Node) {
    $p.nodes[] = $n;
    $p.last = len($p.nodes) - 1;
    return $p;
}

/**
 * Parse `$` or `@` and the segments after it.
 *
 * @param p {Parser} the parser, at the identifier
 * @return {Parser} the parser; `last` is the query node
 */
func parseQuery(p as Parser) {
    def q as Node init newNode(KQUERY);
    $q.text = peek($p);
    $p.pos = $p.pos + 1;
    def singular as bool init true;
    while (true) {
        def save as int init $p.pos;
        $p = skipS($p);
        def ch as string init peek($p);
        if ($ch == "[") {
            $p = parseBracket($p, 0);
        } elseif ($ch == "." and peekAt($p, 1) == ".") {
            $p.pos = $p.pos + 2;
            $p = parseDotted($p, 1);
        } elseif ($ch == ".") {
            $p.pos = $p.pos + 1;
            $p = parseDotted($p, 0);
        } else {
            $p.pos = $save;
            break;
        }
        $q.kids[] = $p.last;
        if (not isSingularSegment($p.nodes, $p.last)) {
            $singular = false;
        }
    }
    if ($singular) {
        $q.num = 1;
    }
    $p = emit($p, $q);
    return $p;
}

/**
 * Whether a segment keeps a query singular: a child segment with one name or
 * index selector.
 *
 * @param nodes {list of Node} the nodes
 * @param seg {int} the segment
 * @return {bool} true when it selects at most one node
 */
func isSingularSegment(nodes as list of Node, seg as int) {
    if ($nodes[$seg].num == 1 or len($nodes[$seg].kids) != 1) {
        return false;
    }
    def k as int init $nodes[$nodes[$seg].kids[0]].kind;
    return $k == KNAME or $k == KINDEX;
}

/**
 * Parse what follows `.` or `..`: a wildcard, a member name, or (after `..`)
 * a bracketed selection.
 *
 * @param p {Parser} the parser, after the dots
 * @param descendant {int} 1 after `..`
 * @return {Parser} the parser; `last` is the segment
 */
func parseDotted(p as Parser, descendant as int) {
    def ch as string init peek($p);
    if ($ch == "[" and $descendant == 1) {
        $p = parseBracket($p, 1);
        return $p;
    }
    def sel as Node init newNode(KWILD);
    if ($ch == "*") {
        $p.pos = $p.pos + 1;
    } elseif (isNameFirst($ch)) {
        $sel.kind = KNAME;
        def start as int init $p.pos;
        while (isNameChar(peek($p))) {
            $p.pos = $p.pos + 1;
        }
        $sel.text = strings.join(lists.slice($p.chars, $start, $p.pos), "");
    } else {
        failAt($p, "expected a member name or * after the dot, found " + describeChar($ch));
    }
    $p = emit($p, $sel);
    def seg as Node init newNode(KSEGMENT);
    $seg.num = $descendant;
    $seg.kids = [$p.last];
    $p = emit($p, $seg);
    return $p;
}

/**
 * Parse a bracketed selection, `[sel, sel, ...]`.
 *
 * @param p {Parser} the parser, at `[`
 * @param descendant {int} 1 after `..`
 * @return {Parser} the parser; `last` is the segment
 */
func parseBracket(p as Parser, descendant as int) {
    $p.pos = $p.pos + 1;
    def seg as Node init newNode(KSEGMENT);
    $seg.num = $descendant;
    while (true) {
        $p = skipS($p);
        $p = parseSelector($p);
        $seg.kids[] = $p.last;
        $p = skipS($p);
        def ch as string init peek($p);
        if ($ch == ",") {
            $p.pos = $p.pos + 1;
        } elseif ($ch == "]") {
            $p.pos = $p.pos + 1;
            break;
        } else {
            failAt($p, "expected , or ] in a selection, found " + describeChar($ch));
        }
    }
    $p = emit($p, $seg);
    return $p;
}

/**
 * Parse one selector of a bracketed selection.
 *
 * @param p {Parser} the parser, at the selector
 * @return {Parser} the parser; `last` is the selector
 */
func parseSelector(p as Parser) {
    def ch as string init peek($p);
    if ($ch == "'" or $ch == "\"") {
        $p = parseString($p);
        def name as Node init newNode(KNAME);
        $name.text = json.asString($p.nodes[$p.last].lit);
        $p = emit($p, $name);
        return $p;
    }
    if ($ch == "*") {
        $p.pos = $p.pos + 1;
        $p = emit($p, newNode(KWILD));
        return $p;
    }
    if ($ch == "?") {
        $p.pos = $p.pos + 1;
        $p = enter($p);
        $p = skipS($p);
        $p = parseOr($p, false);
        $p.depth = $p.depth - 1;
        def filter as Node init newNode(KFILTER);
        $filter.kids = [$p.last];
        $p = emit($p, $filter);
        return $p;
    }
    def sel as Node init newNode(KINDEX);
    if ($ch == "-" or isDigit($ch)) {
        $p = parseInt($p);
        $sel.start = $p.num;
        $sel.hasStart = true;
    }
    def save as int init $p.pos;
    $p = skipS($p);
    if (peek($p) != ":") {
        $p.pos = $save;
        if (not $sel.hasStart) {
            failAt($p, "expected a selector, found " + describeChar($ch));
        }
        $sel.num = $sel.start;
        $p = emit($p, $sel);
        return $p;
    }
    $sel.kind = KSLICE;
    $sel.step = 1;
    $p.pos = $p.pos + 1;
    $p = skipS($p);
    if (peek($p) == "-" or isDigit(peek($p))) {
        $p = parseInt($p);
        $sel.stop = $p.num;
        $sel.hasStop = true;
        $p = skipS($p);
    }
    if (peek($p) == ":") {
        $p.pos = $p.pos + 1;
        $p = skipS($p);
        if (peek($p) == "-" or isDigit(peek($p))) {
            $p = parseInt($p);
            $sel.step = $p.num;
        }
    }
    $p = emit($p, $sel);
    return $p;
}

/**
 * Parse an integer: `0`, or an optional `-` and digits without a leading
 * zero, within plus or minus 2^53 - 1.
 *
 * @param p {Parser} the parser, at the integer
 * @return {Parser} the parser; `num` is the integer
 */
func parseInt(p as Parser) {
    def start as int init $p.pos;
    def negative as bool init peek($p) == "-";
    if ($negative) {
        $p.pos = $p.pos + 1;
    }
    def first as int init $p.pos;
    while (isDigit(peek($p))) {
        $p.pos = $p.pos + 1;
    }
    def digits as string init strings.join(lists.slice($p.chars, $first, $p.pos), "");
    if ($digits == "") {
        failAt($p, "expected digits");
    }
    if (len($digits) > 1 and strings.startsWith($digits, "0")) {
        $p.pos = $start;
        failAt($p, "an integer has no leading zero");
    }
    if ($negative and $digits == "0") {
        $p.pos = $start;
        failAt($p, "-0 is not an integer");
    }
    if (len($digits) > 16 or convert.toInt($digits) > MAX_INDEX) {
        $p.pos = $start;
        failAt($p, "an integer is at most 2^53 - 1 in size");
    }
    $p.num = convert.toInt($digits);
    if ($negative) {
        $p.num = 0 - $p.num;
    }
    return $p;
}

/**
 * Parse a string literal in `'...'` or `"..."`.
 *
 * @param p {Parser} the parser, at the opening quote
 * @return {Parser} the parser; `last` is a literal node holding the string
 */
func parseString(p as Parser) {
    def quote as string init peek($p);
    $p.pos = $p.pos + 1;
    def out as list of string init [];
    while (true) {
        def ch as string init peek($p);
        if ($ch == "") {
            failAt($p, "unterminated string");
        }
        $p.pos = $p.pos + 1;
        if ($ch == $quote) {
            break;
        }
        if ($ch == "\\") {
            $p = parseEscape($p, $quote);
            $out[] = convert.fromCodepoint($p.num);
        } elseif (convert.toCodepoint($ch) < 32) {
            $p.pos = $p.pos - 1;
            failAt($p, "a control character must be escaped in a string");
        } else {
            $out[] = $ch;
        }
    }
    def lit as Node init newNode(KLITERAL);
    $lit.lit = jsonString(strings.join($out, ""));
    $p = emit($p, $lit);
    return $p;
}

/**
 * Parse the escape after a backslash in a string.
 *
 * @param p {Parser} the parser, after the backslash
 * @param quote {string} the string's quote, the one quote that may be escaped
 * @return {Parser} the parser; `num` is the code point
 */
func parseEscape(p as Parser, quote as string) {
    def ch as string init peek($p);
    $p.pos = $p.pos + 1;
    def simple as map of string to int init {
        "b": 8,
        "f": 12,
        "n": 10,
        "r": 13,
        "t": 9,
        "/": 47,
        "\\": 92
    };
    if (maps.has($simple, $ch)) {
        $p.num = $simple[$ch];
        return $p;
    }
    if ($ch == $quote) {
        $p.num = convert.toCodepoint($ch);
        return $p;
    }
    if ($ch != "u") {
        $p.pos = $p.pos - 1;
        failAt($p, "unknown escape \\" + $ch);
    }
    $p = parseHex4($p);
    def cp as int init $p.num;
    if ($cp >= 0xDC00 and $cp <= 0xDFFF) {
        failAt($p, "a low surrogate without a high one");
    }
    if ($cp >= 0xD800 and $cp <= 0xDBFF) {
        if (peek($p) != "\\" or peekAt($p, 1) != "u") {
            failAt($p, "a high surrogate needs a low one");
        }
        $p.pos = $p.pos + 2;
        $p = parseHex4($p);
        if ($p.num < 0xDC00 or $p.num > 0xDFFF) {
            failAt($p, "a high surrogate needs a low one");
        }
        $p.num = 0x10000 + (($cp - 0xD800) << 10) + ($p.num - 0xDC00);
    } else {
        $p.num = $cp;
    }
    return $p;
}

/**
 * Parse four hex digits.
 *
 * @param p {Parser} the parser, at the digits
 * @return {Parser} the parser; `num` is their value
 */
func parseHex4(p as Parser) {
    def end as int init $p.pos + 4;
    if ($end > len($p.chars)) {
        $end = len($p.chars);
    }
    def text as string init strings.join(lists.slice($p.chars, $p.pos, $end), "");
    if (not regex.matches('^[0-9A-Fa-f]{4}$', $text)) {
        failAt($p, "\\u needs four hex digits");
    }
    $p.num = convert.toInt($text, 16);
    $p.pos = $p.pos + 4;
    return $p;
}

/**
 * Parse `a || b || ...`.
 *
 * @param p {Parser} the parser
 * @param allowLiteral {bool} a lone literal may stand here (a function argument)
 * @return {Parser} the parser; `last` is the expression
 */
func parseOr(p as Parser, allowLiteral as bool) {
    $p = parseAnd($p, $allowLiteral);
    def n as Node init newNode(KOR);
    $n.kids = [$p.last];
    while (true) {
        def save as int init $p.pos;
        $p = skipS($p);
        if (peek($p) != "|" or peekAt($p, 1) != "|") {
            $p.pos = $save;
            break;
        }
        $p.pos = $p.pos + 2;
        $p = skipS($p);
        $p = parseAnd($p, false);
        $n.kids[] = $p.last;
    }
    if (len($n.kids) == 1) {
        $p.last = $n.kids[0];
        return $p;
    }
    checkOperands($p, $n.kids);
    $p = emit($p, $n);
    return $p;
}

/**
 * Parse `a && b && ...`.
 *
 * @param p {Parser} the parser
 * @param allowLiteral {bool} a lone literal may stand here
 * @return {Parser} the parser; `last` is the expression
 */
func parseAnd(p as Parser, allowLiteral as bool) {
    $p = parseBasic($p, $allowLiteral);
    def n as Node init newNode(KAND);
    $n.kids = [$p.last];
    while (true) {
        def save as int init $p.pos;
        $p = skipS($p);
        if (peek($p) != "&" or peekAt($p, 1) != "&") {
            $p.pos = $save;
            break;
        }
        $p.pos = $p.pos + 2;
        $p = skipS($p);
        $p = parseBasic($p, false);
        $n.kids[] = $p.last;
    }
    if (len($n.kids) == 1) {
        $p.last = $n.kids[0];
        return $p;
    }
    checkOperands($p, $n.kids);
    $p = emit($p, $n);
    return $p;
}

/**
 * Refuse an operand of `&&` or `||` that is no test: a literal, or a
 * function returning a value.
 *
 * @param p {Parser} the parser
 * @param kids {list of int} the operands
 * @throws {Error} kind `"jsonpath"` for an operand that is no test
 */
func checkOperands(p as Parser, kids as list of int) {
    for (def k in $kids) {
        checkTest($p, $k);
    }
}

/**
 * Parse a basic expression: a negation, parentheses, a comparison or a test.
 *
 * @param p {Parser} the parser
 * @param allowLiteral {bool} a function argument: a lone literal, or a
 *   function returning a value, may stand here; `fitsParameter` checks it
 * @return {Parser} the parser; `last` is the expression
 */
func parseBasic(p as Parser, allowLiteral as bool) {
    def ch as string init peek($p);
    if ($ch == "!") {
        $p.pos = $p.pos + 1;
        $p = skipS($p);
        if (peek($p) == "(") {
            $p = parseParen($p);
        } else {
            $p = parsePrimary($p);
            checkTest($p, $p.last);
        }
        def neg as Node init newNode(KNOT);
        $neg.kids = [$p.last];
        $p = emit($p, $neg);
        return $p;
    }
    if ($ch == "(") {
        $p = parseParen($p);
        return $p;
    }
    $p = parsePrimary($p);
    def left as int init $p.last;
    def save as int init $p.pos;
    $p = skipS($p);
    def op as string init comparisonOp($p);
    if ($op == "") {
        $p.pos = $save;
        if ($p.nodes[$left].kind == KLITERAL) {
            if (not $allowLiteral) {
                failAt($p, "a literal is not a test; compare it");
            }
            $p.last = $left;
            return $p;
        }
        if (not $allowLiteral) {
            checkTest($p, $left);
        }
        $p.last = $left;
        return $p;
    }
    $p.pos = $p.pos + len($op);
    $p = skipS($p);
    checkComparable($p, $left);
    $p = parsePrimary($p);
    def right as int init $p.last;
    checkComparable($p, $right);
    def cmp as Node init newNode(KCMP);
    $cmp.text = $op;
    $cmp.kids = [$left, $right];
    $p = emit($p, $cmp);
    return $p;
}

/**
 * Parse `( logical-expr )`.
 *
 * @param p {Parser} the parser, at `(`
 * @return {Parser} the parser; `last` is the expression
 */
func parseParen(p as Parser) {
    $p.pos = $p.pos + 1;
    $p = enter($p);
    $p = skipS($p);
    $p = parseOr($p, false);
    $p = skipS($p);
    if (peek($p) != ")") {
        failAt($p, "expected ), found " + describeChar(peek($p)));
    }
    $p.pos = $p.pos + 1;
    $p.depth = $p.depth - 1;
    def k as int init $p.nodes[$p.last].kind;
    if ($k != KQUERY and $k != KFUNC) {
        return $p;
    }
    def test as Node init newNode(KTEST);
    $test.kids = [$p.last];
    $p = emit($p, $test);
    return $p;
}

/**
 * The comparison operator at the parser's position.
 *
 * @param p {Parser} the parser
 * @return {string} the operator; "" for none
 */
func comparisonOp(p as Parser) {
    def two as string init peek($p) + peekAt($p, 1);
    if ($two == "==" or $two == "!=" or $two == "<=" or $two == ">=") {
        return $two;
    }
    if (peek($p) == "<" or peek($p) == ">") {
        return peek($p);
    }
    return "";
}

/**
 * Parse a literal, a query or a function call.
 *
 * @param p {Parser} the parser
 * @return {Parser} the parser; `last` is the node
 */
func parsePrimary(p as Parser) {
    def ch as string init peek($p);
    if ($ch == "$" or $ch == "@") {
        $p = parseQuery($p);
        return $p;
    }
    if ($ch == "'" or $ch == "\"") {
        $p = parseString($p);
        return $p;
    }
    if ($ch == "-" or isDigit($ch)) {
        $p = parseNumber($p);
        return $p;
    }
    if ($ch >= "a" and $ch <= "z") {
        def start as int init $p.pos;
        while (peek($p) != "" and
            ((peek($p) >= "a" and peek($p) <= "z") or isDigit(peek($p)) or peek($p) == "_")) {
            $p.pos = $p.pos + 1;
        }
        def word as string init strings.join(lists.slice($p.chars, $start, $p.pos), "");
        if (peek($p) == "(") {
            $p = parseFunction($p, $word);
            return $p;
        }
        def literals as map of string to string init {
            "true": "true",
            "false": "false",
            "null": "null"
        };
        if (maps.has($literals, $word)) {
            def lit as Node init newNode(KLITERAL);
            $lit.lit = json.decode($word);
            $p = emit($p, $lit);
            return $p;
        }
        $p.pos = $start;
        failAt($p, "unknown word " + quoted(cut($word)));
    }
    failAt($p, "expected a query, a literal or a function, found " + describeChar($ch));
}

/**
 * Parse a number literal: an integer or `-0`, then an optional fraction and
 * exponent.
 *
 * @param p {Parser} the parser, at the number
 * @return {Parser} the parser; `last` is a literal node
 */
func parseNumber(p as Parser) {
    def start as int init $p.pos;
    while (peek($p) != "" and regex.matches("^[-+0-9.eE]$", peek($p))) {
        $p.pos = $p.pos + 1;
    }
    def text as string init strings.join(lists.slice($p.chars, $start, $p.pos), "");
    if (not regex.matches("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][-+]?[0-9]+)?$", $text)) {
        $p.pos = $start;
        failAt($p, "malformed number " + quoted(cut($text)));
    }
    def lit as Node init newNode(KLITERAL);
    try {
        $lit.lit = json.decode($text);
    } catch (e) {
        $p.pos = $start;
        failAt($p, "number out of range " + quoted(cut($text)));
    }
    $p = emit($p, $lit);
    return $p;
}

/**
 * Parse a function call and check it against the function's signature.
 *
 * @param p {Parser} the parser, at `(`
 * @param name {string} the function's name
 * @return {Parser} the parser; `last` is the call
 */
func parseFunction(p as Parser, name as string) {
    def sig as list of int init signature($name);
    if (len($sig) == 0) {
        failAt($p, "unknown function " + cut($name) + "()");
    }
    $p.pos = $p.pos + 1;
    $p = enter($p);
    def call as Node init newNode(KFUNC);
    $call.text = $name;
    $call.num = $sig[0];
    $p = skipS($p);
    if (peek($p) == ")") {
        $p.pos = $p.pos + 1;
    } else {
        while (true) {
            $p = skipS($p);
            $p = parseOr($p, true);
            $call.kids[] = $p.last;
            $p = skipS($p);
            def ch as string init peek($p);
            if ($ch == ",") {
                $p.pos = $p.pos + 1;
            } elseif ($ch == ")") {
                $p.pos = $p.pos + 1;
                break;
            } else {
                failAt($p, "expected , or ) in " + $name + "(), found " + describeChar($ch));
            }
        }
    }
    $p.depth = $p.depth - 1;
    $call = precompile($p, $call);
    if (len($call.kids) != len($sig) - 1) {
        failAt($p, $name + "() takes " + convert.toString(len($sig) - 1) + " argument(s)");
    }
    def i as int init 0;
    while ($i < len($call.kids)) {
        if (not fitsParameter($p.nodes, $call.kids[$i], $sig[$i + 1])) {
            failAt(
                $p,
                "argument " + convert.toString($i + 1) + " of " + $name + "() has the wrong type");
        }
        $i = $i + 1;
    }
    $p = emit($p, $call);
    return $p;
}

/**
 * Whether an argument fits a parameter type (RFC 9535 section 2.4.3).
 *
 * @param nodes {list of Node} the nodes
 * @param arg {int} the argument
 * @param type {int} `TVALUE`, `TLOGICAL` or `TNODES`
 * @return {bool} true when it is well-typed
 */
func fitsParameter(nodes as list of Node, arg as int, type as int) {
    def n as Node init $nodes[$arg];
    if ($type == TVALUE) {
        return $n.kind == KLITERAL or ($n.kind == KQUERY and $n.num == 1) or
            ($n.kind == KFUNC and $n.num == TVALUE);
    }
    if ($type == TNODES) {
        return $n.kind == KQUERY or ($n.kind == KFUNC and $n.num == TNODES);
    }
    if ($n.kind == KFUNC) {
        return $n.num == TLOGICAL or $n.num == TNODES;
    }
    return $n.kind != KLITERAL;
}

/**
 * Refuse a test that is a function returning a value.
 *
 * @param p {Parser} the parser
 * @param idx {int} the node standing as a test
 * @throws {Error} kind `"jsonpath"` for a literal or a value function
 */
func checkTest(p as Parser, idx as int) {
    def n as Node init $p.nodes[$idx];
    if ($n.kind == KLITERAL) {
        failAt($p, "a literal is not a test");
    }
    if ($n.kind == KFUNC and $n.num == TVALUE) {
        failAt($p, $n.text + "() returns a value; compare it");
    }
}

/**
 * Refuse an operand of a comparison that is not comparable: a query that can
 * select more than one node, or a function that does not return a value.
 *
 * @param p {Parser} the parser
 * @param idx {int} the operand
 * @throws {Error} kind `"jsonpath"` when the operand is not comparable
 */
func checkComparable(p as Parser, idx as int) {
    def n as Node init $p.nodes[$idx];
    if ($n.kind == KQUERY and $n.num != 1) {
        failAt($p, "only a singular query can be compared");
    }
    if ($n.kind == KFUNC and $n.num != TVALUE) {
        failAt($p, $n.text + "() returns no value to compare");
    }
}

/**
 * Go one level deeper into parentheses, a filter or a call. A query nested
 * past `MAX_NESTING` is refused before it costs time or reaches Jennifer's
 * call-depth limit.
 *
 * @param p {Parser} the parser
 * @return {Parser} the parser one level deeper
 */
func enter(p as Parser) {
    $p.depth = $p.depth + 1;
    if ($p.depth > MAX_NESTING) {
        failAt($p, "nested deeper than " + convert.toString(MAX_NESTING) + " levels");
    }
    return $p;
}

/**
 * Translate the pattern of `match` or `search` once when it is a string
 * literal, instead of for every node the filter tests, and refuse it when
 * RE2 cannot compile it.
 *
 * @param p {Parser} the parser
 * @param call {Node} the call
 * @return {Node} the call, with `start` and `lit` set for a literal pattern
 * @throws {Error} kind `"jsonpath"` when the pattern is valid I-Regexp that
 *   RE2 cannot compile (a repeat over 1000, a program over RE2's size limits)
 */
func precompile(p as Parser, call as Node) {
    if (($call.text != "match" and $call.text != "search") or len($call.kids) != 2) {
        return $call;
    }
    def arg as Node init $p.nodes[$call.kids[1]];
    if ($arg.kind != KLITERAL or json.typeOf($arg.lit) != "string") {
        return $call;
    }
    def rx as Rx init translate(json.asString($arg.lit));
    $call.start = 2;
    if (not $rx.ok) {
        return $call;
    }
    def why as string init "";
    try {
        regex.matches("^(?:" + $rx.re + ")$", "");
    } catch (e) {
        $why = $e.message;
    }
    if ($why != "") {
        failAt($p, "RE2 cannot run a valid I-Regexp: " + $why);
    }
    $call.start = 1;
    $call.lit = jsonString($rx.re);
    return $call;
}

/**
 * Quote text for an error message: JSON string syntax, but `<`, `>` and `&`
 * as they are (`json.encode` writes them as `\u003c`, `\u003e`, `\u0026`).
 *
 * @param text {string} the text
 * @return {string} the quoted text
 */
func quoted(text as string) {
    def q as string init json.encode($text);
    $q = strings.replace($q, "\\u003c", "<");
    $q = strings.replace($q, "\\u003e", ">");
    return strings.replace($q, "\\u0026", "&");
}

/**
 * Cut text for an error message to `EXCERPT` code points.
 *
 * @param text {string} the text, possibly long
 * @return {string} the text, with `...` after it when cut
 */
func cut(text as string) {
    if (len($text) <= EXCERPT) {
        return $text;
    }
    return strings.substring($text, 0, EXCERPT) + "...";
}
