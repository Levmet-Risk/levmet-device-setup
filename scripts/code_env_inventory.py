"""Inventory environment references without importing or executing the inspected code.

Reports contain names and source locations, never environment values or defaults.
Dynamic accesses and parse failures remain visible for manual review.
"""
from __future__ import annotations

import argparse
import ast
import json
import os
from pathlib import Path
import re
import warnings

NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
SKIP = {".git", ".claude", ".cache", "__pycache__", "node_modules", "site-packages", "venv"}


def inventory(root: Path) -> dict:
    records: dict[str, list[dict]] = {}
    unresolved: list[dict] = []
    hardcoded_paths: list[dict] = []
    files = 0

    def add(name, file, line, kind="read"):
        if not isinstance(name, str) or not NAME.fullmatch(name):
            return
        # Windows environment variable names are case-insensitive.
        canonical = "user_email" if name.lower() == "user_email" else name.upper()
        record = {"file": file, "line": line, "kind": kind}
        if record not in records.setdefault(canonical, []):
            records[canonical].append(record)

    for directory, dirs, filenames in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in SKIP and not d.startswith(".venv"))
        for filename in sorted(filenames):
            path = Path(directory) / filename
            suffix = path.suffix.lower()
            if suffix not in {".py", ".ipynb", ".ps1", ".bat", ".cmd", ".js", ".ts", ".tsx", ".r", ".yaml", ".yml", ".toml", ".json"} and not filename.startswith(".env"):
                continue
            relative = path.relative_to(root).as_posix()
            try:
                if path.stat().st_size > 5_000_000:
                    unresolved.append({"file": relative, "reason": "File exceeds the 5 MB scan limit"})
                    continue
                source = path.read_text(encoding="utf-8-sig")
            except UnicodeError:
                source = path.read_text(encoding="cp1252")
            except OSError:
                unresolved.append({"file": relative, "reason": "File could not be read; check local sync availability"})
                continue
            files += 1
            if suffix == ".ipynb":
                try:
                    source = "\n".join("".join(c.get("source", [])) for c in json.loads(source)["cells"] if c.get("cell_type") == "code")
                except (ValueError, KeyError):
                    unresolved.append({"file": relative, "reason": "Notebook could not be parsed"})
                    continue
            if suffix in {".py", ".ipynb"}:
                try:
                    with warnings.catch_warnings():
                        warnings.simplefilter("ignore", SyntaxWarning)
                        tree = ast.parse(source)
                except SyntaxError as error:
                    unresolved.append({"file": relative, "line": error.lineno, "reason": "Python parse error; literal accesses still scanned"})
                    tree = None
                if tree:
                    constants = {}
                    aliases = {}
                    for node in ast.walk(tree):
                        if isinstance(node, ast.Constant) and isinstance(node.value, str) and (re.search(r"(?i)[a-z]:[\\/]users[\\/]", node.value) or "OneDrive - Levmet" in node.value):
                            location = {"file": relative, "line": node.lineno}
                            if location not in hardcoded_paths:
                                hardcoded_paths.append(location)
                        if isinstance(node, (ast.Assign, ast.AnnAssign)) and isinstance(node.value, ast.Constant):
                            for target in node.targets if isinstance(node, ast.Assign) else [node.target]:
                                if isinstance(target, ast.Name):
                                    constants[target.id] = node.value.value
                        elif isinstance(node, ast.Import):
                            for entry in node.names:
                                aliases[entry.asname or entry.name] = entry.name
                        elif isinstance(node, ast.ImportFrom):
                            for entry in node.names:
                                aliases[entry.asname or entry.name] = (node.module or "") + "." + entry.name

                    def symbol(node):
                        if isinstance(node, ast.Name):
                            return aliases.get(node.id, node.id)
                        if isinstance(node, ast.Attribute):
                            return symbol(node.value) + "." + node.attr
                        return ""

                    def value(node):
                        if isinstance(node, ast.Constant):
                            return node.value
                        if isinstance(node, ast.Name):
                            return constants.get(node.id)
                        return None

                    getters = {"os.getenv", "os.environ.get", "os.environ.setdefault", "os.environ.pop"}
                    wrappers = {}
                    for function in (n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))):
                        parameters = [p.arg for p in function.args.args]
                        for call in ast.walk(function):
                            if isinstance(call, ast.Call) and symbol(call.func) in getters and call.args and isinstance(call.args[0], ast.Name) and call.args[0].id in parameters:
                                wrappers[function.name] = parameters.index(call.args[0].id)
                    for node in ast.walk(tree):
                        if isinstance(node, ast.Call):
                            function = symbol(node.func)
                            index = 0 if function in getters else wrappers.get(function)
                            if index is not None and len(node.args) > index:
                                name = value(node.args[index])
                                if name is not None:
                                    add(name, relative, node.lineno)
                                elif not (isinstance(node.args[index], ast.Name) and node.args[index].id in {"name", "env_name"}):
                                    unresolved.append({"file": relative, "line": node.lineno, "reason": "Dynamic environment name"})
                        elif isinstance(node, ast.Subscript) and symbol(node.value) == "os.environ":
                            name = value(node.slice)
                            if name is None:
                                unresolved.append({"file": relative, "line": node.lineno, "reason": "Dynamic environment name"})
                            else:
                                add(name, relative, node.lineno, "write" if isinstance(node.ctx, ast.Store) else "read")
                        elif isinstance(node, ast.ClassDef) and any(symbol(base).endswith("BaseSettings") for base in node.bases):
                            # The inspected dashboard has no prefix or nested delimiter.
                            for field in node.body:
                                if not isinstance(field, ast.AnnAssign) or not isinstance(field.target, ast.Name):
                                    continue
                                aliases_found = []
                                if isinstance(field.value, ast.Call):
                                    aliases_found = [value(k.value) for k in field.value.keywords if k.arg in {"validation_alias", "alias", "env"}]
                                for name in aliases_found or [field.target.id.upper()]:
                                    add(name, relative, field.lineno, "settings-model")
                                if aliases_found:
                                    add(field.target.id.upper(), relative, field.lineno, "settings-model-field")
            # Literal fallback also covers syntactically broken legacy Python files.
            patterns = [(r'''\b(?:getenv|environ\.(?:get|setdefault|pop))\(\s*["']([A-Za-z_][A-Za-z0-9_]*)["']''', "read"),
                        (r'''\benviron\s*\[\s*["']([A-Za-z_][A-Za-z0-9_]*)["']''', "read")]
            if suffix not in {".py", ".ipynb"}:
                patterns += [(r"\$env:([A-Za-z_][A-Za-z0-9_]*)", "shell"),
                             (r"\bprocess\.env\.([A-Za-z_][A-Za-z0-9_]*)", "read"),
                             (r'''(?:GetEnvironmentVariable|SetEnvironmentVariable|Sys\.getenv)\(\s*["']([A-Za-z_][A-Za-z0-9_]*)["']''', "read"),
                             (r"\$\{([A-Z_][A-Z0-9_]*)\}", "substitution")]
            if suffix in {".bat", ".cmd"}:
                patterns += [(r"%([A-Za-z_][A-Za-z0-9_]*)%", "batch"),
                             (r'(?im)^\s*(?:set|setx)\s+"?([A-Za-z_][A-Za-z0-9_]*)[= ]', "batch")]
            if filename.startswith(".env"):
                patterns += [(r"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=", "dotenv")]
            for pattern, kind in patterns:
                for match in re.finditer(pattern, source):
                    add(match[1], relative, source.count("\n", 0, match.start()) + 1, kind)
    return {"schemaVersion": 1, "scannedFiles": files,
            "variables": [{"name": name, "references": refs} for name, refs in sorted(records.items())],
            "unresolved": unresolved, "hardcodedPathReferences": hardcoded_paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--code-root", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.code_root.is_dir():
        parser.error("Code directory does not exist")
    report = inventory(args.code_root)
    text = json.dumps(report, indent=2, ensure_ascii=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
