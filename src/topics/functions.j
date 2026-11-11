# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# jsonpath - the function extensions of RFC 9535 section 2.4 (length, count,
# match, search, value) and the I-Regexp (RFC 9485) translation onto RE2.
# Spliced into jsonpath.j via include.

/**
 * A value in a filter, or Nothing (RFC 9535 section 2.4.1).
 *
 * @field present {bool} false for Nothing
 * @field value {json.Value} the value, when present
 */
def struct Val {
    present as bool,
    value as json.Value
};

/**
 * A translated regular expression, or part of one.
 *
 * @field ok {bool} whether the pattern was valid I-Regexp
 * @field re {string} the RE2 pattern
 * @field next {int} for a part: the position after it in the pattern
 * @field lit {string} for a class item: the character it stands for; ""
 *   for a category
 */
def struct Rx {
    ok as bool,
    re as string,
    next as int,
    lit as string
};

/**
 * A function's signature.
 *
 * @param name {string} the function's name
 * @return {list of int} the result type, then the parameter types; empty for
 *   an unknown function
 */
func signature(name as string) {
    if ($name == "length") {
        return [TVALUE, TVALUE];
    } elseif ($name == "count" or $name == "value") {
        return [TVALUE, TNODES];
    } elseif ($name == "match" or $name == "search") {
        return [TLOGICAL, TVALUE, TVALUE];
    }
    return [];
}

/**
 * Nothing.
 *
 * @return {Val} the absent value
 */
func nothing() {
    return Val{present: false, value: json.decode("null")};
}

/**
 * `length()`: the code points of a string, the elements of an array, the
 * members of an object; Nothing for anything else.
 *
 * @param v {Val} the argument
 * @return {Val} the length, or Nothing
 */
func fnLength(v as Val) {
    if (not $v.present) {
        return nothing();
    }
    def kind as string init json.typeOf($v.value);
    if ($kind == "string") {
        return Val{present: true, value: jsonInt(len(json.asString($v.value)))};
    }
    if ($kind == "list" or $kind == "map") {
        return Val{present: true, value: jsonInt(json.length($v.value))};
    }
    return nothing();
}

/**
 * `match()` and `search()`: whether a string matches a translated I-Regexp,
 * as a whole or anywhere. A non-string or an invalid pattern gives false.
 *
 * @param subject {Val} the string
 * @param rx {Rx} the pattern, from `translate`
 * @param whole {bool} true for `match`, false for `search`
 * @return {bool} the result
 * @throws {Error} kind `"jsonpath"` when RE2 cannot compile the pattern
 */
func fnMatch(subject as Val, rx as Rx, whole as bool) {
    if (not $rx.ok) {
        return false;
    }
    return matchRe2($subject, $rx.re, $whole);
}

/**
 * Match a string against a translated pattern.
 *
 * @param subject {Val} the string
 * @param re {string} the RE2 pattern
 * @param whole {bool} match the whole string
 * @return {bool} the result; false for a non-string
 * @throws {Error} kind `"jsonpath"` when RE2 cannot compile the pattern: a
 *   valid I-Regexp can repeat more than RE2's 1000, or exceed its size limits
 */
func matchRe2(subject as Val, re as string, whole as bool) {
    if (not $subject.present or json.typeOf($subject.value) != "string") {
        return false;
    }
    if ($whole) {
        $re = "^(?:" + $re + ")$";
    }
    try {
        return regex.matches($re, json.asString($subject.value));
    } catch (e) {
        fail("RE2 cannot run a valid I-Regexp: " + $e.message);
    }
}

/**
 * Translate an I-Regexp into RE2, in one pass. `.` becomes `[^\n\r]`, and
 * anything outside RFC 9485's grammar is refused. `^` and `$` stay anchors,
 * as the compliance suite expects.
 *
 * @param pattern {string} the I-Regexp
 * @return {Rx} the RE2 pattern, or not `ok`
 */
