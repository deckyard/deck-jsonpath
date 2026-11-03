# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

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
 * A translated regular expression.
 *
 * @field ok {bool} whether the pattern was valid I-Regexp
 * @field re {string} the RE2 pattern
 */
def struct Rx {
    ok as bool,
    re as string
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
 * `match()` and `search()`: whether a string matches an I-Regexp, as a whole
 * or anywhere. A non-string or an invalid pattern gives false.
 *
 * @param subject {Val} the string
 * @param pattern {Val} the I-Regexp
 * @param whole {bool} true for `match`, false for `search`
 * @return {bool} the result
 */
func fnMatch(subject as Val, pattern as Val, whole as bool) {
    if (not $subject.present or not $pattern.present) {
        return false;
    }
    if (json.typeOf($subject.value) != "string" or json.typeOf($pattern.value) != "string") {
        return false;
    }
    def rx as Rx init translate(json.asString($pattern.value));
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
        return false;
    }
}

/**
 * Translate an I-Regexp into RE2. `.` becomes `[^\n\r]`, and anything
 * outside RFC 9485's grammar is refused. `^` and `$` stay anchors, as the
 * compliance suite expects.
 *
 * @param pattern {string} the I-Regexp
 * @return {Rx} the RE2 pattern, or not `ok`
 */
func translate(pattern as string) {
    def bad as Rx init Rx{ok: false, re: ""};
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
            def text as string init $cls.re;
            $out[] = $text;
            $i = $i + classLength($chars, $i);
            $canQuantify = true;
        } elseif ($c == "\\") {
            def esc as Rx init escape($chars, $i);
            if (not $esc.ok) {
                return $bad;
            }
            $out[] = $esc.re;
            $i = $i + escapeLength($chars, $i);
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
    return Rx{ok: true, re: strings.join($out, "")};
}

/**
 * The end of a range quantifier `{n}`, `{n,}` or `{n,m}`.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the position after `{`
 * @return {int} the position of `}`; -1 when the quantifier is malformed
 */
func rangeEnd(chars as list of string, from as int) {
    def i as int init $from;
    def digits as int init 0;
    while ($i < len($chars) and isDigit($chars[$i])) {
        $i = $i + 1;
        $digits = $digits + 1;
    }
    if ($digits == 0 or $i >= len($chars)) {
        return -1;
    }
    if ($chars[$i] == ",") {
        $i = $i + 1;
        while ($i < len($chars) and isDigit($chars[$i])) {
            $i = $i + 1;
        }
    }
    if ($i >= len($chars) or $chars[$i] != RBRACE) {
        return -1;
    }
    return $i;
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
 * `\P{..}`.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the position after the backslash
 * @return {Rx} the RE2 text, or not `ok`
 */
func escape(chars as list of string, from as int) {
    def bad as Rx init Rx{ok: false, re: ""};
    if ($from >= len($chars)) {
        return $bad;
    }
    def c as string init $chars[$from];
    def single as string init singleEscape($c);
    if ($single != "") {
        return Rx{ok: true, re: $single};
    }
    if ($c != "p" and $c != "P") {
        return $bad;
    }
    def close as int init lists.indexOf(lists.slice($chars, $from), RBRACE);
    if ($from + 1 >= len($chars) or $chars[$from + 1] != LBRACE or $close < 0) {
        return $bad;
    }
    def name as string init strings.join(lists.slice($chars, $from + 2, $from + $close), "");
    if (not regex.matches(
        "^(L[lmotu]?|M[cen]?|N[dlo]?|P[cdefios]?|Z[lps]?|S[ckmo]?|C[cfno]?)$",
        $name)) {
        return $bad;
    }
    return Rx{ok: true, re: "\\" + $c + LBRACE + $name + RBRACE};
}

/**
 * How many code points an escape takes after the backslash.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the position after the backslash
 * @return {int} its length
 */
func escapeLength(chars as list of string, from as int) {
    if ($chars[$from] == "p" or $chars[$from] == "P") {
        return lists.indexOf(lists.slice($chars, $from), RBRACE) + 1;
    }
    return 1;
}

/**
 * Translate a character class `[...]`.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the position after `[`
 * @return {Rx} the RE2 class, or not `ok`
 */
func charClass(chars as list of string, from as int) {
    def bad as Rx init Rx{ok: false, re: ""};
    def out as list of string init ["["];
    def i as int init $from;
    if ($i < len($chars) and $chars[$i] == "^") {
        $out[] = "^";
        $i = $i + 1;
    }
    def items as int init 0;
    while (true) {
        if ($i >= len($chars)) {
            return $bad;
        }
        def c as string init $chars[$i];
        if ($c == "]") {
            if ($items == 0) {
                return $bad;
            }
            break;
        }
        if ($c == "[") {
            return $bad;
        }
        if ($c == "\\") {
            def esc as Rx init escape($chars, $i + 1);
            if (not $esc.ok) {
                return $bad;
            }
            $out[] = $esc.re;
            $i = $i + 1 + escapeLength($chars, $i + 1);
        } elseif ($c == "-") {
            def edge as bool init $items == 0 or ($i + 1 < len($chars) and $chars[$i + 1] == "]");
            if ($edge) {
                $out[] = "\\-";
            } else {
                $out[] = "-";
            }
            $i = $i + 1;
        } else {
            $out[] = $c;
            $i = $i + 1;
        }
        $items = $items + 1;
    }
    $out[] = "]";
    return Rx{ok: true, re: strings.join($out, "")};
}

/**
 * How many code points a character class takes after `[`, its `]` included.
 *
 * @param chars {list of string} the pattern
 * @param from {int} the position after `[`
 * @return {int} its length
 */
func classLength(chars as list of string, from as int) {
    def i as int init $from;
    while ($i < len($chars) and $chars[$i] != "]") {
        if ($chars[$i] == "\\") {
            $i = $i + 1 + escapeLength($chars, $i + 1);
        } else {
            $i = $i + 1;
        }
    }
    return $i - $from + 1;
}
