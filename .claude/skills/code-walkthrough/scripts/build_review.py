#!/usr/bin/env python3
"""Build REVIEW-mode theme pages from a review spec + the real `git diff`.

Diff lines are never typed by hand: the builder runs git (via difflib_git.py) and
renders the hunks the spec references. Every changed line must be covered exactly once
across all themes (hunks can be sliced by new-side line range), or the build fails.

    build_review.py --repo R --source <sha|A..B|staged|worktree> [--github URL]
                    --out DIR --parent ../<slug>.html [--parent-title T] spec.json

Spec (see references/review-spec.md):
{
  "slug": "...", "title": "...",
  "themes": [
    {"id": "classify", "title": "...", "summary": "<p>", "why": "<p>",
     "map": "flowchart LR ... (optional; ID[\"label\"] nodes)",
     "entries": [
        {"hunk": "src/x.py@120", "range": [130, 175], "title": "...",
         "explain": "<p>What changed / why</p>",
         "notes": [{"kind": "risk|question|nit|good|test", "text": "..."}],
         "highlight": [140], "collapsed": false}
     ],
     "checklist": ["..."]}
  ]
}
"""
import argparse
import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from difflib_git import parse  # noqa: E402

LANG_BY_EXT = {'.py': 'python', '.js': 'javascript', '.ts': 'typescript', '.html': 'xml', '.md': 'markdown',
               '.c': 'c', '.h': 'cpp', '.cc': 'cpp', '.cpp': 'cpp', '.hpp': 'cpp', '.cu': 'cpp', '.tpp': 'cpp',
               '.sh': 'bash', '.yaml': 'yaml', '.yml': 'yaml', '.json': 'json', '.cmake': 'cmake'}
NOTE_KINDS = {'risk', 'question', 'nit', 'good', 'test'}
ALLOWED_TAGS = {'p', 'ul', 'ol', 'li', 'code', 'strong', 'em', 'br', 'a', 'b', 'i', 'q'}


def check_html(fragment, where, errors):
    for tag in re.findall(r'</?([a-zA-Z0-9]+)', fragment or ''):
        if tag.lower() not in ALLOWED_TAGS:
            errors.append(f'{where}: disallowed tag <{tag}>')


def changed_positions(hunk):
    """Yield (row_index, anchor_new_line) for each +/- row. A '-' row anchors to the new-side
    line number that follows it (so slices by new-side range also capture deletions)."""
    next_new = hunk['new_start']
    pos = []
    for i, (tag, o, n, _t) in enumerate(hunk['lines']):
        if tag == ' ' or tag == '+':
            next_new = n
        if tag in '+-':
            anchor = n if tag == '+' else next_new
            pos.append((i, anchor))
        if tag in ' +':
            next_new = n + 1
    return pos


STATUS_CLASS = {'new': 'new', 'changed': 'chg', 'context': 'ctxn'}