func translate(pattern as string) {
    def bad as Rx init Rx{ok: false, re: "", next: 0, lit: ""};
    def chars as list of string init strings.chars($pattern);
    def n as int init len($chars);
    def out as list of string init [];
    def i as int init 0;
    def depth as int init 0;
    def canQuantify as bool init false;
    while ($i < $n) {
        def c as string init $chars[$i];
        $i = $i + 1;
        if ($c == "(") {
            $out[] = "(";
            $depth = $depth + 1;
            $canQuantify = false;
        } elseif ($c == ")") {
            if ($depth == 0) {
                return $bad;
            }
            $depth = $depth - 1;
            $out[] = ")";
            $canQuantify = true;
        } elseif ($c == "|") {
            $out[] = "|";
            $canQuantify = false;
        } elseif ($c == "*" or $c == "+" or $c == "?") {
            if (not $canQuantify) {
                return $bad;
            }
            $out[] = $c;
            $canQuantify = false;
        } elseif ($c == LBRACE) {
            def close as int init rangeEnd($chars, $i);
            if (not $canQuantify or $close < 0) {
                return $bad;
            }
            $out[] = LBRACE + strings.join(lists.slice($chars, $i, $close), "") + RBRACE;
            $i = $close + 1;
            $canQuantify = false;
        } elseif ($c == ".") {
            $out[] = "[^\\n\\r]";
            $canQuantify = true;
        } elseif ($c == "[") {
            def cls as Rx init charClass($chars, $i);
            if (not $cls.ok) {
                return $bad;
            }
            $out[] = $cls.re;
            $i = $cls.next;
            $canQuantify = true;
        } elseif ($c == "\\") {
            def esc as Rx init escape($chars, $i);
            if (not $esc.ok) {
                return $bad;
            }
            $out[] = $esc.re;
            $i = $esc.next;
            $canQuantify = true;
        } elseif ($c == "]" or $c == RBRACE) {
            return $bad;
        } else {
            $out[] = $c;
            $canQuantify = true;
        }
    }
    if ($depth != 0) {
        return $bad;
    }
    return Rx{ok: true, re: strings.join($out, ""), next: $n, lit: ""};
}

/**
 * The end of a range quantifier `{n}`, `{n,}` or `{n,m}`; `{n,m}` needs
 * `n <= m`.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the position after `{`
 * @return {int} the position of `}`; -1 when the quantifier is malformed
 */
func rangeEnd(chars as list of string, from as int) {
    def i as int init $from;
    while ($i < len($chars) and isDigit($chars[$i])) {
        $i = $i + 1;
    }
    def low as string init strings.join(lists.slice($chars, $from, $i), "");
    if ($low == "" or $i >= len($chars)) {
        return -1;
    }
    if ($chars[$i] == ",") {
        $i = $i + 1;
        def first as int init $i;
        while ($i < len($chars) and isDigit($chars[$i])) {
            $i = $i + 1;
        }
        def high as string init strings.join(lists.slice($chars, $first, $i), "");
        if ($high != "" and digitsBefore($high, $low)) {
            return -1;
        }
    }
    if ($i >= len($chars) or $chars[$i] != RBRACE) {
        return -1;
    }
    return $i;
}

/**
 * Whether one decimal number is less than another, at any length.
 *
 * @param a {string} digits
 * @param b {string} digits
 * @return {bool} true when `a < b`
 */
func digitsBefore(a as string, b as string) {
    $a = regex.replace("^0+", $a, "");
    $b = regex.replace("^0+", $b, "");
    if (len($a) != len($b)) {
        return len($a) < len($b);
    }
    return $a < $b;
}

/**
 * The single-character escapes of I-Regexp, and what RE2 writes for them.
 *
 * @param c {string} the character after the backslash
 * @return {string} the RE2 escape; "" when `c` cannot be escaped
 */
func singleEscape(c as string) {
    if ($c == "n" or $c == "r" or $c == "t") {
        return "\\" + $c;
    }
    if (strings.contains("()*+-.?[\\]^|" + LBRACE + RBRACE, $c) and $c != "") {
        return "\\" + $c;
    }
    return "";
}

/**
 * Translate an escape: a single-character escape or a category `\p{..}` /
 * `\P{..}`. A category name is one or two letters, so the scan for `}` is
 * bounded.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the position after the backslash
 * @return {Rx} the RE2 text and the position after the escape, or not `ok`
 */
