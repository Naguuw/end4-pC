#!/usr/bin/env python3
"""
read-file.py — Smart file reader for the AI sidebar assistant.

Instead of feeding raw files to the LLM (which wastes thousands of tokens),
this script extracts structural skeletons: signatures, docstrings, class/function
outlines, markdown headers, and sample tables — while respecting a strict character budget.

Supported formats:
  - Python (.py, .pyw): AST-based skeleton (classes, functions, decorators, docstrings)
  - Jupyter Notebooks (.ipynb): Cell-by-cell outline (markdown notes + code, strips base64/plots)
  - PDF (.pdf): Clean text extraction via pdftotext with page count & header
  - JS/TS (.js, .ts, .jsx, .tsx): Function, class, const, interface declarations
  - Shell (.sh, .bash, .zsh): Function declarations + sourced files + key env vars
  - QML (.qml): Component properties, signals, and function signatures
  - Data / Tables (.csv, .tsv): Row/column count, column headers, first 5 sample rows
  - Structured Config (.json, .yaml, .yml, .toml): Key structure, types, array sizes
  - Markdown (.md, .markdown): Table of contents / section outline + overview
  - Plain Text (.txt, .log, .conf, note.txt): Cleaned text with line-count and head/tail budget

Usage:
  python3 read-file.py <file_path> [--max-chars N] [--full]
"""
import sys
import os
import re
import json
import subprocess
import csv
import io
import ast as python_ast
from pathlib import Path

MAX_CHARS = 30000


# ──────────────────────────────────────────────
# Utilities
# ──────────────────────────────────────────────

def truncate(text: str, max_chars: int = MAX_CHARS) -> str:
    """Apply a character budget with a visible truncation marker."""
    if len(text) > max_chars:
        return text[:max_chars].rstrip() + f"\n\n[Truncated at {max_chars} chars — use --full or --max-chars to see more]"
    return text


def file_header(path: str, total_lines: int, lang: str) -> str:
    """Standardized metadata header for every output."""
    size = os.path.getsize(path)
    unit = "B"
    display_size = float(size)
    if size >= 1024 * 1024:
        display_size = size / (1024 * 1024)
        unit = "MB"
    elif size >= 1024:
        display_size = size / 1024
        unit = "KB"
    return (
        f"── {os.path.basename(path)} ──\n"
        f"Path: {path}\n"
        f"Type: {lang} | {total_lines} items/lines | {display_size:.1f} {unit}\n"
        f"{'─' * 40}"
    )


def read_file_safe(path: str) -> str:
    """Read a text file with graceful encoding fallback."""
    for encoding in ("utf-8", "latin-1", "cp1252"):
        try:
            return Path(path).read_text(encoding=encoding)
        except (UnicodeDecodeError, ValueError):
            continue
    return ""


# ──────────────────────────────────────────────
# Jupyter Notebook (.ipynb): extract code & notes
# ──────────────────────────────────────────────

