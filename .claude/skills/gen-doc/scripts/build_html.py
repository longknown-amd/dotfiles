#!/usr/bin/env python3
"""Wrap a body fragment in the gen-doc reader skeleton: inline reader.css, build the side TOC.

    build_html.py body.html out.html [--title "Page title"] [--theme dark|light]

The body fragment holds everything inside <main>: h1, .meta, .answer, sections with <h2 id=...>,
and optionally <section class="appx"> with <details class="more" id=...> appendices.
Nav entries: every <h2 id> outside the appendix section, then each appendix <details id> under
"Appendices" (label = its <span class="lbl">). Use --nav-label "id=Short label" to shorten an entry.
"""
import argparse
import html
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent


def strip_tags(s):
    return html.unescape(re.sub(r'<[^>]+>', '', s)).strip()


def build_nav(body, overrides):
    appx_at = body.find('<section class="appx"')
    main_part = body if appx_at < 0 else body[:appx_at]
    appx_part = '' if appx_at < 0 else body[appx_at:]
    links = []
    for m in re.finditer(r'<h2[^>]*\bid="([^"]+)"[^>]*>(.*?)</h2>', main_part, flags=re.S):
        hid, label = m.group(1), strip_tags(m.group(2))
        links.append('<a href="#%s">%s</a>' % (hid, html.escape(overrides.get(hid, label))))
    sub = []
    for m in re.finditer(r'<details[^>]*\bid="([^"]+)"[^>]*>\s*<summary>.*?<span class="lbl">(.*?)</span>', appx_part, flags=re.S):
        did, label = m.group(1), strip_tags(m.group(2))
        sub.append('<a href="#%s">%s</a>' % (did, html.escape(overrides.get(did, label))))
    if sub:
        links.append('<p class="sub">Appendices</p>')
        links += sub
    return '\n'.join(links)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('body')
    ap.add_argument('out')
    ap.add_argument('--title')
    ap.add_argument('--theme', choices=['dark', 'light'])
    ap.add_argument('--nav-label', action='append', default=[], help='id=Short label')
    a = ap.parse_args()
    body = Path(a.body).read_text(encoding='utf-8')
    title = a.title
    if not title:
        m = re.search(r'<h1[^>]*>(.*?)</h1>', body, flags=re.S)
        title = strip_tags(m.group(1)) if m else 'Untitled'
    overrides = dict(x.split('=', 1) for x in a.nav_label)
    page = (HERE / 'assets' / 'skeleton.html').read_text(encoding='utf-8')
    css = (HERE / 'assets' / 'reader.css').read_text(encoding='utf-8')
    page = (page.replace('{{TITLE}}', html.escape(title)).replace('{{CSS}}', css)
                .replace('{{NAV}}', build_nav(body, overrides)).replace('{{BODY}}', body))
    if a.theme:
        page = page.replace('<html lang="en">', '<html lang="en" data-theme="%s">' % a.theme, 1)
    Path(a.out).write_text(page, encoding='utf-8')
    print('%s: %d bytes' % (a.out, len(page)))


if __name__ == '__main__':
    main()
