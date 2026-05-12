#!/usr/bin/env node
// Restyle all migrated pages: replace marked-default HTML with inline-styled HTML
// that simulates rendered Markdown in OneNote.

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { PublicClientApplication } from '@azure/msal-node';
import { Client } from '@microsoft/microsoft-graph-client';
import { marked } from 'marked';
import fetch from 'node-fetch';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const MCP_DIR = __dirname;
const DOCS_DIR = '/home/thohuang/docs/docs';
const MKDOCS_BASE = 'http://hjbog-srdc-38:8000';

const cacheFilePath = path.join(MCP_DIR, '.msal-cache.json');
const clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e';
const scopes = ['Notes.Read', 'Notes.ReadWrite', 'Notes.Create', 'User.Read'];

// --- MSAL ---
const cachePlugin = {
  beforeCacheAccess: async (ctx) => {
    if (fs.existsSync(cacheFilePath))
      ctx.tokenCache.deserialize(fs.readFileSync(cacheFilePath, 'utf8'));
  },
  afterCacheAccess: async (ctx) => {
    if (ctx.cacheHasChanged)
      fs.writeFileSync(cacheFilePath, ctx.tokenCache.serialize(), { mode: 0o600 });
  }
};
const pca = new PublicClientApplication({
  auth: { clientId, authority: 'https://login.microsoftonline.com/common' },
  cache: { cachePlugin }
});

let accessToken;
async function getToken() {
  const accounts = await pca.getTokenCache().getAllAccounts();
  if (!accounts.length) throw new Error('No cached MSAL account.');
  const result = await pca.acquireTokenSilent({ account: accounts[0], scopes });
  accessToken = result.accessToken;
  return accessToken;
}

let client;
function getClient() {
  if (!client) {
    client = Client.init({
      authProvider: async (done) => {
        try { done(null, await getToken()); }
        catch (e) { done(e, null); }
      }
    });
  }
  return client;
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// --- Custom marked renderer with inline styles ---
const styledRenderer = {
  heading({ text, depth }) {
    if (depth === 1) {
      return `<h1>${text}</h1>\n`;
    }
    if (depth === 2) {
      return `<h2 style="border-bottom: 1px solid #d0d7de; padding-bottom: 0.3em; margin-top: 1.5em;">${text}</h2>\n`;
    }
    return `<h3 style="margin-top: 1.2em;">${text}</h3>\n`;
  },
  paragraph({ text }) {
    return `<p style="line-height: 1.6; margin: 0.8em 0;">${text}</p>\n`;
  },
  code({ text, lang }) {
    const escaped = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return `<pre style="background-color: #f6f8fa; border: 1px solid #d0d7de; border-radius: 6px; padding: 16px; font-family: 'Consolas', 'Courier New', monospace; font-size: 13px; line-height: 1.45; overflow-x: auto; white-space: pre;"><code>${escaped}</code></pre>\n`;
  },
  codespan({ text }) {
    return `<code style="background-color: #eff1f3; padding: 0.2em 0.4em; border-radius: 3px; font-family: 'Consolas', 'Courier New', monospace; font-size: 85%;">${text}</code>`;
  },
  table({ header, rows }) {
    let html = `<table style="border-collapse: collapse; width: auto; min-width: 50%; margin: 1em 0;">\n<thead>\n<tr style="background-color: #f6f8fa;">\n`;
    for (const cell of header) {
      html += `<th style="border: 1px solid #d0d7de; padding: 10px 16px; text-align: ${cell.align || 'left'};">${cell.text}</th>\n`;
    }
    html += `</tr>\n</thead>\n<tbody>\n`;
    for (const row of rows) {
      html += `<tr>\n`;
      for (const cell of row) {
        html += `<td style="border: 1px solid #d0d7de; padding: 10px 16px;">${cell.text}</td>\n`;
      }
      html += `</tr>\n`;
    }
    html += `</tbody>\n</table>\n`;
    return html;
  },
  blockquote({ text }) {
    return `<blockquote style="border-left: 4px solid #d0d7de; padding: 0.5em 1em; margin: 1em 0; color: #57606a;">${text}</blockquote>\n`;
  },
  list({ items, ordered }) {
    const tag = ordered ? 'ol' : 'ul';
    const inner = items.map(i => i.raw !== undefined ? this.listitem(i) : `<li style="margin: 0.3em 0;">${i}</li>`).join('\n');
    return `<${tag}>\n${inner}\n</${tag}>\n`;
  },
  listitem({ text }) {
    return `<li style="margin: 0.3em 0;">${text}</li>\n`;
  },
  hr() {
    return `<hr style="border: none; border-top: 1px solid #d0d7de; margin: 1.5em 0;">\n`;
  },
  link({ href, text }) {
    return `<a href="${href}" style="color: #0969da; text-decoration: none;">${text}</a>`;
  },
  strong({ text }) {
    return `<strong>${text}</strong>`;
  },
  em({ text }) {
    return `<em>${text}</em>`;
  }
};

marked.use({ renderer: styledRenderer, gfm: true, breaks: false });

function mdToStyledHtml(md) {
  if (!md) return '';
  return marked.parse(String(md));
}

function stripLeadingH1(md) {
  return md.replace(/^#\s+.+\n*/, '');
}

function rewriteIndexLinks(md) {
  return md.replace(/\[([^\]]+)\]\(([^)]+\.md)\)/g, (match, text, href) => {
    const urlPath = href.replace(/\.md$/, '/');
    return `[${text}](${MKDOCS_BASE}/${urlPath})`;
  });
}

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// --- Update a page's content via Graph API PATCH ---
async function updatePageContent(pageId, title, htmlBody) {
  const gc = getClient();
  const patchBody = [{
    target: 'body',
    action: 'replace',
    content: `<div><h1>${escapeHtml(title)}</h1>${htmlBody}</div>`
  }];
  await gc.api(`/me/onenote/pages/${pageId}/content`)
    .header('Content-Type', 'application/json')
    .patch(patchBody);
}