def skeleton_ipynb(source: str, path: str) -> str:
    """
    Parse Jupyter Notebook JSON, extracting full markdown instructions/tasks and code cells
    while stripping heavy base64 binary plots and raw data blobs.
    """
    try:
        data = json.loads(source)
    except Exception as e:
        return f"Error parsing notebook JSON: {e}"

    cells = data.get("cells", [])
    total_cells = len(cells)
    kernel = data.get("metadata", {}).get("kernelspec", {}).get("display_name", "Python / Jupyter")

    parts = [file_header(path, total_cells, f"Jupyter Notebook ({kernel})")]
    parts.append(f"\nTotal Cells: {total_cells}")

    md_count = sum(1 for c in cells if c.get("cell_type") == "markdown")
    code_count = sum(1 for c in cells if c.get("cell_type") == "code")
    parts.append(f"  • {code_count} Code cells | {md_count} Markdown cells\n")

    for i, cell in enumerate(cells, 1):
        cell_type = cell.get("cell_type", "unknown")
        raw_src = cell.get("source", [])
        cell_text = "".join(raw_src) if isinstance(raw_src, list) else str(raw_src)
        cell_text = cell_text.strip()

        if not cell_text:
            continue

        if cell_type == "markdown":
            parts.append(f"\n[Cell {i} : Markdown / Instructions]")
            parts.append(cell_text)

        elif cell_type == "code":
            lines = cell_text.splitlines()
            exec_count = cell.get("execution_count", i)
            parts.append(f"\n[Cell {i} : Code (In [{exec_count or ' '}])] ({len(lines)} lines)")

            CELL_LINE_BUDGET = 30
            if len(lines) <= CELL_LINE_BUDGET:
                for line in lines:
                    parts.append(f"  {line}")
            else:
                head, tail = 20, 5
                for line in lines[:head]:
                    parts.append(f"  {line}")
                skipped = len(lines) - head - tail
                parts.append(f"  ... ({skipped} lines omitted) ...")
                for line in lines[-tail:]:
                    parts.append(f"  {line}")

            # Check outputs (text and error messages only, strip base64 plots)
            outputs = cell.get("outputs", [])
            for out in outputs:
                if out.get("output_type") == "error":
                    ename = out.get("ename", "Error")
                    evalue = out.get("evalue", "")
                    parts.append(f"  ⚠️ Error: {ename}: {evalue}")
                elif "text" in out:
                    raw_out = "".join(out["text"]).strip()
                    if raw_out:
                        out_lines = raw_out.splitlines()
                        short_out = "\n".join(f"  >> {l}" for l in out_lines[:4])
                        if len(out_lines) > 4:
                            short_out += f"\n  >> ... (+{len(out_lines) - 4} output lines)"
                        parts.append(short_out)
                elif "data" in out and "text/plain" in out["data"]:
                    raw_out = "".join(out["data"]["text/plain"]).strip()
                    if raw_out:
                        out_lines = raw_out.splitlines()
                        short_out = "\n".join(f"  >> {l}" for l in out_lines[:4])
                        if len(out_lines) > 4:
                            short_out += f"\n  >> ... (+{len(out_lines) - 4} output lines)"
                        parts.append(short_out)

    return "\n".join(parts)


# ──────────────────────────────────────────────
# PDF Document (.pdf)
# ──────────────────────────────────────────────

