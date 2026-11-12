#!/usr/bin/env python3
"""Report-only linter for reader-friendly docs (.md and .html). Stdlib only.

Usage: check_doc.py FILE [FILE...] [--strict] [--first-screen] [--json]
"""
import json
import re
import sys
from collections import defaultdict
from html.parser import HTMLParser

GENERIC = {"results", "overview", "details", "introduction", "background", "summary",
           "discussion", "analysis", "findings", "data", "setup", "notes", "misc", "conclusion"}
BANNED = ["robust", "seamless", "seamlessly", "leverage", "comprehensive", "cutting-edge",
          "delve", "utilize", "holistic", "game-changer", "it is important to note",
          "it's worth noting", "in order to", "just", "simply", "obviously", "basically"]
ACRO_OK = set("HTML CSS JS API URL CPU GPU JSON SQL HTTP HTTPS SSH PDF UI CLI CI OS ID OK PR TOC "
              "LLM AI USD UTC YAML MD PNG SVG AND OR NOT TODO FAQ README PASS PASSED FAILED".split())
NUM_RE = re.compile(r"^-?\d+(?:\.\d+)?$")
ANSWER_H = re.compile(r"summary|tl;?dr|answer|bluf", re.I)
NUMBERING = re.compile(r"^\s*(?:\d+(?:\.\d+)*\.?|[A-Z]\.\d*(?:\.\d+)*)\s+")
WS = re.compile(r"\s+")


class Doc:
    def __init__(self, kind):
        self.kind = kind
        self.headings = []     # (level, text, line, in_appx)
        self.paras = []        # (words, line)
        self.lists = []        # list of [(words, line)]
        self.deep = []         # lines where nesting > 2
        self.tables = []       # (line, rows)
        self.bold = 0
        self.prose_words = 0
        self.text = []         # non-code text chunks
        self.figures = []      # [line, has_title]
        self.answer_ok = False
        self.has_meta = False
        self.labels = []       # details/summary labels (all)
        self.appx_labels = []
        self.title = ""
        self.meta = ""
        self.answer = ""
        self.md_lines = []
        self.collapsed = set()   # lines of tables inside <details>


def words(s):
    return len(s.split())


