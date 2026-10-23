#!/usr/bin/env python3
"""Build the feature OVERVIEW page from an overview spec (see references/overview-spec.md).

All code is pulled from the repo by (file, start, end) at build time:
  * scenario steps:  {"node", "title", "plain", "file", "start", "end"}
  * HTML fragments:  <div class="code-ref" data-file=".." data-start="N" data-end="M"
                      data-caption="optional"></div>

    build_overview.py --repo DIR --commit SHA [--github URL] --out page.html spec.json
"""
import argparse
import html
import json
import re
import sys
from pathlib import Path

LANG_BY_EXT = {'.py': 'python', '.js': 'javascript', '.ts': 'typescript', '.html': 'xml',
               '.c': 'c', '.h': 'cpp', '.cc': 'cpp', '.cpp': 'cpp', '.hpp': 'cpp', '.cu': 'cpp',
               '.sh': 'bash', '.yaml': 'yaml', '.yml': 'yaml', '.json': 'json', '.cmake': 'cmake'}
MAX_LINES = 60
KEYWORDS = {'flowchart', 'graph', 'classDef', 'class', 'style', 'linkStyle', 'click', 'subgraph', 'end',
            'TD', 'TB', 'LR', 'RL', 'BT'}


class Repo:
    def __init__(self, root, errors):
        self.root, self.errors, self.cache = Path(root), errors, {}

    def lines(self, file, where):
        if file not in self.cache:
            p = self.root / file
            if not p.is_file():
                self.errors.append(f'{where}: file not found: {file}')
                self.cache[file] = None
            else:
                self.cache[file] = p.read_text(errors='replace').splitlines()
        return self.cache[file]

    def snippet(self, file, start, end, where):
        src = self.lines(file, where)
        if src is None:
            return None
        start, end = int(start), int(end)
        if not (1 <= start <= end <= len(src)):
            self.errors.append(f'{where}: {file}:{start}-{end} outside file (len {len(src)})')
            return None
        if end - start + 1 > MAX_LINES:
            self.errors.append(f'{where}: {file}:{start}-{end} longer than {MAX_LINES} lines')
        return '\n'.join(src[start - 1:end])


def lang_of(file):
    return LANG_BY_EXT.get(Path(file).suffix, 'plaintext')


def node_ids(mermaid_text):
    ids = set(re.findall(r'(?:^|[\s;>|-])([A-Za-z]\w*)\s*(?=[\[\(\{>])', mermaid_text, re.M))
    return ids - KEYWORDS