def skeleton_pdf(path: str) -> str:
    """Extract clean text from PDF using pdftotext or python libraries."""
    # 1. Try pdftotext command line tool (fastest & high quality)
    try:
        proc = subprocess.run(
            ["pdftotext", "-q", "-layout", path, "-"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            raw_text = proc.stdout
            lines = [l.rstrip() for l in raw_text.splitlines() if l.strip()]
            header = file_header(path, len(lines), "PDF Document")
            clean_text = "\n".join(lines)
            return f"{header}\n\n{clean_text}"
    except Exception:
        pass

    # 2. Try python pypdf / pypdf2 fallback
    for mod_name in ("pypdf", "PyPDF2"):
        try:
            pdf_mod = __import__(mod_name)
            reader = pdf_mod.PdfReader(path)
            num_pages = len(reader.pages)
            extracted_pages = []
            for idx in range(min(num_pages, 10)):
                txt = reader.pages[idx].extract_text() or ""
                if txt.strip():
                    extracted_pages.append(f"--- Page {idx + 1} ---\n{txt.strip()}")
            all_text = "\n\n".join(extracted_pages)
            lines = all_text.splitlines()
            header = file_header(path, len(lines), f"PDF Document ({num_pages} pages)")
            return f"{header}\n\n{all_text}"
        except Exception:
            continue

    return f"Error: Cannot extract PDF text. Ensure `poppler-utils` (pdftotext) or `pypdf` is installed."


# ──────────────────────────────────────────────
# Python: AST-based skeleton
# ──────────────────────────────────────────────

def skeleton_python(source: str, path: str) -> str:
    """Extract class/function signatures, decorators, and docstrings via AST."""
    try:
        tree = python_ast.parse(source, filename=path)
    except SyntaxError:
        return skeleton_generic(source, path, "Python (syntax error — fallback)")

    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "Python")]

    # Top-level imports
    imports = []
    for node in python_ast.iter_child_nodes(tree):
        if isinstance(node, python_ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, python_ast.ImportFrom):
            module = node.module or ""
            names = ", ".join(a.name for a in node.names[:5])
            if len(node.names) > 5:
                names += f" (+{len(node.names) - 5} more)"
            imports.append(f"from {module} import {names}")
    if imports:
        parts.append("\n[Imports]")
        parts.append("\n".join(f"  {imp}" for imp in imports[:15]))

    # Top-level constants / assignments
    top_vars = []
    for node in python_ast.iter_child_nodes(tree):
        if isinstance(node, python_ast.Assign) and node.end_lineno == node.lineno:
            top_vars.append(lines[node.lineno - 1].strip())
        elif isinstance(node, python_ast.AnnAssign) and node.end_lineno == node.lineno:
            top_vars.append(lines[node.lineno - 1].strip())
    if top_vars:
        parts.append("\n[Module-level variables]")
        for v in top_vars[:15]:
            parts.append(f"  {v}")
        if len(top_vars) > 15:
            parts.append(f"  (+{len(top_vars) - 15} more)")

    def _format_node(node, indent=0):
        prefix = "  " * indent
        result = []

        decorators = getattr(node, "decorator_list", [])
        for dec in decorators:
            dec_line = lines[dec.lineno - 1].strip() if dec.lineno <= total_lines else ""
            result.append(f"{prefix}{dec_line}")

        sig_line = lines[node.lineno - 1].strip() if node.lineno <= total_lines else ""
        result.append(f"{prefix}{sig_line}")

        docstring = python_ast.get_docstring(node)
        if docstring:
            short_doc = docstring.split("\n")[0].strip()
            if len(short_doc) > 120:
                short_doc = short_doc[:117] + "..."
            result.append(f"{prefix}    \"\"\"{short_doc}\"\"\"")

        body = getattr(node, "body", [])
        body_without_docstring = body[1:] if docstring and body else body
        if body_without_docstring:
            start = body_without_docstring[0].lineno
            end = node.end_lineno or start
            body_lines = end - start + 1
            if body_lines > 1:
                result.append(f"{prefix}    ... ({body_lines} lines)")

        for child in body:
            if isinstance(child, (python_ast.FunctionDef, python_ast.AsyncFunctionDef, python_ast.ClassDef)):
                result.append("")
                result.extend(_format_node(child, indent + 1))

        return result

    for node in python_ast.iter_child_nodes(tree):
        if isinstance(node, (python_ast.FunctionDef, python_ast.AsyncFunctionDef, python_ast.ClassDef)):
            parts.append("")
            parts.extend(_format_node(node))

    return "\n".join(parts)


# ──────────────────────────────────────────────
# JavaScript / TypeScript
# ──────────────────────────────────────────────

