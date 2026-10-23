#!/usr/bin/env python3
"""Build code-walkthrough HTML pages from JSON specs.

Code is read from the repo at build time by (file, start, end), so quoted
snippets are always verbatim. Usage:

    build.py --repo DIR --commit SHA --github URL --out DIR \
             --parent ../page.html --order slug1,slug2,... specs/*.json
"""
import argparse
import html
import json
import re
import sys
from pathlib import Path

LANG_BY_EXT = {'.py': 'python', '.js': 'javascript', '.ts': 'typescript', '.html': 'xml',
               '.c': 'c', '.h': 'cpp', '.cc': 'cpp', '.cpp': 'cpp', '.hpp': 'cpp',
               '.sh': 'bash', '.yaml': 'yaml', '.yml': 'yaml', '.json': 'json'}
ALLOWED_TAGS = {'p', 'ul', 'ol', 'li', 'code', 'strong', 'em', 'br', 'a'}


def check_html(fragment, where):
    for tag in re.findall(r'</?([a-zA-Z0-9]+)', fragment):
        if tag.lower() not in ALLOWED_TAGS:
            raise SystemExit(f'{where}: disallowed tag <{tag}>')


def load_spec(path, repo, errors):
    spec = json.loads(Path(path).read_text())
    cache = {}
    nblocks = 0
    for si, sec in enumerate(spec['sections']):
        check_html(sec.get('intro', ''), f"{path} section {si}")
        for bi, blk in enumerate(sec['blocks']):
            where = f"{spec['slug']}:{blk['file']}:{blk['start']}-{blk['end']}"
            check_html(blk.get('explain', ''), where)
            src = cache.get(blk['file'])
            if src is None:
                fp = repo / blk['file']
                if not fp.is_file():
                    errors.append(f'{where}: file not found')
                    continue
                src = cache[blk['file']] = fp.read_text(errors='replace').splitlines()
            s, e = int(blk['start']), int(blk['end'])
            if not (1 <= s <= e <= len(src)):
                errors.append(f'{where}: range outside file (len {len(src)})')
                continue
            if e - s + 1 > 60:
                errors.append(f'{where}: block longer than 60 lines')
            blk['code'] = '\n'.join(src[s - 1:e])
            blk['lang'] = LANG_BY_EXT.get(Path(blk['file']).suffix, 'plaintext')
            for ln in blk.get('highlight', []):
                if not s <= ln <= e:
                    errors.append(f'{where}: highlight L{ln} outside range')
            for ln in map(int, re.findall(r'\bL(\d+)\b', blk.get('explain', ''))):
                if not s <= ln <= e:
                    errors.append(f'{where}: explain cites L{ln} outside range (warning)')
            nblocks += 1
    spec['_nblocks'] = nblocks
    if spec.get('map'):
        link_map(spec, repo, errors)
    return spec


NODE_RE = re.compile(r'\b([A-Za-z]\w*)\["([^"]*)"\]')
ARROW_RE = re.compile(r'\s*(?:-->|-\.->|==>|--\s[^-]*?-->|-\.\s[^.]*?\.->)\s*(?:\|[^|]*\|)?\s*')


def parse_map(text):
    """Return ({id: label}, [(src, dst)]) from a Mermaid flowchart."""
    nodes, edges = {}, []
    for nid, label in NODE_RE.findall(text):
        nodes.setdefault(nid, re.sub(r'<br\s*/?>', ' ', label))
    for line in text.splitlines()[1:]:
        parts = ARROW_RE.split(line.strip())
        ids = [m.group(1) for p in parts if (m := re.match(r'([A-Za-z]\w*)', p))]
        if len(ids) < 2:
            continue
        for a, b in zip(ids, ids[1:]):
            if a in nodes and b in nodes and (a, b) not in edges:
                edges.append((a, b))
    return nodes, edges


