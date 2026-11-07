import Foundation

/// Reading Python properly, with Python's own parser. A small model's reply often isn't what it should be,
/// so code works out what it means: where a function starts and ends, and how a fragment fits a file.
enum DevPython {
    struct Syntax: Decodable, Sendable {
        var ok: Bool
        var line: Int?
        var message: String?
    }

    struct Definition: Decodable, Sendable {
        var name: String
        var kind: String
        var start: Int
        var end: Int
        var signature: String
    }

    struct Outline: Decodable, Sendable {
        var ok: Bool
        var definitions: [Definition] = []
        var hasMain = false
    }

    struct Merged: Decodable, Sendable {
        var ok: Bool
        var source: String?
        var replaced: [String] = []
        var added: [String] = []
    }

    private static let helper = #"""
    import ast, json, sys

    def lines_of(node):
        first = min([d.lineno for d in getattr(node, "decorator_list", [])] + [node.lineno])
        return first, node.end_lineno

    def signature(node):
        try:
            args = ast.unparse(node.args)
        except Exception:
            args = ", ".join(a.arg for a in node.args.args)
        return "def %s(%s)" % (node.name, args)

    def check(req):
        try:
            compile(req["source"], req.get("name", "file"), "exec")
            return {"ok": True}
        except SyntaxError as e:
            return {"ok": False, "line": e.lineno, "message": "%s: %s" % (type(e).__name__, e.msg)}

    def defs(tree):
        out = []
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                first, last = lines_of(node)
                out.append({"name": node.name, "kind": "function", "start": first, "end": last, "signature": signature(node)})
            elif isinstance(node, ast.ClassDef):
                first, last = lines_of(node)
                out.append({"name": node.name, "kind": "class", "start": first, "end": last, "signature": "class " + node.name})
                for item in node.body:
                    if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        a, b = lines_of(item)
                        out.append({"name": node.name + "." + item.name, "kind": "method", "start": a, "end": b,
                                    "signature": "  " + signature(item)})
        return out

    def is_main(node):
        return isinstance(node, ast.If) and "__name__" in ast.dump(node.test)

    def outline(req):
        try:
            tree = ast.parse(req["source"])
        except SyntaxError:
            return {"ok": False}
        return {"ok": True, "definitions": defs(tree), "hasMain": any(is_main(n) for n in tree.body)}

    def merge(req):
        original, patch = [req[k].replace("\r\n", "\n").replace("\r", "\n") for k in ("original", "patch")]
        try:
            old, new = ast.parse(original), ast.parse(patch)
        except SyntaxError:
            return {"ok": False}
        lines = original.split("\n")
        patch_lines = patch.split("\n")
        def text(node):
            a, b = lines_of(node)
            return patch_lines[a - 1:b]
        top = {n.name: n for n in old.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))}
        methods = {}
        for n in old.body:
            if isinstance(n, ast.ClassDef):
                for m in n.body:
                    if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        methods.setdefault(m.name, m)
        edits, replaced, additions = [], [], []
        imports = []
        have = {ast.get_source_segment(original, n) for n in old.body if isinstance(n, (ast.Import, ast.ImportFrom))}
        used = {n.id for n in ast.walk(new) if isinstance(n, ast.Name)}
        only = set(filter(None, req.get("only", "").split(",")))
        for node in new.body:
            name = getattr(node, "name", None)
            if only and name is not None and name not in only and (name in top or name in methods):
                continue
            if only and is_main(node):
                continue
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                segment = ast.get_source_segment(patch, node)
                bound = [(a.asname or a.name).split(".")[0] for a in node.names]
                if segment not in have and any(b in used for b in bound):
                    imports.append(segment)
            elif isinstance(node, ast.ClassDef) and node.name in top and isinstance(top[node.name], ast.ClassDef):
                current = top[node.name]
                owned = {m.name: m for m in current.body if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef))}
                given = [m for m in node.body if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef))]
                if set(owned) <= {m.name for m in given}:
                    a, b = lines_of(current)
                    edits.append((a, b, text(node)))
                else:
                    extra = []
                    for m in given:
                        if m.name in owned:
                            a, b = lines_of(owned[m.name])
                            edits.append((a, b, text(m)))
                        else:
                            extra += [""] + text(m)
                    if extra:
                        edits.append((current.end_lineno + 1, current.end_lineno, extra))
                replaced.append(node.name)
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                if node.name in top:
                    a, b = lines_of(top[node.name])
                    edits.append((a, b, text(node)))
                    replaced.append(node.name)
                elif node.name in methods and not isinstance(node, ast.ClassDef):
                    a, b = lines_of(methods[node.name])
                    indent = " " * (methods[node.name].col_offset - node.col_offset)
                    edits.append((a, b, [indent + l if l.strip() else l for l in text(node)]))
                    replaced.append(node.name)
                else:
                    additions.append(text(node))
            elif is_main(node):
                current = next((n for n in old.body if is_main(n)), None)
                body = patch_lines[node.lineno - 1:node.end_lineno]
                if current is not None:
                    edits.append((current.lineno, current.end_lineno, body))
                else:
                    additions.append(body)
        for a, b, body in sorted(edits, key=lambda e: e[0], reverse=True):
            lines[a - 1:b] = body
        result = "\n".join(lines)
        if additions:
            tree = ast.parse(result)
            main = next((n for n in tree.body if is_main(n)), None)
            lines = result.split("\n")
            at = main.lineno - 1 if main is not None else len(lines)
            block = []
            for body in additions:
                block += body + [""]
            lines[at:at] = block
            result = "\n".join(lines)
        if imports:
            tree = ast.parse(result)
            first = 0
            if tree.body and isinstance(tree.body[0], ast.Expr) and isinstance(getattr(tree.body[0], "value", None), ast.Constant):
                first = tree.body[0].end_lineno
            lines = result.split("\n")
            lines[first:first] = imports
            result = "\n".join(lines)
        try:
            compile(result, "merged", "exec")
        except SyntaxError:
            return {"ok": False}
        added = [n.name for n in new.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n.name not in replaced]
        return {"ok": True, "source": result, "replaced": replaced, "added": added}

    req = json.load(sys.stdin)
    print(json.dumps({"check": check, "outline": outline, "merge": merge}[req["op"]](req)))
    """#

    /// An empty folder, so a project's own json.py can't stand in for the one these need.
    private static let quietFolder: URL? = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-dev-parser", isDirectory: true)
        return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) == nil ? nil : folder
    }()

    private static func call<Reply: Decodable>(_ request: [String: String]) async -> Reply? {
        guard let body = try? JSONSerialization.data(withJSONObject: request), let quietFolder else { return nil }
        let result = await DevRunner.run(["-c", helper], in: quietFolder, input: String(decoding: body, as: UTF8.self))
        guard result.succeeded, let line = result.output.split(whereSeparator: \.isNewline).last,
              let data = String(line).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Reply.self, from: data)
    }

    static func check(_ source: String, name: String) async -> Syntax {
        await call(["op": "check", "source": source, "name": name]) ?? Syntax(ok: true)
    }

    static func outline(_ source: String) async -> Outline {
        await call(["op": "outline", "source": source]) ?? Outline(ok: false)
    }

    /// Fits a fragment into a file: same-named functions are replaced and new ones added. `only` limits
    /// which existing ones it may replace, since a model that wasn't shown a function can't improve it.
    static func merge(_ patch: String, into original: String, only: [String] = []) async -> Merged {
        await call(["op": "merge", "original": original, "patch": patch, "only": only.joined(separator: ",")]) ?? Merged(ok: false)
    }
}