def skeleton_js(source: str, path: str) -> str:
    lines = source.splitlines()
    total_lines = len(lines)
    ext = Path(path).suffix
    lang = "TypeScript" if ext in (".ts", ".tsx") else "JavaScript"
    parts = [file_header(path, total_lines, lang)]

    import_lines = [l.strip() for l in lines if re.match(r"^\s*(import\s|const\s.*=\s*require)", l)]
    if import_lines:
        parts.append("\n[Imports]")
        for imp in import_lines[:15]:
            parts.append(f"  {imp}")

    patterns = [
        r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*\w+\s*\(",
        r"^\s*(?:export\s+)?class\s+\w+",
        r"^\s*(?:export\s+)?(?:const|let|var)\s+\w+\s*=",
        r"^\s*(?:export\s+)?(?:type|interface|enum)\s+\w+",
        r"^\s*module\.exports\s*=",
    ]
    combined = re.compile("|".join(patterns))

    parts.append("\n[Declarations]")
    found = 0
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*"):
            continue
        if combined.match(stripped):
            sig = stripped.rstrip("{").rstrip()
            parts.append(f"  L{i}: {sig}")
            found += 1

    if found == 0:
        parts.append("  (no top-level declarations found)")

    return "\n".join(parts)


# ──────────────────────────────────────────────
# Shell Scripts (.sh, .bash)
# ──────────────────────────────────────────────

def skeleton_shell(source: str, path: str) -> str:
    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "Shell")]

    if lines and lines[0].startswith("#!"):
        parts.append(f"\n  {lines[0]}")

    sourced = [l.strip() for l in lines if re.match(r"^\s*(\.|source)\s+", l)]
    if sourced:
        parts.append("\n[Sourced files]")
        for s in sourced:
            parts.append(f"  {s}")

    vars_found = []
    for l in lines:
        stripped = l.strip()
        if re.match(r"^[A-Z_][A-Z_0-9]*=", stripped) and not stripped.startswith("#"):
            vars_found.append(stripped)
    if vars_found:
        parts.append("\n[Environment / variables]")
        for v in vars_found[:15]:
            short_v = v if len(v) <= 100 else v[:97] + "..."
            parts.append(f"  {short_v}")

    func_pattern = re.compile(r"^\s*(?:function\s+)?(\w[\w-]*)\s*\(\s*\)\s*\{?")
    functions = []
    for i, line in enumerate(lines, 1):
        m = func_pattern.match(line)
        if m:
            name = m.group(1)
            comment = ""
            if i >= 2:
                prev = lines[i - 2].strip()
                if prev.startswith("#") and not prev.startswith("#!"):
                    comment = f"  {prev}"
            functions.append((i, name, comment))

    if functions:
        parts.append("\n[Functions]")
        for lineno, name, comment in functions:
            if comment:
                parts.append(comment)
            parts.append(f"  L{lineno}: {name}()")

    return "\n".join(parts)


# ──────────────────────────────────────────────
# QML Component (.qml)
# ──────────────────────────────────────────────

def skeleton_qml(source: str, path: str) -> str:
    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "QML")]

    import_lines = [l.strip() for l in lines if l.strip().startswith("import ")]
    if import_lines:
        parts.append("\n[Imports]")
        for imp in import_lines:
            parts.append(f"  {imp}")

    root_match = re.search(r"^(\w[\w.]*)\s*\{", source, re.MULTILINE)
    if root_match:
        parts.append(f"\n[Root] {root_match.group(1)}")

    prop_pattern = re.compile(
        r"^\s*(?:readonly\s+|default\s+)?property\s+(?:var|string|int|real|bool|list|url|color|alias|[\w.]+)\s+(\w+)"
    )
    props = []
    for i, line in enumerate(lines, 1):
        m = prop_pattern.match(line)
        if m:
            short = line.strip()
            if len(short) > 120:
                short = short[:117] + "..."
            props.append(f"  L{i}: {short}")
    if props:
        parts.append("\n[Properties]")
        parts.extend(props[:30])

    sig_pattern = re.compile(r"^\s*signal\s+(\w+)")
    signals = []
    for i, line in enumerate(lines, 1):
        m = sig_pattern.match(line)
        if m:
            signals.append(f"  L{i}: signal {m.group(1)}")
    if signals:
        parts.append("\n[Signals]")
        parts.extend(signals)

    func_pattern = re.compile(r"^\s*function\s+(\w+)\s*\(([^)]*)\)")
    funcs = []
    for i, line in enumerate(lines, 1):
        m = func_pattern.match(line)
        if m:
            funcs.append(f"  L{i}: function {m.group(1)}({m.group(2)})")
    if funcs:
        parts.append("\n[Functions]")
        parts.extend(funcs)

    return "\n".join(parts)


# ──────────────────────────────────────────────
# C / C++ (.c, .cpp, .h, .hpp)
# ──────────────────────────────────────────────