class HP(HTMLParser):
    VOID = {"br", "img", "meta", "link", "hr", "input", "col", "area", "base", "wbr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.d = Doc("html")
        self.stack = []   # (tag, classes)
        self.bufs = []    # dicts: kind, depth, parts, line, extra
        self.appx_latched = False
        self.h2count = 0

    def inside(self, *tags):
        return any(t in tags for t, _ in self.stack)

    def in_class(self, c):
        return any(c in cl for _, cl in self.stack)

    def open_buf(self, kind, **extra):
        b = dict(kind=kind, depth=len(self.stack), parts=[], line=self.getpos()[0], **extra)
        self.bufs.append(b)
        return b

    def handle_starttag(self, tag, attrs):
        cl = set((dict(attrs).get("class") or "").split())
        line = self.getpos()[0]
        if tag in self.VOID:
            return
        self.stack.append((tag, cl))
        if tag in ("p", "li", "div", "tr", "h1", "h2", "h3", "h4", "summary"):
            for b in self.bufs:
                if b["kind"] == "answer":
                    b["parts"].append("\n")
        if tag == "span":
            for b in self.bufs:
                if b["kind"] == "meta" and b["parts"]:
                    b["parts"].append(" · ")
        if re.fullmatch(r"h[1-6]", tag):
            self.open_buf("heading", level=int(tag[1]), appx=self.appx_latched or self.in_class("appx"))
            if tag == "h2":
                self.h2count += 1
        elif tag == "p" and not self.inside("table"):
            self.open_buf("para", coll=self.inside("details"))
        elif tag in ("ul", "ol"):
            depth = sum(1 for t, _ in self.stack if t in ("ul", "ol"))
            if depth > 2:
                self.d.deep.append(line)
            self.open_buf("list", items=[])
        elif tag == "li":
            self.open_buf("li")
        elif tag == "table":
            self.open_buf("table", rows=[], coll=self.inside("details"))
        elif tag == "tr":
            self.open_buf("row", cells=[])
        elif tag in ("td", "th"):
            self.open_buf("cell")
        elif tag in ("strong", "b"):
            if not self.inside("table", "summary") and not any(
                    re.fullmatch(r"h[1-6]", t) for t, _ in self.stack):
                self.d.bold += 1
        elif tag == "figure":
            self.d.figures.append([line, False])
        elif tag == "summary":
            self.open_buf("summary", appx=self.in_class("appx"))
        if "chart-title" in cl and self.d.figures:
            self.d.figures[-1][1] = True
        if "meta" in cl:
            self.d.has_meta = True
            self.open_buf("meta")
        if "answer" in cl:
            if self.h2count < 2:
                self.d.answer_ok = True
            self.open_buf("answer")
        if "lbl" in cl and self.inside("summary"):
            self.open_buf("lbl", appx=self.in_class("appx"))

    def handle_endtag(self, tag):
        if tag in self.VOID:
            return
        idx = None
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                idx = i
                break
        if idx is None:
            return
        del self.stack[idx:]
        n = len(self.stack)
        while self.bufs and self.bufs[-1]["depth"] > n:
            self.fin(self.bufs.pop())

    def fin(self, b):
        text = WS.sub(" ", "".join(b["parts"])).strip()
        k = b["kind"]
        d = self.d
        if k == "heading":
            if b["level"] == 1 and not d.title:
                d.title = text
            if text.lower().startswith("appendix"):
                self.appx_latched = True
            d.headings.append((b["level"], text, b["line"], b["appx"]))
            if b["level"] == 2 and ANSWER_H.search(text) and self.h2count <= 2:
                d.answer_ok = True
        elif k == "para":
            d.paras.append((words(text), b["line"], b["coll"]))
        elif k == "li":
            for p in reversed(self.bufs):
                if p["kind"] == "list":
                    p["items"].append((words(text), b["line"]))
                    break
        elif k == "list":
            if b["items"]:
                d.lists.append(b["items"])
        elif k == "cell":
            for p in reversed(self.bufs):
                if p["kind"] == "row":
                    p["cells"].append(text)
                    break
        elif k == "row":
            for p in reversed(self.bufs):
                if p["kind"] == "table":
                    p["rows"].append(b["cells"])
                    break
        elif k == "table":
            d.tables.append((b["line"], b["rows"]))
            if b["coll"]:
                d.collapsed.add(b["line"])
        elif k == "meta":
            d.meta = text
        elif k == "answer":
            d.answer = "\n".join(l.strip() for l in "".join(b["parts"]).split("\n") if l.strip())
            d.answer = re.sub(r"[ \t]+", " ", d.answer)
        elif k == "lbl":
            d.labels.append(text)
            if b["appx"]:
                d.appx_labels.append(text)

    def handle_data(self, data):
        if self.inside("script", "style", "head", "title"):
            return
        for b in self.bufs:
            b["parts"].append(data)
        if self.inside("pre", "code"):
            return
        self.d.text.append(data)
        if not self.inside("table", "summary") and not any(
                re.fullmatch(r"h[1-6]", t) for t, _ in self.stack):
            self.d.prose_words += words(data)


def parse_html(src):
    p = HP()
    p.feed(src)
    p.close()
    while p.bufs:
        p.fin(p.bufs.pop())
    return p.d


MD_LIST = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)")
MD_HEAD = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
INLINE_CODE = re.compile(r"`[^`]*`")
TAG = re.compile(r"<[^>]+>")


