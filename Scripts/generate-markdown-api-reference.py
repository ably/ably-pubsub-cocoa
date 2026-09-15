#!/usr/bin/env python3
"""
Generate a Markdown API reference for the Ably Swift module.

Runs the full pipeline:
  1. swift build                 — compile the Ably module (SPM)
  2. swift symbolgraph-extract   — extract Swift symbol graph
  3. clang -extract-api          — extract ObjC symbol graph (for doc comments)
  4. Render Markdown             — merge symbols + render → api.md

Output: Docs/markdown-api-reference/api.md

Prerequisites:
  - Xcode (provides swift, clang, xcrun)
  - Python 3
"""

import json
import os
import re
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_json(path):
    with open(path) as f:
        return json.load(f)


def run(cmd):
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    subprocess.run(cmd, check=True)


def decl_text(symbol):
    """Get the full Swift declaration string."""
    frags = symbol.get("declarationFragments", [])
    return "".join(f.get("spelling", "") for f in frags)


def doc_comment(symbol):
    """Extract the doc comment text, or empty string."""
    doc = symbol.get("docComment", {})
    if not doc:
        return ""
    lines = doc.get("lines", [])
    return "\n".join(line.get("text", "") for line in lines).strip()


def is_nodoc(symbol):
    stripped = doc_comment(symbol).strip()
    return stripped == ":nodoc:" or stripped.startswith(":nodoc:")


def kind_sort_order(kind):
    order = {
        "Initializer": 0,
        "Type Property": 1,
        "Type Method": 2,
        "Instance Property": 3,
        "Instance Method": 4,
        "Case": 5,
    }
    return order.get(kind, 99)


# ---------------------------------------------------------------------------
# Symbol loading / filtering
# ---------------------------------------------------------------------------

def load_internal_ids(internal_header_path):
    """Parse AblyInternal.h to get imported header filenames.

    Symbols declared in these headers are public API intended only for
    Ably-authored SDKs and should be excluded from documentation.
    """
    header_basenames = set()
    if internal_header_path:
        with open(internal_header_path) as f:
            for line in f:
                m = re.match(r'#import\s+<AblyPubSubDevice/(.+\.h)>', line.strip())
                if m:
                    header_basenames.add(m.group(1))
    return header_basenames


def load_objc_nodoc_ids(objc_data):
    """Get precise IDs of symbols marked :nodoc: in the ObjC symbol graph."""
    ids = set()
    for s in objc_data.get("symbols", []):
        doc = s.get("docComment", {})
        if doc:
            text = " ".join(line.get("text", "") for line in doc.get("lines", []))
            if text.strip().startswith(":nodoc:"):
                ids.add(s["identifier"]["precise"])
    return ids


# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------