def skeleton_cpp(source: str, path: str) -> str:
    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "C/C++")]

    includes = [l.strip() for l in lines if re.match(r"^\s*#\s*include\s+[<\"]", l)]
    if includes:
        parts.append("\n[Includes]")
        for inc in includes[:15]:
            parts.append(f"  {inc}")

    patterns = [
        r"^\s*(?:class|struct|enum(?:\s+class)?)\s+\w+",
        r"^\s*(?:[\w:*&<>]+\s+)+[\w:~]+\s*\([^)]*\)\s*(?:const)?\s*(?:override|noexcept)?\s*(?:\{|;)",
        r"^\s*#\s*define\s+\w+",
    ]
    combined = re.compile("|".join(patterns))

    parts.append("\n[Declarations]")
    found = 0
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*"):
            continue
        if combined.match(stripped):
            sig = stripped.rstrip("{").rstrip()
            parts.append(f"  L{i}: {sig}")
            found += 1
    if found == 0:
        parts.append("  (no top-level declarations found)")

    return "\n".join(parts)


# ──────────────────────────────────────────────
# Rust (.rs)
# ──────────────────────────────────────────────

def skeleton_rust(source: str, path: str) -> str:
    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "Rust")]

    uses = [l.strip() for l in lines if re.match(r"^\s*(?:pub\s+)?use\s+", l)]
    if uses:
        parts.append("\n[Uses]")
        for u in uses[:15]:
            parts.append(f"  {u}")

    patterns = [
        r"^\s*(?:pub(?:\([\w:]+\))?\s+)?(?:async\s+)?fn\s+\w+",
        r"^\s*(?:pub(?:\([\w:]+\))?\s+)?struct\s+\w+",
        r"^\s*(?:pub(?:\([\w:]+\))?\s+)?enum\s+\w+",
        r"^\s*(?:pub(?:\([\w:]+\))?\s+)?trait\s+\w+",
        r"^\s*impl(?:\s+<[^>]+>)?\s+(?:\w+\s+for\s+)?\w+",
    ]
    combined = re.compile("|".join(patterns))

    parts.append("\n[Declarations]")
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if combined.match(stripped):
            sig = stripped.rstrip("{").rstrip()
            parts.append(f"  L{i}: {sig}")

    return "\n".join(parts)


# ──────────────────────────────────────────────
# Go (.go)
# ──────────────────────────────────────────────

def skeleton_go(source: str, path: str) -> str:
    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "Go")]

    pkg = [l.strip() for l in lines if l.startswith("package ")]
    if pkg:
        parts.append(f"\n[{pkg[0]}]")

    patterns = [
        r"^\s*func\s+(?:\([^)]+\)\s+)?\w+\s*\(",
        r"^\s*type\s+\w+\s+(?:struct|interface)",
    ]
    combined = re.compile("|".join(patterns))

    parts.append("\n[Declarations]")
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if combined.match(stripped):
            sig = stripped.rstrip("{").rstrip()
            parts.append(f"  L{i}: {sig}")

    return "\n".join(parts)


# ──────────────────────────────────────────────
# CSV / TSV Data Table (.csv, .tsv)
# ──────────────────────────────────────────────

def skeleton_csv(source: str, path: str) -> str:
    """Extract CSV structure: row count, columns, and first 5 sample rows."""
    delimiter = "\t" if path.endswith(".tsv") else ","
    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "CSV / Data Table")]

    try:
        reader = csv.reader(io.StringIO(source), delimiter=delimiter)
        rows = list(reader)
        if not rows:
            parts.append("\n(empty table)")
            return "\n".join(parts)

        headers = rows[0]
        num_cols = len(headers)
        num_rows = len(rows) - 1

        parts.append(f"\nDimensions: {num_rows:,} rows × {num_cols} columns")
        parts.append(f"Columns: {', '.join(headers[:20])}")
        if len(headers) > 20:
            parts.append(f"  (+{len(headers) - 20} more columns)")

        parts.append("\n[Sample Rows 1–5]")
        for i, row in enumerate(rows[1:6], 1):
            short_row = [c if len(c) <= 25 else c[:22] + "..." for c in row[:10]]
            parts.append(f"  Row {i}: {', '.join(short_row)}")

    except Exception as e:
        parts.append(f"\nError parsing CSV: {e}")
        parts.extend(lines[:20])

    return "\n".join(parts)


# ──────────────────────────────────────────────
# Markdown Document (.md, .markdown)
# ──────────────────────────────────────────────

