#!/usr/bin/env python3
"""Render each page in headless Chromium and fail on broken diagrams or JS errors.

    check_render.py page.html [page.html ...]

Checks: every .mermaid-host / #map got an <svg>, no Mermaid "Syntax error"
SVG, no rendered "diagram error", no uncaught JS exceptions in the console.
"""
import re
import subprocess
import sys
from pathlib import Path

CHROME = ['chromium', '--headless=new', '--no-sandbox', '--disable-gpu',
          '--virtual-time-budget=15000', '--window-size=1500,4000']


def check(page):
    url = Path(page).resolve().as_uri()
    p = subprocess.run(CHROME + ['--enable-logging=stderr', '--v=0', '--dump-dom', url],
                       capture_output=True, text=True, timeout=180)
    dom, log = p.stdout, p.stderr
    dom = re.sub(r'<script\b[^>]*>.*?</script>', '', dom, flags=re.S)   # ignore JS source text
    problems = []
    hosts = len(re.findall(r'class="mermaid-host[^"]*"', dom)) + dom.count('id="map"') + dom.count('class="rp-diag')
    svgs = len(re.findall(r'<svg[^>]+id="(?:mmd|rp-mmd)', dom))
    if svgs < hosts:
        problems.append(f'{hosts} diagram hosts but only {svgs} rendered')
    if 'Syntax error in text' in dom:
        problems.append('Mermaid syntax error')
    if re.search(r'>diagram error', dom):
        problems.append('diagram error rendered')
    for line in log.splitlines():
        if 'Uncaught' in line or ('CONSOLE' in line and 'Error' in line):
            problems.append('JS: ' + line.strip()[:200])
    return hosts, svgs, problems


if __name__ == '__main__':
    bad = 0
    for page in sys.argv[1:]:
        hosts, svgs, problems = check(page)
        status = 'OK  ' if not problems else 'FAIL'
        bad += bool(problems)
        print(f'{status} {page}  diagrams {svgs}/{hosts}')
        for pr in problems:
            print('     -', pr)
    sys.exit(1 if bad else 0)