def render_markdown(swift_symbol_paths, objc_symbol_path, internal_header_path,
                    output_path):
    """Load symbol graphs, merge, filter, and render to Markdown."""

    # Load and merge all Swift symbol graph files
    all_symbols = []
    all_relationships = []
    for path in swift_symbol_paths:
        data = load_json(path)
        all_symbols.extend(data.get("symbols", []))
        all_relationships.extend(data.get("relationships", []))

    # Load ObjC symbol graph and merge doc comments into Swift symbols
    # (swift symbolgraph-extract doesn't carry ObjC doc comments)
    objc_data = load_json(objc_symbol_path)
    objc_docs = {}
    for s in objc_data.get("symbols", []):
        doc = s.get("docComment")
        if doc:
            objc_docs[s["identifier"]["precise"]] = doc
    merged = 0
    for s in all_symbols:
        sid = s["identifier"]["precise"]
        if not s.get("docComment") and sid in objc_docs:
            s["docComment"] = objc_docs[sid]
            merged += 1
    print(f"Merged {merged} doc comments from ObjC symbol graph")

    # Index symbols by precise identifier
    sym_by_id = {}
    for s in all_symbols:
        sym_by_id[s["identifier"]["precise"]] = s

    # Load :nodoc: IDs from ObjC symbol graph (these don't carry into Swift)
    objc_nodoc = load_objc_nodoc_ids(objc_data)

    # Exclude symbols declared in AblyInternal.h-imported headers
    internal_headers = load_internal_ids(internal_header_path)
    exclude_ids = set()
    if internal_headers:
        for s in objc_data.get("symbols", []):
            uri = s.get("location", {}).get("uri", "")
            if uri:
                basename = uri.rsplit("/", 1)[-1]
                if basename in internal_headers:
                    sid = s["identifier"]["precise"]
                    if sid in sym_by_id:
                        exclude_ids.add(sid)

    for nid in exclude_ids:
        del sym_by_id[nid]
    if exclude_ids:
        print(f"Excluded {len(exclude_ids)} AblyInternal symbols")

    # Track which symbols are :nodoc:
    nodoc_ids = objc_nodoc | {sid for sid, s in sym_by_id.items() if is_nodoc(s)}

    # Build relationship maps
    members_of = defaultdict(list)
    requirements_of = defaultdict(list)
    conforms_to = defaultdict(list)
    inherits_from = defaultdict(list)

    for r in all_relationships:
        src = r["source"]
        tgt = r["target"]
        kind = r["kind"]

        if src in nodoc_ids or tgt in nodoc_ids:
            continue

        if kind == "memberOf":
            members_of[tgt].append(src)
        elif kind == "requirementOf":
            requirements_of[tgt].append(src)
        elif kind == "conformsTo":
            conforms_to[src].append(tgt)
        elif kind == "inheritsFrom":
            inherits_from[src].append(tgt)

    # Identify top-level types
    top_level_kinds = {"Class", "Protocol", "Enumeration", "Structure", "Type Alias"}
    top_level_symbols = {}
    for sid, s in sym_by_id.items():
        kind = s.get("kind", {}).get("displayName", "")
        if kind in top_level_kinds:
            top_level_symbols[sid] = s

    # Collect top-level functions
    global_symbols = {}
    for sid, s in sym_by_id.items():
        kind = s.get("kind", {}).get("displayName", "")
        if kind in {"Function", "Global Variable"}:
            global_symbols[sid] = s

    # Recursive protocol member collection
    def get_protocol_members(proto_id, visited=None):
        if visited is None:
            visited = set()
        if proto_id in visited:
            return []
        visited.add(proto_id)
        members = []
        for mid in requirements_of.get(proto_id, []):
            if mid in sym_by_id:
                members.append((mid, proto_id))
        for mid in members_of.get(proto_id, []):
            if mid in sym_by_id:
                members.append((mid, proto_id))
        for parent_proto in conforms_to.get(proto_id, []):
            members.extend(get_protocol_members(parent_proto, visited))
        return members

    # Group top-level symbols by category
    classes, protocols, enums, structs, type_aliases = [], [], [], [], []
    for sid, s in sorted(top_level_symbols.items(),
                         key=lambda x: x[1].get("names", {}).get("title", "")):
        kind = s.get("kind", {}).get("displayName", "")
        {"Class": classes, "Protocol": protocols, "Enumeration": enums,
         "Structure": structs, "Type Alias": type_aliases}[kind].append((sid, s))

    # --- Build Markdown ---
    lines = []
    lines.append("# Ably SDK \u2014 Swift Public API Reference\n")
    lines.append("This document describes the public Swift API surface of the "
                 "`AblyPubSubDevice` module (ably-cocoa).\n")
    lines.append("---\n")

    # Table of Contents
    lines.append("## Table of Contents\n")
    for heading, items in [("Classes", classes), ("Protocols", protocols),
                           ("Enumerations", enums), ("Structures", structs),
                           ("Type Aliases", type_aliases)]:
        if items:
            lines.append(f"### {heading}\n")
            for sid, s in items:
                name = s["names"]["title"]
                lines.append(f"- [{name}](#{name.lower()})")
            lines.append("")
    lines.append("---\n")

    def render_type(sid, s, section_heading_level="##"):
        name = s["names"]["title"]
        kind = s.get("kind", {}).get("displayName", "")
        decl = decl_text(s)
        doc = doc_comment(s)

        lines.append(f"{section_heading_level} {name}\n")
        lines.append(f"```swift\n{decl}\n```\n")

        if sid in nodoc_ids or not doc or doc.startswith(":nodoc:"):
            lines.append("*Not documented.*\n")
        else:
            lines.append(f"{doc}\n")

        # Conformances and inheritance
        conformances = [sym_by_id[pid]["names"]["title"]
                        for pid in conforms_to.get(sid, []) if pid in sym_by_id]
        if conformances:
            lines.append(f"**Conforms to:** {', '.join(conformances)}\n")

        parents = [sym_by_id[pid]["names"]["title"]
                   for pid in inherits_from.get(sid, []) if pid in sym_by_id]
        if parents:
            lines.append(f"**Inherits from:** {', '.join(parents)}\n")

        # Direct members
        direct_member_ids = set(members_of.get(sid, []))
        if kind == "Protocol":
            direct_member_ids |= set(requirements_of.get(sid, []))

        # Inherited members (from protocols, for classes only)
        inherited_members = {}
        if kind == "Class":
            direct_decls = {decl_text(sym_by_id[mid])
                           for mid in direct_member_ids if mid in sym_by_id}
            for proto_id in conforms_to.get(sid, []):
                for mid, source_proto_id in get_protocol_members(proto_id):
                    if (mid not in direct_member_ids
                            and mid not in inherited_members):
                        m = sym_by_id.get(mid)
                        if m and decl_text(m) not in direct_decls:
                            inherited_members[mid] = source_proto_id

        # Group by kind
        all_member_ids = direct_member_ids | set(inherited_members.keys())
        members_by_kind = defaultdict(list)
        for mid in all_member_ids:
            m = sym_by_id.get(mid)
            if not m:
                continue
            mkind = m.get("kind", {}).get("displayName", "")
            members_by_kind[mkind].append((mid, m, mid in inherited_members))

        for mkind in members_by_kind:
            members_by_kind[mkind].sort(
                key=lambda x: x[1].get("names", {}).get("title", ""))

        rendered_kinds = sorted(members_by_kind.keys(),
                                key=lambda k: kind_sort_order(k))

        for mkind in rendered_kinds:
            members = members_by_kind[mkind]
            if not members:
                continue

            kind_plural = {
                "Instance Property": "Instance Properties",
                "Type Property": "Type Properties",
                "Case": "Cases",
            }.get(mkind, mkind + ("es" if mkind.endswith("s") else "s"))

            lines.append(f"### {kind_plural}\n")

            for mid, m, is_inherited in members:
                mdecl = decl_text(m)
                mdoc = doc_comment(m)
                mname = m["names"]["title"]

                inherited_marker = ""
                if is_inherited:
                    source_proto_id = inherited_members.get(mid)
                    if source_proto_id:
                        proto = sym_by_id.get(source_proto_id)
                        if proto:
                            inherited_marker = (
                                f" *(from {proto['names']['title']})*")

                lines.append(f"#### `{mname}`{inherited_marker}\n")
                lines.append(f"```swift\n{mdecl}\n```\n")

                if mid in nodoc_ids or not mdoc or mdoc.startswith(":nodoc:"):
                    lines.append("*Not documented.*\n")
                else:
                    lines.append(f"{mdoc}\n")

            lines.append("")

        lines.append("---\n")

    # Render each category
    for heading, items in [("Classes", classes), ("Protocols", protocols),
                           ("Enumerations", enums), ("Structures", structs)]:
        if items:
            lines.append(f"## {heading}\n")
            for sid, s in items:
                render_type(sid, s, "##")

    if type_aliases:
        lines.append("## Type Aliases\n")
        for sid, s in type_aliases:
            name = s["names"]["title"]
            decl = decl_text(s)
            doc = doc_comment(s)
            lines.append(f"### {name}\n")
            lines.append(f"```swift\n{decl}\n```\n")
            if doc and not doc.startswith(":nodoc:"):
                lines.append(f"{doc}\n")
        lines.append("---\n")

    global_funcs = [(sid, s) for sid, s in global_symbols.items()
                    if s.get("kind", {}).get("displayName") == "Function"]
    if global_funcs:
        lines.append("## Global Functions\n")
        for sid, s in sorted(global_funcs, key=lambda x: x[1]["names"]["title"]):
            name = s["names"]["title"]
            decl = decl_text(s)
            doc = doc_comment(s)
            lines.append(f"### {name}\n")
            lines.append(f"```swift\n{decl}\n```\n")
            if doc and not doc.startswith(":nodoc:"):
                lines.append(f"{doc}\n")
        lines.append("---\n")

    # Write output
    content = "\n".join(lines)
    with open(output_path, "w") as f:
        f.write(content)

    # Stats
    print(f"Generated {output_path}")
    print(f"  {len(classes)} classes, {len(protocols)} protocols, "
          f"{len(enums)} enums, {len(structs)} structs, "
          f"{len(type_aliases)} type aliases")
    print(f"  {len(global_funcs)} global functions")
    print(f"  {len(sym_by_id)} total symbols "
          f"(after filtering {len(nodoc_ids)} :nodoc:)")


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def main():
    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent
    os.chdir(repo_dir)

    output_dir = Path("Docs/markdown-api-reference")
    output_file = output_dir / "api.md"

    with tempfile.TemporaryDirectory() as work_dir:
        work = Path(work_dir)

        # Auto-detect SDK path and target triple
        sdk_path = subprocess.check_output(
            ["xcrun", "--show-sdk-path"], text=True).strip()
        target_info = json.loads(subprocess.check_output(
            ["swift", "-print-target-info"], text=True))
        target = target_info["target"]["unversionedTriple"]
        build_dir = f".build/{target}/debug"

        print(f"SDK path: {sdk_path}")
        print(f"Target: {target}")
        print(f"Build dir: {build_dir}")

        # Step 1: Build the Ably module
        print("\n==> Building Ably module...")
        run(["swift", "build"])

        # Step 2: Extract Swift symbol graph
        print("\n==> Extracting Swift symbol graph...")
        run([
            "swift", "symbolgraph-extract",
            "-module-name", "AblyPubSubDevice",
            "-I", "Source/include",
            "-I", build_dir,
            "-I", f"{build_dir}/AblyPubSubDevice.build",
            "-sdk", sdk_path,
            "-target", target,
            "-output-dir", str(work),
            "-minimum-access-level", "public",
        ])

        swift_symbol_files = sorted(work.glob("Ably*.symbols.json"))
        print("Swift symbol graph files:")
        for f in swift_symbol_files:
            print(f"  {f}")

        # Step 3: Extract ObjC symbol graph (for doc comments)
        print("\n==> Extracting ObjC symbol graph...")
        objc_path = work / "objc-symbols.json"
        header_files = sorted(Path("Source/include/AblyPubSubDevice").glob("*.h"))
        run([
            "clang", "-extract-api",
            "-x", "objective-c-header",
            "-isysroot", sdk_path,
            "-I", "Source/include",
            "-o", str(objc_path),
        ] + [str(h) for h in header_files])

        # Step 4: Generate Markdown
        print("\n==> Generating Markdown API reference...")
        output_dir.mkdir(parents=True, exist_ok=True)

        render_markdown(
            swift_symbol_paths=[str(f) for f in swift_symbol_files],
            objc_symbol_path=str(objc_path),
            internal_header_path="Source/include/AblyPubSubDevice/AblyInternal.h",
            output_path=str(output_file),
        )

        print(f"\n==> Done! Output: {output_file}")


if __name__ == "__main__":
    main()