def skeleton_markdown(source: str, path: str) -> str:
    """Extract table of contents and outline from Markdown file."""
    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "Markdown Document")]

    headers = []
    for i, line in enumerate(lines, 1):
        if line.startswith("#"):
            headers.append(f"  L{i}: {line}")

    if headers:
        parts.append("\n[Table of Contents / Outline]")
        parts.extend(headers[:30])
        if len(headers) > 30:
            parts.append(f"  (+{len(headers) - 30} more sections)")

    # Include first 25 lines of overview/content
    parts.append("\n[Document Overview]")
    non_empty_lines = [l for l in lines[:40] if not l.startswith("#") and l.strip()]
    for l in non_empty_lines[:15]:
        parts.append(f"  {l}")

    return "\n".join(parts)


# ──────────────────────────────────────────────
# JSON / Structured Config (.json, .yaml, .toml)
# ──────────────────────────────────────────────

def skeleton_json(source: str, path: str) -> str:
    lines = source.splitlines()
    total_lines = len(lines)
    parts = [file_header(path, total_lines, "JSON")]

    try:
        data = json.loads(source)
    except json.JSONDecodeError as e:
        parts.append(f"\n[Parse error] {e}")
        for line in lines[:30]:
            parts.append(f"  {line}")
        return "\n".join(parts)

    MAX_JSON_DEPTH = 3  # cap recursion so deeply nested JSON doesn't blow the char budget

    def _describe(value, depth=0) -> list[str]:
        indent = "  " * (depth + 1)
        result = []
        if isinstance(value, dict):
            for key in list(value.keys())[:25]:
                v = value[key]
                if isinstance(v, dict):
                    result.append(f"{indent}{key}: {{...}} ({len(v)} keys)")
                    if depth < MAX_JSON_DEPTH:
                        result.extend(_describe(v, depth + 1))
                elif isinstance(v, list):
                    item_type = type(v[0]).__name__ if v else "empty"
                    result.append(f"{indent}{key}: [...] ({len(v)} items, {item_type})")
                    if depth < MAX_JSON_DEPTH and v and isinstance(v[0], (dict, list)):
                        result.extend(_describe(v[0], depth + 1))
                elif isinstance(v, str):
                    short = v[:60].replace("\n", "\\n")
                    if len(v) > 60:
                        short += "..."
                    result.append(f'{indent}{key}: "{short}"')
                else:
                    result.append(f"{indent}{key}: {v}")
            remaining = len(value) - 25
            if remaining > 0:
                result.append(f"{indent}(+{remaining} more keys)")
        elif isinstance(value, list):
            result.append(f"{indent}Array with {len(value)} items")
            if value:
                result.append(f"{indent}First item type: {type(value[0]).__name__}")
                if depth < MAX_JSON_DEPTH and isinstance(value[0], (dict, list)):
                    result.extend(_describe(value[0], depth + 1))
        else:
            result.append(f"{indent}{type(value).__name__}: {str(value)[:100]}")
        return result

    parts.append("\n[Structure]")
    parts.extend(_describe(data))

    return "\n".join(parts)


# ──────────────────────────────────────────────
# Generic Text Fallback (.txt, note.txt, .log)
# ──────────────────────────────────────────────

def skeleton_generic(source: str, path: str, lang: str = "Plain Text") -> str:
    """Fallback: clean blank lines, show head & tail with omission count."""
    raw_lines = source.splitlines()
    total_lines = len(raw_lines)
    parts = [file_header(path, total_lines, lang)]

    head_count = 45
    tail_count = 15

    if total_lines <= head_count + tail_count:
        parts.append("")
        parts.extend(f"  {l}" for l in raw_lines)
    else:
        parts.append(f"\n[Beginning {head_count} lines]")
        for l in raw_lines[:head_count]:
            parts.append(f"  {l}")
        skipped = total_lines - head_count - tail_count
        parts.append(f"\n  ... ({skipped:,} lines omitted) ...\n")
        parts.append(f"[End {tail_count} lines]")
        for l in raw_lines[-tail_count:]:
            parts.append(f"  {l}")

    return "\n".join(parts)