def render_code_refs(fragment, repo, github, commit, where):
    def repl(m):
        attrs = dict(re.findall(r'data-(\w+)="([^"]*)"', m.group(0)))
        f, s, e = attrs.get('file'), attrs.get('start'), attrs.get('end')
        code = repo.snippet(f, s, e, where)
        if code is None:
            return '<p><em>missing code</em></p>'
        ref = f'{f}:{s}-{e}'
        link = (f'<a href="{github}/blob/{commit}/{f}#L{s}-L{e}" target="_blank" rel="noopener">{html.escape(ref)}</a>'
                if github else html.escape(ref))
        cap = attrs.get('caption')
        cap_html = f'<b>{html.escape(cap)}</b> — {link}' if cap else f'<b>{link}</b>'
        return (f'<div class="codecap">{cap_html}</div>'
                f'<pre><code class="language-{lang_of(f)}">{html.escape(code)}</code></pre>')
    return re.sub(r'<div class="code-ref"[^>]*>\s*</div>', repl, fragment)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True)
    ap.add_argument('--commit', required=True)
    ap.add_argument('--github', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('spec')
    a = ap.parse_args()

    spec = json.loads(Path(a.spec).read_text())
    errors = []
    repo = Repo(a.repo, errors)
    github = a.github.rstrip('/')
    diagrams = spec.get('diagrams', {})
    walk_key = spec.get('walk_diagram', 'main')

    # ---- scenarios: fill code from the repo, check nodes exist in the walk diagram
    walk_nodes = node_ids(diagrams.get(walk_key, ''))
    for key, sc in spec.get('scenarios', {}).items():
        for i, st in enumerate(sc['steps'], 1):
            where = f'scenario {key} step {i}'
            if st.get('node') not in walk_nodes:
                errors.append(f'{where}: node {st.get("node")!r} not in diagram {walk_key!r} ({sorted(walk_nodes)})')
            code = repo.snippet(st['file'], st['start'], st['end'], where)
            st['path'] = st['file']
            st['file'] = f"{st['file']}:{st['start']}-{st['end']}"
            st['code'] = code or ''
            st['lang'] = lang_of(st['path'])

    # ---- sections -> nav + html
    nav = [f'<a class="back" href="{spec["back"]["href"]}">{spec["back"]["text"]}</a>'] if spec.get('back') else []
    out = []
    for sec in spec['sections']:
        sid, kind = sec['id'], sec.get('kind', 'html')
        nav.append(f'<a href="#{sid}">{sec["nav"]}</a>')
        out.append('<!-- ======================================================= -->')
        out.append(f'<h2 id="{sid}">{sec["title"]}</h2>')
        body = render_code_refs(sec.get('html', ''), repo, github, a.commit, f'section {sid}')
        out.append(body)
        if kind == 'walkthrough':
            out.append('<div class="scenarios" id="scenarios"></div>\n<div class="player">\n'
                       '  <div class="diagram-pane">\n    <div class="mermaid-host focus" id="main-diagram"></div>\n'
                       f'    <div class="hint">{sec.get("legend", "")}</div>\n  </div>\n'
                       '  <div class="step-card" id="step-card"></div>\n</div>')
        elif kind == 'replays':
            out.append('<div class="rp-tabs" id="rp-tabs"></div>\n<div id="rp-main"></div>')
        elif kind == 'quiz':
            out.append('<div id="ov-quiz"></div>')
        for sub in sec.get('subs', []):
            nav.append(f'<a class="sub" href="#{sub["id"]}">{sub["nav"]}</a>')
            out.append(f'<h3 id="{sub["id"]}">{sub["title"]}</h3>')
            out.append(render_code_refs(sub.get('html', ''), repo, github, a.commit, f'section {sub["id"]}'))

    # ---- diagram hosts referenced in html must exist
    all_html = '\n'.join(out)
    for key in re.findall(r'data-diagram="([^"]+)"', all_html):
        if key not in diagrams and key not in ('0', '1'):
            errors.append(f'data-diagram="{key}" has no entry in diagrams')

    for e in errors:
        print('ERR  ' + e, file=sys.stderr)
    if errors:
        raise SystemExit(f'{len(errors)} errors')

    data = {'diagrams': diagrams, 'scenarios': spec.get('scenarios', {}), 'quiz': spec.get('quiz', []),
            'replay_tabs': spec.get('replay_tabs', []), 'walk_diagram': walk_key,
            'commit': a.commit, 'github': github}
    tpl = Path(__file__).with_name('overview_template.html').read_text()
    extra = ''.join(f'<script src="{s}"></script>' for s in spec.get('scripts', []))
    page = (tpl.replace('%%TITLE%%', html.escape(spec['title']))
               .replace('%%EXTRA_HEAD%%', extra)
               .replace('%%NAV%%', '\n'.join('  ' + n for n in nav))
               .replace('%%H1%%', spec.get('h1', html.escape(spec['title'])))
               .replace('%%SUBTITLE%%', spec.get('subtitle', ''))
               .replace('%%FOOTER%%', spec.get('footer', ''))
               .replace('%%SECTIONS%%', all_html)
               .replace('%%DATA%%', json.dumps(data, ensure_ascii=False).replace('</', '<\\/')))
    Path(a.out).write_text(page)
    n_steps = sum(len(s['steps']) for s in spec.get('scenarios', {}).values())
    print(f'wrote {a.out}  ({len(spec["sections"])} sections, {n_steps} scenario steps, '
          f'{len(spec.get("quiz", []))} quiz, {len(diagrams)} diagrams)')


if __name__ == '__main__':
    main()