def parse_md(src):
    d = Doc("md")
    lines = src.splitlines()
    d.md_lines = lines
    fence = False
    para, para_line = [], 0
    indents = []
    cur_list, appx = None, False
    h2count = 0
    first_h1 = None
    last_row = -1

    def flush():
        nonlocal para
        if para:
            t = " ".join(para)
            d.paras.append((words(INLINE_CODE.sub("", t)), para_line, False))
            if re.match(r"\*\*(Answer|Bottom line)", t) and h2count < 2:
                d.answer_ok = True
        para = []

    def prose(s):
        s = INLINE_CODE.sub("", s)
        d.bold += len(re.findall(r"\*\*[^*\n]+\*\*|__[^_\n]+__", s))
        d.prose_words += words(s)

    for n, raw in enumerate(lines, 1):
        s = raw.strip()
        if s.startswith("```") or s.startswith("~~~"):
            flush()
            fence = not fence
            continue
        if fence:
            continue
        if not s:
            flush()
            cur_list = None
            indents = []
            continue
        d.text.append(INLINE_CODE.sub("", raw) + "\n")
        m = MD_HEAD.match(s) if not raw.startswith("    ") else None
        if m:
            flush()
            cur_list = None
            lvl, text = len(m.group(1)), TAG.sub("", m.group(2))
            if lvl == 1 and first_h1 is None:
                first_h1 = n
                d.title = text
            if text.lower().startswith("appendix"):
                appx = True
            if lvl == 2:
                h2count += 1
                if ANSWER_H.search(text) and h2count <= 2:
                    d.answer_ok = True
            d.headings.append((lvl, text, n, appx))
            continue
        if re.match(r"!!!\s+(abstract|summary|success)\b", s) and h2count < 2:
            d.answer_ok = True
        if s.startswith("|"):
            flush()
            cells = [c.strip() for c in s.strip("|").split("|")]
            if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                continue
            if last_row != n - 1:
                d.tables.append((n, []))
            d.tables[-1][1].append(cells)
            last_row = n
            continue
        m = MD_LIST.match(raw)
        if m:
            flush()
            ind = len(m.group(1).replace("\t", "    "))
            while indents and indents[-1] > ind:
                indents.pop()
            if not indents or indents[-1] < ind:
                indents.append(ind)
            if len(indents) > 2:
                d.deep.append(n)
            body = m.group(3)
            prose(body)
            if len(indents) == 1:
                if cur_list is None:
                    cur_list = []
                    d.lists.append(cur_list)
                cur_list.append((words(INLINE_CODE.sub("", body)), n))
            continue
        if cur_list is not None and raw.startswith((" ", "\t")):
            continue
        if s.startswith("!!!") or s.startswith("???"):
            flush()
            continue
        if not para:
            para_line = n
        para.append(s)
        prose(s)
    flush()
    return d


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def find_lint(d, src_text):
    F = []

    def add(level, rule, msg, where=""):
        F.append((level, rule, msg, where))

    hs = d.headings
    # 1 answer-first
    if not d.answer_ok:
        add("warn", "answer-first", "no answer block (BLUF/summary) before the 2nd h2")
    # 2 meta
    if d.kind == "html":
        if not d.has_meta:
            add("info", "meta", "no .meta audience/status line")
    else:
        h1 = next((h[2] for h in hs if h[0] == 1), None)
        ok = False
        if h1:
            for l in d.md_lines[h1:h1 + 6]:
                if re.search(r"\b(Audience|For|Status|Updated)\b", l) or re.match(r"^\s*[*_].*·.*[*_]\s*$", l):
                    ok = True
        if not ok:
            add("info", "meta", "no Audience/For/Status/Updated line within 6 lines of the h1")
    # 3 generic-heading
    for lvl, text, line, in_appx in hs:
        if lvl not in (2, 3) or in_appx or text.lower().startswith("appendix"):
            continue
        core = NUMBERING.sub("", text + " ").strip().rstrip(":.").lower()
        if core in GENERIC:
            add("warn", "generic-heading", f'"{text}" names a topic, not a claim', f"line {line}")
    # 4 long-paragraph
    for w, line, coll in d.paras:
        if w > 120:
            add("info" if coll else "warn", "long-paragraph",
                f"{w}-word paragraph" + (" (inside collapsed details)" if coll else ""), f"line {line}")
    # 5 deep-nesting
    for line in d.deep:
        add("warn", "deep-nesting", "list nested deeper than 2", f"line {line}")
    # 6 fragment-bullets
    for items in d.lists:
        run = []
        for w, line in items + [(99, 0)]:
            if w <= 6:
                run.append(line)
                continue
            if len(run) >= 6:
                add("info", "fragment-bullets", f"{len(run)} consecutive short bullets", f"line {run[0]}")
            run = []
    # 7 wide-table
    for tl, rows in d.tables:
        cols = max((len(r) for r in rows), default=0)
        if cols > 7:
            coll = tl in d.collapsed
            add("info" if coll else "warn", "wide-table",
                f"{cols} columns" + (" (inside collapsed details)" if coll else ""), f"line {tl}")
    # 8 bold-density
    if d.prose_words:
        dens = d.bold * 100 / d.prose_words
        if dens > 3:
            add("warn", "bold-density", f"{d.bold} bold runs in {d.prose_words} prose words ({dens:.1f} per 100)")
    # 9 banned-words
    text = "".join(d.text)
    for w in BANNED:
        c = len(re.findall(r"(?<![\w-])" + re.escape(w) + r"(?![\w-])", text, re.I))
        if c:
            add("info", "banned-words", f'"{w}" x{c}')
    # 10 undefined-acronym
    counts = defaultdict(int)
    for m in re.finditer(r"\b([A-Z]{2,6})s?\b", text):
        counts[m.group(1)] += 1
    undefined = []
    for a, c in sorted(counts.items(), key=lambda kv: -kv[1]):
        if c < 2 or a in ACRO_OK:
            continue
        defn = (r"\(\s*" + a + r"\s*\)|\b" + a + r"s?\s*\(\s*[A-Za-z]{3,}|\b" + a + r"\s*(?:=|:|means)\s")
        if not re.search(defn, text):
            undefined.append((a, c))
    for a, c in undefined[:10]:
        add("info", "undefined-acronym", f"{a} appears {c}x, never defined")
    # 11 broken-xref
    htexts = [h[1] for h in hs] + d.labels
    plain = re.sub(r"\s+", " ", text)
    for m in re.finditer(r"\b[Ss]ection (\d+(?:\.\d+)?)", plain):
        n = m.group(1)
        if not any(re.match(re.escape(n) + r"(?:[.\s]|$)", h.strip()) for h in htexts):
            add("warn", "broken-xref", f'"{m.group(0)}" has no matching heading')
    for m in sorted(set(re.findall(r"\bAppendix ([A-Z])\b", plain))):
        if not any(h.startswith(f"Appendix {m}") or h.startswith(f"{m}.") for h in htexts):
            add("warn", "broken-xref", f'"Appendix {m}" has no matching heading or label')
    # 12 number-mismatch
    seen = defaultdict(set)
    for tl, rows in d.tables:
        if len(rows) < 2:
            continue
        head = [norm(c) for c in rows[0]]
        labels = defaultdict(int)
        for r in rows[1:]:
            if r and r[0]:
                labels[norm(r[0])] += 1
        for r in rows[1:]:
            if not r or not r[0]:
                continue
            lab = norm(r[0])
            if labels[lab] > 1 or lab.isdigit():
                continue
            for j, c in enumerate(r[1:], 1):
                v = c.replace("$", "").replace("%", "").replace(",", "").strip()
                if j < len(head) and re.search(r"[a-z]", head[j]) and NUM_RE.match(v):
                    seen[(lab, head[j])].add(float(v))
    for (lab, col), vals in seen.items():
        if len(vals) > 1:
            add("warn", "number-mismatch",
                f'row "{lab}" / column "{col}" has values {sorted(vals)} across tables')
    # 13 chart-title
    if d.kind == "html":
        for line, ok in d.figures:
            if not ok:
                add("info", "chart-title", "figure without .chart-title", f"line {line}")
    # inline colors in content: color is the site's job (accent, section hue, callouts); hand-set colors drift
    n_inline = len(re.findall(r'style="[^"]*(?<![-\w])(?:color|background(?:-color)?)\s*:', src_text))
    n_font = len(re.findall(r'<font\b', src_text, flags=re.I))
    if n_inline + n_font and d.kind == "md":
        add("info", "inline-color", f"{n_inline + n_font} inline color style(s); use a callout or the site palette instead")
    return F


