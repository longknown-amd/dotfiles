#!/usr/bin/env python3
"""Parse `git diff` into files and hunks with stable ids.

Diff sources:
  commit SHA            -> SHA^..SHA
  A..B                  -> range
  staged                -> index vs HEAD          (alias: --staged)
  worktree              -> working tree vs index  (alias: --worktree)

Hunk id: "<new path>@<new start>"; for deleted files "<old path>@-<old start>".

CLI:  difflib_git.py --repo R <source> [--context N] [--json]
      prints one line per hunk: id, +adds/-dels, function context.
"""
import argparse
import json
import re
import subprocess
import sys

HUNK_RE = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$')


def diff_args(source):
    if source in ('staged', '--staged'):
        return ['diff', '--cached'], 'staged', 'HEAD', 'INDEX'
    if source in ('worktree', '--worktree'):
        return ['diff'], 'worktree', 'INDEX', 'WORKTREE'
    if '..' in source:
        a, b = source.split('..', 1)
        return ['diff', a, b], source, a, b
    return ['diff', f'{source}^', source], source, f'{source}^', source


def git(repo, *args):
    return subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True, check=True).stdout


def parse(repo, source, context=5):
    args, label, base, head = diff_args(source)
    out = git(repo, *args, f'-U{context}', '--no-color', '--no-ext-diff', '--find-renames')
    files, cur, hunk = [], None, None
    old_n = new_n = 0
    for line in out.splitlines():
        if line.startswith('diff --git '):
            cur = {'old': None, 'new': None, 'status': 'modified', 'hunks': [], 'binary': False}
            files.append(cur)
            hunk = None
            continue
        if cur is None:
            continue
        if hunk is None or line.startswith(('--- ', '+++ ', 'new file', 'deleted file', 'rename ', 'similarity', 'index ', 'Binary')):
            if line.startswith('--- '):
                cur['old'] = None if line[4:] == '/dev/null' else line[6:]
                continue
            if line.startswith('+++ '):
                cur['new'] = None if line[4:] == '/dev/null' else line[6:]
                continue
            if line.startswith('new file'):
                cur['status'] = 'added'
            elif line.startswith('deleted file'):
                cur['status'] = 'deleted'
            elif line.startswith('rename from'):
                cur['status'] = 'renamed'
            elif line.startswith('Binary'):
                cur['binary'] = True
            if not line.startswith('@@'):
                continue
        m = HUNK_RE.match(line)
        if m:
            o, oc, n, nc, ctx = m.groups()
            old_n, new_n = int(o), int(n)
            path = cur['new'] or cur['old']
            hid = f"{path}@{n}" if cur['new'] else f"{path}@-{o}"
            hunk = {'id': hid, 'file': path, 'old_start': int(o), 'new_start': int(n),
                    'context': ctx.strip(), 'lines': [], 'adds': 0, 'dels': 0}
            cur['hunks'].append(hunk)
            continue
        if hunk is None:
            continue
        tag = line[:1]
        if tag == '\\':
            continue
        if tag == '+':
            hunk['lines'].append(['+', None, new_n, line[1:]]); new_n += 1; hunk['adds'] += 1
        elif tag == '-':
            hunk['lines'].append(['-', old_n, None, line[1:]]); old_n += 1; hunk['dels'] += 1
        else:
            hunk['lines'].append([' ', old_n, new_n, line[1:]]); old_n += 1; new_n += 1
    meta = {'label': label, 'base': base, 'head': head}
    if source not in ('staged', '--staged', 'worktree', '--worktree') and '..' not in source:
        meta['subject'] = git(repo, 'log', '-1', '--format=%s', source).strip()
        meta['body'] = git(repo, 'log', '-1', '--format=%b', source).strip()
        meta['author'] = git(repo, 'log', '-1', '--format=%an', source).strip()
        meta['date'] = git(repo, 'log', '-1', '--format=%ad', '--date=short', source).strip()
        meta['sha'] = git(repo, 'rev-parse', source).strip()
    return meta, files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', default='.')
    ap.add_argument('--context', type=int, default=5)
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--staged', action='store_true', help='same as source "staged"')
    ap.add_argument('--worktree', action='store_true', help='same as source "worktree"')
    ap.add_argument('source', nargs='?')
    a = ap.parse_args()
    a.source = 'staged' if a.staged else 'worktree' if a.worktree else a.source
    if not a.source:
        ap.error('give a source: <sha>, A..B, staged or worktree')
    meta, files = parse(a.repo, a.source, a.context)
    if a.json:
        json.dump({'meta': meta, 'files': files}, sys.stdout)
        return
    print(f"# {meta['label']}  ({meta['base']} -> {meta['head']})  {meta.get('subject', '')}")
    total = 0
    for f in files:
        print(f"\n## {f['new'] or f['old']}  [{f['status']}]  hunks={len(f['hunks'])}")
        for h in f['hunks']:
            total += 1
            first_add = next((l[3].strip() for l in h['lines'] if l[0] == '+' and l[3].strip()), '')
            print(f"  {h['id']:<60} +{h['adds']:<4} -{h['dels']:<4} {h['context'][:50]}  | {first_add[:60]}")
    print(f"\n{total} hunks")


if __name__ == '__main__':
    main()