def link_map(spec, repo, errors):
    """Tie map nodes to blocks: block numbers per node, call edges, def locations."""
    slug = spec['slug']
    labels, edges = parse_map(spec['map'])
    meta = spec.get('nodes', {})
    info = {nid: {'label': lab, 'role': meta.get(nid, {}).get('role', ''), 'def': meta.get(nid, {}).get('def', ''),
                  'blocks': [], 'calls': [b for a, b in edges if a == nid],
                  'called_by': [a for a, b in edges if b == nid]} for nid, lab in labels.items()}
    idx = 0
    for sec in spec['sections']:
        for blk in sec['blocks']:
            idx += 1
            nid = blk.get('node')
            if nid not in info:
                errors.append(f'{slug}: block #{idx} node {nid!r} not in map')
                continue
            info[nid]['blocks'].append(idx)
    for sec in spec['sections']:
        for blk in sec['blocks']:
            if blk.get('node') in info:
                bl = info[blk['node']]['blocks']
                blk['part'] = [None, len(bl)]
    idx = 0
    for sec in spec['sections']:
        for blk in sec['blocks']:
            idx += 1
            if blk.get('node') in info:
                blk['part'][0] = info[blk['node']]['blocks'].index(idx) + 1
    for nid, n in info.items():
        if not n['role']:
            errors.append(f'{slug}: node {nid} has no role (warning)')
        if n['def']:
            f, _, ln = n['def'].rpartition(':')
            fp = repo / f
            if not fp.is_file() or not ln.isdigit():
                errors.append(f'{slug}: node {nid} def {n["def"]!r} not found')
            else:
                lines = fp.read_text(errors='replace').splitlines()
                name = n['label'].split('.')[-1].split()[0]
                if not (1 <= int(ln) <= len(lines) and name in lines[int(ln) - 1]):
                    errors.append(f'{slug}: node {nid} def line does not mention {name!r} (warning)')
    # Show block numbers inside each box; dash the boxes no block covers.
    text = spec['map']
    for nid, n in info.items():
        tag = ' '.join(f'#{b}' for b in n['blocks']) or 'context only'
        text = re.sub(r'\b%s\["([^"]*)"\]' % nid,
                      lambda m: f'{nid}["{m.group(1)}<br/><small>{tag}</small>"]', text, count=1)
    ctx = [nid for nid, n in info.items() if not n['blocks']]
    text += '\n  classDef ctx stroke-dasharray:4 3,fill:#f6f8fa,color:#57606a'
    if ctx:
        text += f"\n  class {','.join(ctx)} ctx"
    spec['map'] = text
    spec['node_info'] = info


TEMPLATE = Path(__file__).with_name('walkthrough_template.html').read_text()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True)
    ap.add_argument('--commit', required=True)
    ap.add_argument('--github', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('--parent', required=True, help='relative URL of the parent overview page')
    ap.add_argument('--parent-title', default='Overview')
    ap.add_argument('--order', default='')
    ap.add_argument('specs', nargs='+')
    a = ap.parse_args()

    repo, out = Path(a.repo), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    errors = []
    specs = [load_spec(p, repo, errors) for p in a.specs]
    hard = [e for e in errors if not e.endswith('(warning)')]
    for e in errors:
        print(('WARN ' if e.endswith('(warning)') else 'ERR  ') + e, file=sys.stderr)
    if hard:
        raise SystemExit(f'{len(hard)} errors')

    order = [s for s in a.order.split(',') if s] or [s['slug'] for s in specs]
    specs.sort(key=lambda s: order.index(s['slug']) if s['slug'] in order else 99)
    siblings = [{'slug': s['slug'], 'title': s['title']} for s in specs]
    for spec in specs:
        data = dict(spec, commit=a.commit, github=a.github.rstrip('/'), parent=a.parent,
                    parent_title=a.parent_title, siblings=siblings)
        payload = json.dumps(data, ensure_ascii=False).replace('</', '<\\/')
        page = (TEMPLATE.replace('%%TITLE%%', html.escape(spec['title']))
                        .replace('%%DATA%%', payload))
        (out / f"{spec['slug']}.html").write_text(page)
        print(f"wrote {out / (spec['slug'] + '.html')}  ({spec['_nblocks']} blocks)")


if __name__ == '__main__':
    main()