def first_screen(d):
    out = []
    if d.kind == "html":
        out.append(d.title)
        if d.meta:
            out.append(d.meta)
        if d.answer:
            out += ["", d.answer]
        out.append("")
        out += [f"## {h[1]}" for h in hs_of(d, 2)]
        if d.appx_labels:
            out.append("")
            out.append("Appendix toggles:")
            out += [f"  - {l}" for l in d.appx_labels]
    else:
        cut = len(d.md_lines)
        n2 = 0
        for h in d.headings:
            if h[0] == 2:
                n2 += 1
                if n2 == 2:
                    cut = h[2] - 1
                    break
        out += [TAG.sub("", l) for l in d.md_lines[:cut]]
        out.append("")
        out.append("Sections:")
        out += [f"## {h[1]}" for h in hs_of(d, 2)]
    return "\n".join(out).strip()


def hs_of(d, lvl):
    return [h for h in d.headings if h[0] == lvl]


def main(argv):
    flags = {a for a in argv if a.startswith("--")}
    files = [a for a in argv if not a.startswith("--")]
    if not files:
        print(__doc__)
        return 2
    results, worst = {}, False
    for f in files:
        try:
            src = open(f, encoding="utf-8", errors="replace").read()
        except OSError as e:
            print(f"error: {f}: {e}", file=sys.stderr)
            continue
        d = parse_html(src) if f.lower().endswith((".html", ".htm")) else parse_md(src)
        if "--first-screen" in flags:
            print(f"== {f}\n{first_screen(d)}\n")
            continue
        F = find_lint(d, src)
        results[f] = F
        worst = worst or any(x[0] == "warn" for x in F)
    if "--first-screen" in flags:
        return 0
    if "--json" in flags:
        print(json.dumps({f: [dict(level=a, rule=b, message=c, where=w) for a, b, c, w in F]
                          for f, F in results.items()}, indent=2))
    else:
        for f, F in results.items():
            print(f"== {f}")
            for level, rule, msg, where in F:
                print(f"{level} {rule}: {msg}" + (f" ({where})" if where else ""))
            nw = sum(1 for x in F if x[0] == "warn")
            print(f"-- {f}: {nw} warn, {len(F) - nw} info\n")
    return 1 if ("--strict" in flags and worst) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
