#!/usr/bin/env python3
"""Score generated walkthrough pages against an eval's expected facts.

    run_evals.py evals/<feature>.json page.html [page.html ...]

Each fact passes when every regex in `all` matches the pages' combined text
(tags stripped; script data such as replays.js / embedded JSON included).
"""
import html
import json
import re
import sys
from pathlib import Path


def page_text(paths):
    out = []
    for p in paths:
        raw = Path(p).read_text(errors='replace')
        out.append(html.unescape(re.sub(r'<[^>]+>', ' ', raw)))
        for src in re.findall(r'<script src="([^":]+\.js)"', raw):   # local data scripts
            f = Path(p).parent / src
            if f.is_file():
                out.append(html.unescape(f.read_text(errors='replace')))
    return '\n'.join(out)


def main():
    ev = json.loads(Path(sys.argv[1]).read_text())
    text = page_text(sys.argv[2:])
    passed = 0
    for fact in ev['facts']:
        miss = [rx for rx in fact['all'] if not re.search(rx, text, re.I)]
        passed += not miss
        print(('PASS ' if not miss else 'MISS ') + f"{fact['id']:<22} {fact['desc']}" + (f"   missing: {miss}" if miss else ''))
    st = ev.get('structure', {})
    quiz = len(re.findall(r'"q":|\bq: ["`]', text))
    replays = len(set(re.findall(r"""["']id["']:\s*["'](r[\w-]*)["']""", text)))
    print(f"quiz questions: {quiz} (min {st.get('min_quiz_questions', 0)})  replays: {replays} (min {st.get('min_replays', 0)})")
    print(f"SCORE {passed}/{len(ev['facts'])}")
    ok = passed == len(ev['facts']) and quiz >= st.get('min_quiz_questions', 0) and replays >= st.get('min_replays', 0)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