// --- Find pages in a section ---
async function getSectionPages(sectionId) {
  const gc = getClient();
  const r = await gc.api(`/me/onenote/sections/${sectionId}/pages?$orderby=order`).get();
  return r.value || [];
}

// --- Page definitions ---
const GPU_ENG_PAGES = [
  { title: 'Home', file: 'index.md', transform: rewriteIndexLinks },
  { title: 'Radeon Microbench & hipMicroBench Guide', file: 'microbench/guide.md' },
  { title: 'Radeon Microbench Codebase', file: 'microbench/radeon-microbench-codebase.md' },
  { title: 'Convolution', file: 'miopen/convolution.md' },
  { title: 'CBA Fusion Study', file: 'miopen/cba_fusion_study.md' },
  { title: 'Kernel Inventory', file: 'miopen/kernel_inventory.md' },
  { title: 'Coworking with AI', file: 'work-with-ai/coworking-with-ai-guide.md' },
  { title: 'MI Instinct Microbench Onboarding', file: 'work-with-ai/mi-instinct-microbench-onboarding.md' },
  { title: 'bf16 RSQ Cannot Select on gfx1100', file: 'troubleshooting/bf16-rsq-cannot-select.md' },
  { title: 'Docker', file: 'cheatsheets/docker.md' },
];

const MUSIC_PAGES = [
  { title: 'Handel Messiah - Part I', file: 'music/handel-messiah/part1.md' },
  { title: 'Handel Messiah - Part II', file: 'music/handel-messiah/part2.md' },
  { title: 'Handel Messiah - Part III', file: 'music/handel-messiah/part3.md' },
  { title: 'Mendelssohn Elijah - Part I', file: 'music/mendelssohn-elijah/part1.md' },
  { title: 'Mendelssohn Elijah - Part II', file: 'music/mendelssohn-elijah/part2.md' },
];

async function restyleSection(nbName, sectionName, pageDefs) {
  const gc = getClient();

  // Find notebook
  const nbs = (await gc.api('/me/onenote/notebooks').get()).value;
  const nb = nbs.find(n => n.displayName === nbName);
  if (!nb) throw new Error(`Notebook "${nbName}" not found`);

  // Find section
  const secs = (await gc.api(`/me/onenote/notebooks/${nb.id}/sections`).get()).value;
  const sec = secs.find(s => s.displayName === sectionName);
  if (!sec) throw new Error(`Section "${sectionName}" not found in "${nbName}"`);

  // Get all pages in section
  const pages = await getSectionPages(sec.id);
  console.log(`\n${nbName} → ${sectionName}: ${pages.length} pages found`);

  let updated = 0;
  for (const def of pageDefs) {
    // Match by title
    const page = pages.find(p => p.title === def.title);
    if (!page) {
      console.log(`  SKIP: "${def.title}" — not found in section`);
      continue;
    }

    // Read source markdown
    let md = fs.readFileSync(path.join(DOCS_DIR, def.file), 'utf8');
    if (def.transform) md = def.transform(md);
    md = stripLeadingH1(md);

    // Convert to styled HTML
    const styledHtml = mdToStyledHtml(md);

    // Update the page
    try {
      await updatePageContent(page.id, def.title, styledHtml);
      console.log(`  OK: "${def.title}"`);
      updated++;
    } catch (e) {
      console.error(`  FAIL: "${def.title}" — ${e.message}`);
    }

    await sleep(1500);
  }

  return updated;
}

async function main() {
  console.log('Authenticating...');
  await getToken();
  console.log('Token acquired.');

  let total = 0;

  // GPU-Eng-Notes in AMD-Work
  total += await restyleSection('AMD-Work', 'GPU-Eng-Notes', GPU_ENG_PAGES);

  // Music in Personal
  total += await restyleSection('Personal', 'Music', MUSIC_PAGES);

  console.log(`\nDone. Updated ${total} pages with styled HTML.`);
}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
