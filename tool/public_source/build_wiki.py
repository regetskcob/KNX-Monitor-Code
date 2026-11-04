#!/usr/bin/env python3
"""Builds the GitHub wiki of the public code repository from docs/.

    build_wiki.py <snapshot tree> <wiki checkout>

docs/ stays the source: it is reviewed and versioned with the code. The wiki
is regenerated from the public snapshot on every sync, so private documents
never reach it. Each docs/*.md becomes a page named after its first heading,
docs/README.md becomes Home, and its sections become the sidebar. Links to
other docs become wiki links, links to code point to the file on GitHub.
"""
import re
import sys
from pathlib import Path

REPO = "https://github.com/regetskcob/KNX-Monitor-Code"
BLOB = f"{REPO}/blob/main/"
TREE = f"{REPO}/tree/main/"

LINK = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)\)")


def page_title(md: Path) -> str:
    if md.name == "README.md":
        return "Home"
    for line in md.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            return line[2:].replace("`", "").strip()
    return md.stem


def page_name(title: str) -> str:
    # Only characters that survive in a Markdown link target and a wiki URL.
    name = re.sub(r"[^\w\s.-]", "", title)
    return re.sub(r"\s+", "-", name).strip("-")


def rewrite(text: str, pages: dict, src: Path, root: Path) -> str:
    def repl(m: re.Match) -> str:
        bang, label, target = m.groups()
        if re.match(r"^[a-z]+:", target) or target.startswith("#"):
            return m.group(0)
        path, _, anchor = target.partition("#")
        resolved = (src.parent / path).resolve()
        anchor = f"#{anchor}" if anchor else ""
        if resolved in pages:
            return f"{bang}[{label}]({pages[resolved]}{anchor})"
        rel = resolved.relative_to(root).as_posix()
        base = TREE if resolved.is_dir() else BLOB
        suffix = "?raw=true" if bang else ""
        return f"{bang}[{label}]({base}{rel}{suffix}{anchor})"

    out, fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence
        out.append(line if fence else LINK.sub(repl, line))
    return "\n".join(out) + "\n"


def sidebar(home: str, titles: dict) -> str:
    """Section headings and links of the docs index, without the prose."""
    lines = ["**[Home](Home)**", ""]
    for line in home.splitlines():
        if line.startswith("## "):
            lines += ["", f"**{line[3:].strip()}**", ""]
        else:
            m = re.match(r"^- \[[^\]]*\]\(([^)]+)\)", line)
            name = m.group(1).split("#")[0] if m else ""
            if name in titles:
                lines.append(f"- [{titles[name]}]({m.group(1)})")
    return "\n".join(lines).strip() + "\n"


def main() -> None:
    root, wiki = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
    docs = root / "docs"
    sources = sorted(docs.glob("*.md"))
    titles = {page_name(page_title(md)): page_title(md) for md in sources}
    pages = {md.resolve(): page_name(page_title(md)) for md in sources}

    for old in wiki.glob("*.md"):
        old.unlink()
    note = (
        f"_This wiki is generated from [docs/]({TREE}docs) in the code repository. "
        "Changes go there as a pull request, see "
        f"[CONTRIBUTING.md]({BLOB}CONTRIBUTING.md)._\n"
    )
    for md in sources:
        body = rewrite(md.read_text(encoding="utf-8"), pages, md, root)
        if md.name == "README.md":
            body = re.sub(r"^# .*\n", "# KNX Monitor\n", body, count=1)
            (wiki / "_Sidebar.md").write_text(sidebar(body, titles), encoding="utf-8")
        else:
            # GitHub shows the page name as the title already.
            body = re.sub(r"^# .*\n+", "", body, count=1)
        (wiki / f"{pages[md.resolve()]}.md").write_text(body, encoding="utf-8")
    (wiki / "_Footer.md").write_text(note, encoding="utf-8")


if __name__ == "__main__":
    main()