def file_at(repo, rev, path):
    """File text at the reviewed revision ('' = working tree, ':' = index)."""
    import subprocess
    if rev == '':
        p = Path(repo) / path
        return p.read_text(errors='replace') if p.is_file() else None
    ref = f':{path}' if rev == ':' else f'{rev}:{path}'
    r = subprocess.run(['git', '-C', repo, 'show', ref], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


_BODY_CACHE = {}


def body_range(repo, rev, path, def_ln):
    """[def_ln, end) of the function/constant defined at def_ln, at the reviewed revision.
    Python: until the next non-blank line indented at or below the def (closing brackets
    stay in the body). Other languages: just the def line."""
    key = (repo, rev, path)
    if key not in _BODY_CACHE:
        _BODY_CACHE[key] = (file_at(repo, rev, path) or '').splitlines()
    lines = _BODY_CACHE[key]
    if not path.endswith('.py') or not (1 <= def_ln <= len(lines)):
        return def_ln, def_ln + 1
    head = lines[def_ln - 1]
    indent = len(head) - len(head.lstrip())
    end = def_ln + 1
    while end <= len(lines):
        ln = lines[end - 1]
        if ln.strip() and (len(ln) - len(ln.lstrip())) <= indent and not ln.lstrip().startswith((')', ']', '}', '#')):
            break
        end += 1
    return def_ln, end


def entry_touches(e, path, lo, hi):
    """True if one of the entry's changed rows anchors inside [lo, hi) of `path`."""
    h = e.get('_hunk')
    if not h or h['file'] != path or '_rows' not in e:
        return False
    rows = h['lines'][e['_rows'][0]:e['_rows'][1] + 1]
    nxt = None
    for tag, o, n, _t in rows:
        if tag in ' +':
            nxt = n
        anchor = n if tag == '+' else (nxt + 1 if nxt is not None else h['new_start']) if tag == '-' else None
        if tag in '+-' and anchor is not None and lo <= anchor < hi:
            return True
    return False


def link_theme_map(t, repo, rev, errors, warnings):
    """Tie map nodes to entries: entry numbers in each box, calls/called-by, def check at
    the reviewed revision, and box styling from node status (new / changed / context)."""
    from build_pages import parse_map
    labels, edges = parse_map(t['map'])
    meta = t.get('nodes', {})
    info = {nid: {'label': lab, 'role': meta.get(nid, {}).get('role', ''),
                  'def': meta.get(nid, {}).get('def', ''),
                  'status': meta.get(nid, {}).get('status', 'changed'),
                  'blocks': [], 'calls': [b for x, b in edges if x == nid],
                  'called_by': [x for x, b in edges if b == nid]} for nid, lab in labels.items()}
    def nodes_of(e):
        v = e.get('node')
        return list(v) if isinstance(v, list) else ([v] if v else [])
    for k, e in enumerate(t['entries'], 1):
        if not nodes_of(e):
            errors.append(f"theme {t['id']} entry {k}: no node")
        for nid in nodes_of(e):
            if nid not in info:
                errors.append(f"theme {t['id']} entry {k}: node {nid!r} not in map")
            else:
                info[nid]['blocks'].append(k)
    # Auto-attach: a new/changed function whose def line is a changed line shown in an entry
    # of the same file belongs to that entry too (one slice can define several helpers).
    for nid, n in info.items():
        if n['blocks'] or n['status'] == 'context' or not n['def']:
            continue
        f, _, ln = n['def'].rpartition(':')
        if not ln.isdigit():
            continue
        lo, hi = body_range(repo, rev, f, int(ln))
        for k, e in enumerate(t['entries'], 1):
            if entry_touches(e, f, lo, hi):
                n['blocks'].append(k)
                e['node'] = nodes_of(e) + [nid]
                warnings.append(f"theme {t['id']} node {nid}: auto-attached to entry {k} (change inside {f}:{lo}-{hi - 1})")
    for n in info.values():
        n['blocks'].sort()
    for k, e in enumerate(t['entries'], 1):
        ns = [x for x in nodes_of(e) if x in info]
        if ns:
            bl = info[ns[0]]['blocks']
            e['part'] = [bl.index(k) + 1, len(bl)]
            e['node'] = ns[0]
            e['nodes'] = ns
    cache = {}
    for nid, n in info.items():
        if n['status'] not in STATUS_CLASS:
            errors.append(f"theme {t['id']} node {nid}: status {n['status']!r} not in {list(STATUS_CLASS)}")
        if not n['role']:
            warnings.append(f"theme {t['id']} node {nid}: no role")
        if n['def']:
            f, _, ln = n['def'].rpartition(':')
            if f not in cache:
                cache[f] = file_at(repo, rev, f)
            src = cache[f]
            name = n['label'].split('.')[-1].split()[0].strip('()')
            if src is None or not ln.isdigit():
                errors.append(f"theme {t['id']} node {nid}: def {n['def']!r} not found at the reviewed revision")
            else:
                lines = src.splitlines()
                if not (1 <= int(ln) <= len(lines) and name in lines[int(ln) - 1]):
                    warnings.append(f"theme {t['id']} node {nid}: def line {n['def']} does not mention {name!r}")
    t['node_info'] = info


def resolve_cross_theme(spec, warnings, repo, rev):
    """A new/changed function with no card on its own theme page may be changed on another
    theme page: point its box there instead of calling it context."""
    for t in spec['themes']:
        info = t.get('node_info') or {}
        for nid, n in info.items():
            if n['blocks'] or n['status'] == 'context' or not n['def']:
                continue
            f, _, ln = n['def'].rpartition(':')
            if not ln.isdigit():
                continue
            lo, hi = body_range(repo, rev, f, int(ln))
            hit = None
            for t2 in spec['themes']:
                for k, e in enumerate(t2['entries'], 1):
                    if entry_touches(e, f, lo, hi):
                        hit = (t2['id'], k, t2['title'])
                        break
                if hit:
                    break
            if hit and hit[0] != t['id']:
                n['elsewhere'] = list(hit)
            elif not hit:
                warnings.append(f"theme {t['id']} node {nid}: status {n['status']} but no change card on any page; attach it to an entry or mark it context")


def finalize_map(t):
    info = t.get('node_info')
    if not info:
        return
    text = t['map']
    for nid, n in info.items():
        tag = (' '.join(f'#{b}' for b in n['blocks'])
               or (f"see {n['elsewhere'][0]} #{n['elsewhere'][1]}" if n.get('elsewhere') else 'context only'))
        text = re.sub(r'\b%s\["([^"]*)"\]' % nid, lambda m: f'{nid}["{m.group(1)}<br/><small>{tag}</small>"]', text, count=1)
    text += ('\n  classDef new fill:#dafbe1,stroke:#1a7f37,color:#0b3d1a'
             '\n  classDef chg fill:#fff8c5,stroke:#9a6700,color:#3d2a00'
             '\n  classDef ctxn fill:#f6f8fa,stroke:#8c959f,stroke-dasharray:4 3,color:#57606a')
    for cls in sorted(set(STATUS_CLASS.values())):
        ids = [nid for nid, n in info.items() if STATUS_CLASS.get(n['status']) == cls]
        if ids:
            text += f"\n  class {','.join(ids)} {cls}"
    t['map'] = text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True)
    ap.add_argument('--source', required=True)
    ap.add_argument('--github', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('--parent', required=True)
    ap.add_argument('--parent-title', default='Review overview')
    ap.add_argument('--context', type=int, default=5)
    ap.add_argument('--allow-uncovered', action='store_true')
    ap.add_argument('spec')
    a = ap.parse_args()

    spec = json.loads(Path(a.spec).read_text())
    meta, files = parse(a.repo, a.source, a.context)
    hunks = {h['id']: h for f in files for h in f['hunks']}
    status = {(f['new'] or f['old']): f['status'] for f in files}
    errors, warnings = [], []
    covered = {}   # (hunk_id, row) -> theme/entry

    for t in spec['themes']:
        if not t.get('id') or not t.get('title'):
            errors.append(f"theme {t.get('id')!r}: missing id or title")
            continue
        check_html(t.get('summary'), f"theme {t['id']} summary", errors)
        check_html(t.get('why'), f"theme {t['id']} why", errors)
        for k, e in enumerate(t['entries'], 1):
            where = f"theme {t['id']} entry {k} ({e.get('hunk')})"
            h = hunks.get(e.get('hunk'))
            if not h:
                errors.append(f'{where}: unknown hunk id')
                continue
            check_html(e.get('explain'), where, errors)
            for n in e.get('notes', []):
                if n.get('kind') not in NOTE_KINDS:
                    errors.append(f"{where}: note kind {n.get('kind')!r} not in {sorted(NOTE_KINDS)}")
                check_html(n.get('text'), where, errors)
            lo, hi = e.get('range') or [-10**9, 10**9]
            rows = [i for i, anchor in changed_positions(h) if lo <= anchor <= hi]
            if not rows:
                errors.append(f'{where}: range {e.get("range")} selects no changed lines')
            for i in rows:
                key = (h['id'], i)
                if key in covered:
                    errors.append(f'{where}: changed line already covered by {covered[key]}')
                covered[key] = f"{t['id']}#{k}"
            # Rows to display: changed rows in range plus up to 5 context rows around them.
            if rows:
                first, last = max(0, min(rows) - 5), min(len(h['lines']) - 1, max(rows) + 5)
                # Do not show context that belongs to a neighbouring slice's changes.
                e['_rows'] = [first, last]
            e['_hunk'] = h
            if rows:
                shown = h['lines'][e['_rows'][0]:e['_rows'][1] + 1]
                new_ok = {r[2] for r in shown if r[2] is not None}
                old_ok = {r[1] for r in shown if r[1] is not None}
                text = (e.get('explain') or '') + ' '.join(n.get('text', '') for n in e.get('notes', []))
                for sign, num in re.findall(r'([+\u2212-])L(\d+)', text):
                    ok = new_ok if sign == '+' else old_ok
                    if int(num) not in ok:
                        warnings.append(f'{where}: cites {sign}L{num}, which is not a shown {"new" if sign == "+" else "old"}-side line (citation check)')
            e['_lang'] = LANG_BY_EXT.get(Path(h['file']).suffix, 'plaintext')
            e['_status'] = status.get(h['file'], 'modified')

    # ---- change map <-> entries (1:1 linking, same contract as feature-mode pages)
    head_rev = meta.get('sha') or ('' if meta['head'] == 'WORKTREE' else ':' if meta['head'] == 'INDEX' else meta['head'])
    for t in spec['themes']:
        if t.get('map'):
            link_theme_map(t, a.repo, head_rev, errors, warnings)
    resolve_cross_theme(spec, warnings, a.repo, head_rev)
    for t in spec['themes']:
        finalize_map(t)

    total_changed = 0
    uncovered = []
    for h in hunks.values():
        for i, _anchor in changed_positions(h):
            total_changed += 1
            if (h['id'], i) not in covered:
                uncovered.append((h['id'], h['lines'][i][2] or h['lines'][i][1], h['lines'][i][0]))
    if uncovered:
        by_hunk = {}
        for hid, ln, tag in uncovered:
            by_hunk.setdefault(hid, []).append(f'{tag}{ln}')
        msg = '; '.join(f"{hid}: {len(v)} lines ({v[0]}..{v[-1]})" for hid, v in by_hunk.items())
        (warnings if a.allow_uncovered else errors).append(f'UNREVIEWED changed lines: {msg}')

    for e in errors:
        print('ERR  ' + e, file=sys.stderr)
    for w in warnings:
        print('WARN ' + w, file=sys.stderr)
    if errors:
        raise SystemExit(f'{len(errors)} errors')

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    tpl = Path(__file__).with_name('review_template.html').read_text()
    siblings = [{'id': t['id'], 'title': t['title']} for t in spec['themes']]
    gh = a.github.rstrip('/')
    head_ref = meta.get('sha') or (meta['head'] if meta['head'] not in ('INDEX', 'WORKTREE') else '')
    for t in spec['themes']:
        entries = []
        for e in t['entries']:
            h = e.pop('_hunk')
            r0, r1 = e.pop('_rows')
            rows = h['lines'][r0:r1 + 1]
            entries.append(dict(e, file=h['file'], context=h['context'], rows=rows,
                                lang=e.pop('_lang'), fstatus=e.pop('_status'),
                                adds=sum(1 for r in rows if r[0] == '+'),
                                dels=sum(1 for r in rows if r[0] == '-')))
        data = {'theme': dict(t, entries=entries), 'meta': meta, 'github': gh, 'head_ref': head_ref,
                'parent': a.parent, 'parent_title': a.parent_title, 'siblings': siblings,
                'review_title': spec.get('title', '')}
        payload = json.dumps(data, ensure_ascii=False).replace('</', '<\\/')
        page = tpl.replace('%%TITLE%%', html.escape(t['title'])).replace('%%DATA%%', payload)
        (out / f"{t['id']}.html").write_text(page)
        print(f"wrote {out / (t['id'] + '.html')}  ({len(entries)} entries, "
              f"+{sum(x['adds'] for x in entries)}/-{sum(x['dels'] for x in entries)})")
    # Summary for the overview builder.
    summary = {'meta': meta, 'files': [{'path': f['new'] or f['old'], 'status': f['status'],
                                        'adds': sum(h['adds'] for h in f['hunks']),
                                        'dels': sum(h['dels'] for h in f['hunks']),
                                        'hunks': len(f['hunks'])} for f in files],
               'themes': [{'id': t['id'], 'title': t['title'], 'entries': len(t['entries']),
                           'summary': t.get('summary', ''),
                           'notes': [dict(n, entry=k, entry_title=e.get('title', ''), file=e.get('hunk', '').split('@')[0])
                                     for k, e in enumerate(t['entries'], 1) for n in e.get('notes', [])],
                           'files': sorted({hunks[e['hunk']]['file'] for e in t['entries']})}
                          for t in spec['themes']],
               'coverage': {'changed_lines': total_changed, 'uncovered': len(uncovered)}}
    (out / 'review_summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False))
    print(f"coverage: {total_changed - len(uncovered)}/{total_changed} changed lines reviewed")


if __name__ == '__main__':
    main()