func escape(chars as list of string, from as int) {
    def bad as Rx init Rx{ok: false, re: "", next: 0, lit: ""};
    if ($from >= len($chars)) {
        return $bad;
    }
    def c as string init $chars[$from];
    def single as string init singleEscape($c);
    if ($single != "") {
        return Rx{ok: true, re: $single, next: $from + 1, lit: ""};
    }
    if ($c != "p" and $c != "P") {
        return $bad;
    }
    if ($from + 1 >= len($chars) or $chars[$from + 1] != LBRACE) {
        return $bad;
    }
    def close as int init $from + 2;
    while ($close < len($chars) and $close < $from + 5 and $chars[$close] != RBRACE) {
        $close = $close + 1;
    }
    if ($close >= len($chars) or $chars[$close] != RBRACE) {
        return $bad;
    }
    def name as string init strings.join(lists.slice($chars, $from + 2, $close), "");
    if (not regex.matches(
        "^(L[lmotu]?|M[cen]?|N[dlo]?|P[cdefios]?|Z[lps]?|S[ckmo]?|C[cfno]?)$",
        $name)) {
        return $bad;
    }
    return Rx{ok: true, re: "\\" + $c + LBRACE + $name + RBRACE, next: $close + 1, lit: ""};
}

/**
 * Translate a character class `[...]` (RFC 9485 `charClassExpr`): `-` is a
 * literal only first or last, and otherwise joins two single characters
 * into a range, never after a range or a category.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the position after `[`
 * @return {Rx} the RE2 class and the position after `]`, or not `ok`
 */
func charClass(chars as list of string, from as int) {
    def bad as Rx init Rx{ok: false, re: "", next: 0, lit: ""};
    def n as int init len($chars);
    def out as list of string init ["["];
    def i as int init $from;
    if ($i < $n and $chars[$i] == "^") {
        $out[] = "^";
        $i = $i + 1;
    }
    def items as int init 0;
    if ($i < $n and $chars[$i] == "-") {
        $out[] = "\\-";
        $i = $i + 1;
        $items = 1;
    }
    while (true) {
        if ($i >= $n) {
            return $bad;
        }
        def c as string init $chars[$i];
        if ($c == "]") {
            if ($items == 0) {
                return $bad;
            }
            break;
        }
        if ($c == "-") {
            if ($i + 1 < $n and $chars[$i + 1] == "]") {
                $out[] = "\\-";
                $i = $i + 1;
                $items = $items + 1;
                continue;
            }
            return $bad;
        }
        def low as Rx init classItem($chars, $i);
        if (not $low.ok) {
            return $bad;
        }
        $i = $low.next;
        if ($low.lit != "" and $i + 1 < $n and $chars[$i] == "-" and $chars[$i + 1] != "]") {
            def high as Rx init classItem($chars, $i + 1);
            if (not $high.ok or $high.lit == "" or
                convert.toCodepoint($high.lit) < convert.toCodepoint($low.lit)) {
                return $bad;
            }
            $out[] = $low.re + "-" + $high.re;
            $i = $high.next;
        } else {
            $out[] = $low.re;
        }
        $items = $items + 1;
    }
    $out[] = "]";
    return Rx{ok: true, re: strings.join($out, ""), next: $i + 1, lit: ""};
}

/**
 * One item of a character class: a character, a single-character escape
 * or a category.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the item's position
 * @return {Rx} the RE2 text, the position after it and the character it
 *   stands for (`lit` "" for a category); not `ok` for `[`, `]`, `-` or a
 *   bad escape
 */
func classItem(chars as list of string, from as int) {
    def c as string init $chars[$from];
    if ($c == "[" or $c == "]" or $c == "-") {
        return Rx{ok: false, re: "", next: 0, lit: ""};
    }
    if ($c != "\\") {
        return Rx{ok: true, re: $c, next: $from + 1, lit: $c};
    }
    def esc as Rx init escape($chars, $from + 1);
    if (not $esc.ok) {
        return $esc;
    }
    def e as string init $chars[$from + 1];
    if ($e != "p" and $e != "P") {
        $esc.lit = $e;
        if ($e == "n") {
            $esc.lit = "\n";
        } elseif ($e == "r") {
            $esc.lit = "\r";
        } elseif ($e == "t") {
            $esc.lit = "\t";
        }
    }
    return $esc;
}
