#!/usr/bin/env python3
"""Converts Ember's Markdown user guides to standalone HTML (Python standard library only).

Usage: md2html.py <input.md> <output.html> <lang>

Supports the subset the guides use: headings (with GitHub-style anchors, so in-page links work),
paragraphs, horizontal rules, fenced code, tables, ordered/unordered lists with one nesting level
and continuation lines, blockquotes, and inline code / bold / italic / links.
"""
import html
import re
import sys

LIST_ITEM = re.compile(r"^([-*]|\d+\.)\s+(.*)$")
NESTED_ITEM = re.compile(r"^\s{2,}([-*]|\d+\.)\s+(.*)$")

STYLE = """
:root { color-scheme: light dark; --accent: #e2611c; --rule: rgba(128,128,128,.35); --tint: rgba(128,128,128,.12); }
body { font: 13px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; color: CanvasText;
       background: transparent; max-width: 760px; margin: 0 auto; padding: 8px 16px 32px; }
h1 { font-size: 22px; margin: 4px 0 8px; }
h2 { font-size: 17px; margin: 28px 0 8px; color: var(--accent); }
h3 { font-size: 14px; margin: 20px 0 6px; }
p, ul, ol { margin: 8px 0; }
li { margin: 3px 0; }
a { color: var(--accent); }
hr { border: 0; border-top: 1px solid var(--rule); margin: 22px 0; }
code { font: 12px ui-monospace, Menlo, monospace; background: var(--tint); padding: 1px 4px; border-radius: 4px; }
pre { background: var(--tint); padding: 10px 12px; border-radius: 8px; overflow-x: auto; }
pre code { background: none; padding: 0; font-size: 11.5px; line-height: 1.35; }
table { border-collapse: collapse; margin: 10px 0; width: 100%; }
th, td { border: 1px solid var(--rule); padding: 5px 8px; text-align: left; vertical-align: top; }
th { background: var(--tint); }
blockquote { margin: 12px 0; padding: 6px 12px; border-left: 3px solid var(--accent); background: var(--tint);
             border-radius: 0 6px 6px 0; }
blockquote p { margin: 0; }
"""


def slug(text: str) -> str:
    """GitHub-style heading anchor: lowercase, drop punctuation, spaces become hyphens."""
    text = re.sub(r"[^\w\- ]", "", text.strip().lower())
    return text.replace(" ", "-")


def inline(text: str) -> str:
    out = []
    for part in re.split(r"(`[^`]+`)", text):
        if len(part) > 1 and part.startswith("`") and part.endswith("`"):
            out.append("<code>" + html.escape(part[1:-1]) + "</code>")
            continue
        part = html.escape(part, quote=False)
        part = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', part)
        part = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", part)
        part = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", part)
        out.append(part)
    return "".join(out)


def table(rows):
    def cells(row):
        return [c.strip() for c in row.strip().strip("|").split("|")]

    header = cells(rows[0])
    body = rows[2:] if len(rows) > 1 and re.fullmatch(r"\|?[\s:|-]+\|?", rows[1]) else rows[1:]
    out = ["<table>"]
    if any(header):
        out.append("<thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in header) + "</tr></thead>")
    out.append("<tbody>")
    for row in body:
        out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in cells(row)) + "</tr>")
    out.append("</tbody></table>")
    return "".join(out)


def parse_list(lines, i, out):
    ordered = LIST_ITEM.match(lines[i]).group(1)[0].isdigit()
    items = []  # {"text": [...], "sub": [[...], ...], "sub_ordered": bool}
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            break
        top = LIST_ITEM.match(line)
        nested = NESTED_ITEM.match(line)
        if top:
            items.append({"text": [top.group(2)], "sub": [], "sub_ordered": False})
        elif nested and items:
            items[-1]["sub"].append([nested.group(2)])
            items[-1]["sub_ordered"] = nested.group(1)[0].isdigit()
        elif line.startswith(" ") and items:  # continuation of the previous item
            target = items[-1]["sub"][-1] if items[-1]["sub"] else items[-1]["text"]
            target.append(line.strip())
        else:
            break
        i += 1

    tag = "ol" if ordered else "ul"
    out.append(f"<{tag}>")
    for item in items:
        out.append("<li>" + inline(" ".join(item["text"])))
        if item["sub"]:
            sub_tag = "ol" if item["sub_ordered"] else "ul"
            out.append(f"<{sub_tag}>" + "".join(f"<li>{inline(' '.join(s))}</li>" for s in item["sub"]) + f"</{sub_tag}>")
        out.append("</li>")
    out.append(f"</{tag}>")
    return i


def convert(markdown: str) -> tuple[str, str]:
    lines = markdown.split("\n")
    out, paragraph = [], []
    title = "User Guide"

    def flush():
        if paragraph:
            out.append("<p>" + inline(" ".join(l.strip() for l in paragraph)) + "</p>")
            paragraph.clear()

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped.startswith("```"):
            flush()
            j, code = i + 1, []
            while j < len(lines) and not lines[j].strip().startswith("```"):
                code.append(lines[j])
                j += 1
            out.append("<pre><code>" + html.escape("\n".join(code)) + "</code></pre>")
            i = j + 1
        elif not stripped:
            flush()
            i += 1
        elif heading := re.match(r"^(#{1,6})\s+(.*)$", line):
            flush()
            level, text = len(heading.group(1)), heading.group(2).strip()
            if level == 1:
                title = re.sub(r"[*`]", "", text)
            out.append(f'<h{level} id="{html.escape(slug(text))}">{inline(text)}</h{level}>')
            i += 1
        elif re.fullmatch(r"-{3,}", stripped):
            flush()
            out.append("<hr>")
            i += 1
        elif stripped.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(lines[i].strip())
                i += 1
            out.append(table(rows))
        elif stripped.startswith(">"):
            flush()
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            out.append("<blockquote><p>" + inline(" ".join(quote)) + "</p></blockquote>")
        elif LIST_ITEM.match(line):
            flush()
            i = parse_list(lines, i, out)
        else:
            paragraph.append(line)
            i += 1
    flush()
    return title, "\n".join(out)


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    source, destination, lang = sys.argv[1:]
    with open(source, encoding="utf-8") as f:
        title, body = convert(f.read())
    page = (
        f'<!DOCTYPE html>\n<html lang="{html.escape(lang)}">\n<head>\n<meta charset="utf-8">\n'
        f'<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"<title>{html.escape(title)}</title>\n<style>{STYLE}</style>\n</head>\n<body>\n{body}\n</body>\n</html>\n"
    )
    with open(destination, "w", encoding="utf-8") as f:
        f.write(page)


if __name__ == "__main__":
    main()
