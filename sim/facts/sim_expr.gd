class_name SimExpr
extends RefCounted
## A tiny expression language over integer facts, for dialogue conditions,
## effects and quest outcomes (CLAUDE.md rule 8: outcomes are predicates over
## world facts).
##
##   alive.Bandits == 0 and not hostile.Village
##   gold_paid >= 2 or (met_guard and not self.suspicious)
##
## Values are integers; true is non-zero. Operators: or, and, not,
## == != < > <= >=, + -, parentheses. Names are letters, digits, _ and .
## (see SimFacts for what they mean). parse() turns text into a small tree of
## arrays, eval() works it out against a state.


## Why the last parse() failed.
static var last_error := ""


## Parses `text` into a tree, or returns null (and records why in last_error).
static func parse(text: String) -> Variant:
	var tokens: Variant = _tokenize(text)
	if tokens == null:
		return null
	var p := {"tokens": tokens, "i": 0}
	var tree: Variant = _or(p)
	if tree == null:
		return null
	if p.i < tokens.size():
		last_error = "Unexpected '%s' in: %s" % [tokens[p.i], text]
		return null
	return tree


static func eval(state: SimState, tree: Variant, context: Dictionary = {}) -> int:
	if tree == null:
		return 0
	var node: Array = tree
	match node[0]:
		"int":
			return node[1]
		"fact":
			return SimFacts.value(state, node[1], context)
		"not":
			return 0 if eval(state, node[1], context) != 0 else 1
		"and":
			return 1 if eval(state, node[1], context) != 0 and eval(state, node[2], context) != 0 else 0
		"or":
			return 1 if eval(state, node[1], context) != 0 or eval(state, node[2], context) != 0 else 0
		"add":
			var a := eval(state, node[2], context)
			var b := eval(state, node[3], context)
			return a + b if node[1] == "+" else a - b
		"cmp":
			var l := eval(state, node[2], context)
			var r := eval(state, node[3], context)
			match node[1]:
				"==": return 1 if l == r else 0
				"!=": return 1 if l != r else 0
				"<": return 1 if l < r else 0
				">": return 1 if l > r else 0
				"<=": return 1 if l <= r else 0
				">=": return 1 if l >= r else 0
	return 0


static func holds(state: SimState, tree: Variant, context: Dictionary = {}) -> bool:
	return eval(state, tree, context) != 0


# --- Parsing ---------------------------------------------------------------------

static func _tokenize(text: String) -> Variant:
	var tokens: Array[String] = []
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch == " " or ch == "\t":
			i += 1
			continue
		var two := text.substr(i, 2)
		if two in ["==", "!=", "<=", ">="]:
			tokens.append(two)
			i += 2
			continue
		if ch in ["(", ")", "<", ">", "+", "-"]:
			tokens.append(ch)
			i += 1
			continue
		if _is_name_char(ch):
			var start := i
			while i < text.length() and _is_name_char(text[i]):
				i += 1
			tokens.append(text.substr(start, i - start))
			continue
		last_error = "Unexpected character '%s' in: %s" % [ch, text]
		return null
	return tokens


static func _is_name_char(ch: String) -> bool:
	return ch == "_" or ch == "." or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")


static func _peek(p: Dictionary) -> String:
	return p.tokens[p.i] if p.i < p.tokens.size() else ""


static func _or(p: Dictionary) -> Variant:
	var left: Variant = _and(p)
	while left != null and _peek(p) == "or":
		p.i += 1
		var right: Variant = _and(p)
		if right == null:
			return null
		left = ["or", left, right]
	return left


static func _and(p: Dictionary) -> Variant:
	var left: Variant = _not(p)
	while left != null and _peek(p) == "and":
		p.i += 1
		var right: Variant = _not(p)
		if right == null:
			return null
		left = ["and", left, right]
	return left


static func _not(p: Dictionary) -> Variant:
	if _peek(p) == "not":
		p.i += 1
		var inner: Variant = _not(p)
		return null if inner == null else ["not", inner]
	return _cmp(p)


static func _cmp(p: Dictionary) -> Variant:
	var left: Variant = _sum(p)
	if left != null and _peek(p) in ["==", "!=", "<", ">", "<=", ">="]:
		var op := _peek(p)
		p.i += 1
		var right: Variant = _sum(p)
		if right == null:
			return null
		return ["cmp", op, left, right]
	return left


static func _sum(p: Dictionary) -> Variant:
	var left: Variant = _atom(p)
	while left != null and _peek(p) in ["+", "-"]:
		var op := _peek(p)
		p.i += 1
		var right: Variant = _atom(p)
		if right == null:
			return null
		left = ["add", op, left, right]
	return left


static func _atom(p: Dictionary) -> Variant:
	var t := _peek(p)
	if t == "":
		last_error = "Expression ends too early"
		return null
	p.i += 1
	if t == "(":
		var inner: Variant = _or(p)
		if _peek(p) != ")":
			last_error = "Missing )"
			return null
		p.i += 1
		return inner
	if t.is_valid_int():
		return ["int", int(t)]
	if t in ["and", "or", "not", ")"] or not _is_name_char(t[0]):
		last_error = "Unexpected '%s'" % t
		return null
	return ["fact", t]