# ──────────────────────────────────────────────
# Router: pick the right strategy by extension
# ──────────────────────────────────────────────

EXTENSION_MAP = {
    # Python
    ".py":       skeleton_python,
    ".pyw":      skeleton_python,
    # Jupyter Notebooks
    ".ipynb":    skeleton_ipynb,
    # C / C++
    ".c":        skeleton_cpp,
    ".cpp":      skeleton_cpp,
    ".cxx":      skeleton_cpp,
    ".cc":       skeleton_cpp,
    ".h":        skeleton_cpp,
    ".hpp":      skeleton_cpp,
    # Rust & Go
    ".rs":       skeleton_rust,
    ".go":       skeleton_go,
    # JavaScript / TypeScript
    ".js":       skeleton_js,
    ".mjs":      skeleton_js,
    ".cjs":      skeleton_js,
    ".ts":       skeleton_js,
    ".tsx":      skeleton_js,
    ".jsx":      skeleton_js,
    # Shell
    ".sh":       skeleton_shell,
    ".bash":     skeleton_shell,
    ".zsh":      skeleton_shell,
    ".fish":     skeleton_shell,
    # QML
    ".qml":      skeleton_qml,
    # Data & Tables
    ".csv":      skeleton_csv,
    ".tsv":      skeleton_csv,
    # Documents & Notes
    ".md":       skeleton_markdown,
    ".markdown": skeleton_markdown,
    # Config & Data
    ".json":     skeleton_json,
}


def read_file(path: str, max_chars: int = MAX_CHARS, full: bool = False) -> str:
    """Main entry point: read, skeletonize, and truncate a file."""
    path = os.path.expanduser(path)

    if not os.path.isfile(path):
        return f"Error: File not found — {path}"

    ext = Path(path).suffix.lower()

    # Safety: skip very large files (> 5 MB) — checked first so it applies
    # to every format, including PDF (previously PDF bypassed this entirely).
    file_size = os.path.getsize(path)
    if file_size > 5 * 1024 * 1024:
        return (
            f"Error: File too large ({file_size / 1024 / 1024:.1f} MB). "
            f"Only files under 5 MB are supported."
        )

    # Special handler for binary PDF files
    if ext == ".pdf":
        return truncate(skeleton_pdf(path), max_chars)

    # Read text content
    try:
        source = read_file_safe(path)
        if not source.strip():
            return f"── {os.path.basename(path)} ──\n(empty file)"
    except Exception as e:
        return f"Error reading file: {e}"

    # --full mode: return raw content with truncation
    if full:
        lines = source.splitlines()
        header = file_header(path, len(lines), ext.lstrip(".") or "text")
        return truncate(f"{header}\n\n{source}", max_chars)

    # Pick the skeletonizer
    skeletonizer = EXTENSION_MAP.get(ext, None)

    if skeletonizer:
        result = skeletonizer(source, path)
    else:
        result = skeleton_generic(source, path, ext.lstrip(".").upper() if ext else "Plain Text")

    return truncate(result, max_chars)


# ──────────────────────────────────────────────
# CLI entry point
# ──────────────────────────────────────────────

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("Usage: read-file.py <file_path> [--max-chars N] [--full]")
        print()
        print("Smart file reader that extracts structural skeletons from code/data/docs,")
        print("reducing token usage by 70-90% compared to reading raw content.")
        print()
        print("Supported formats: .py, .ipynb, .pdf, .js, .ts, .sh, .qml, .csv, .md, .json, .txt")
        print()
        print("Options:")
        print(f"  --max-chars N   Maximum output characters (default: {MAX_CHARS})")
        print("  --full          Return raw content instead of skeleton (still truncated)")
        sys.exit(0)

    file_path = sys.argv[1]
    max_chars = MAX_CHARS
    full = False

    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--max-chars" and i + 1 < len(args):
            try:
                max_chars = int(args[i + 1])
            except ValueError:
                pass
            i += 2
        elif args[i] == "--full":
            full = True
            i += 1
        else:
            i += 1

    print(read_file(file_path, max_chars=max_chars, full=full))


if __name__ == "__main__":
    main()