---
name: aihot
description: AI HOT (aihot.virxact.com) AI-news lookup Skill. Use whenever the user asks for "today's AI news", "AI daily", "AI HOT", "AI hot topics", "what's recent in AI", "what did OpenAI/Anthropic/Google ship lately", "AI news today", "what's happening in the AI industry", "what models dropped today", "yesterday in AI", "show me the curated picks", "AI HOT picks", "the past week's AI papers", "AI model releases", "AI product releases", "AI industry moves", "AI tips and takes", or any similar AI-news query. Even when the user only says "AI scene", "AI news", "AI roundup", or simply "what happened today" with the surrounding context being AI / LLMs / startups, this Skill should fire. Also fires for the equivalent Chinese phrasings (AI 日报 / AI 资讯 / AI 热点 / 今天 AI 圈 / 最近 AI). The Skill curls a public REST API directly and assembles an English markdown brief — no API key or MCP server setup required. **Do not under-trigger** — if the user asks about AI news and you do not invoke this Skill, you will hand them stale training data as if it were today's news, which is harmful.
---

# AI HOT Skill

Lets the agent fetch aihot.virxact.com's daily AI HOT brief and the full AI news feed using natural-language queries — no browser needed. Standard SKILL.md format, works across Claude Code / Codex CLI / Cursor / Gemini CLI / OpenCode / any compatible host.

Live site: https://aihot.virxact.com (publicly reachable, anonymous, no token required)

> **Language note**: the upstream data is bilingual (English source titles + LLM-generated Chinese titles/summaries). This translated Skill instructs the agent to **render the user-facing brief in English** — translate Chinese titles and summaries to natural English on the fly when assembling the output. Original `source` names and URLs stay verbatim. The five fixed daily-section labels are Chinese in the API response (`模型发布/更新`, etc.) and must be rendered as their English equivalents (see the category table below).

## Prerequisite: you MUST send a User-Agent (API endpoints only)

`/api/public/*` sits behind an nginx UA blocklist that rejects commercial scrapers, so the default `curl/X.Y` UA gets a 403 Forbidden. **Every curl that hits the API must carry a browser UA**:

```bash
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

# From here on, every API curl needs -H "User-Agent: $UA", e.g.:
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/daily"
```

The curl examples in the "Workflow" section below assume `$UA` is already set, for brevity — in real calls you must add `-H "User-Agent: $UA"`. **Do not forget.** Skipping this will make you think the endpoint is broken when it's just being 403'd.

> **Scope clarification**: this UA requirement **only applies to `/api/public/*` API endpoints**. The `/aihot-skill/{install.sh,SKILL.md,README.md}` install entry points are **deliberately exempted** from the nginx UA blocklist (they're designed for the `curl -fsSL ... | bash` one-liner install flow), so they return 200 with a default curl UA. Don't over-generalize the "prerequisite" to every aihot.virxact.com path.

## When to use it

> **Routing priority (first principle)**: **default to curated** — `items?mode=selected` is AI HOT's hand-picked daily "main menu", covering what users care about with fresh data.
>
> - **Only when the user literally says "daily" / "daily brief" / "日报"** should you hit `daily` (an editorial-finished product sliced by UTC day, which doesn't line up with rolling windows like "past 24 hours / today")
> - **Only when the user explicitly says "all / complete / everything / full / 全部 / 完整 / 所有 / 全量"** should you hit `mode=all` (includes secondary, non-curated items — high volume but noisier)
> - **"What's happening in AI today", "big news in the past 24h", "anything new in AI lately"** and similar broad questions = **default to curated + a time window (since)**, do NOT default to daily or all
>
> This aligns with users' semantic priority: curated is the main menu; daily and all are alternatives the user explicitly asks for, and shouldn't steal the default.

| What the user says | Endpoint to hit |
|---|---|
| **Default (broad question)**: "what's in AI today", "big news in the past 24h", "AI scene lately", "anything new in AI" | `GET /api/public/items?mode=selected&since=<semantic time window>` (default curated + `since` to narrow) |
| **Explicitly says "daily" / "日报"**: "AI daily", "today's daily", "show me the daily" | `GET /api/public/daily` (latest daily brief) |
| **Explicitly says "all / complete / everything / full"**: "show me everything from today", "full list", "all AI items" | `GET /api/public/items?mode=all` (with or without `since`, depending on context) |
| "Yesterday's / day-before-yesterday's daily", "May 6 daily", "5 月 6 号的日报" | `GET /api/public/daily/{YYYY-MM-DD}` |
| "Recent dailies", "list the dailies", "daily archive" | `GET /api/public/dailies?take=N` |
| "Show me curated items", "AI HOT picks" | `GET /api/public/items?mode=selected` |
| "Recent model releases", "AI product launches", "AI industry moves", "AI papers" | `GET /api/public/items?mode=selected&category=...&since=<7d ago>` (default curated + category) |
| "AI news from the past week", "releases from 5 days ago to now" | `GET /api/public/items?mode=selected&since=ISO-8601` |
| "What did OpenAI / Anthropic / Google ship recently" (company axis) | `GET /api/public/items?q=OpenAI` (server-side keyword search, shipped 2026-05-08) |
| "Sora-related / GPT-5-related / RAG papers" | `GET /api/public/items?q=<keyword>` (matches across `title`, Chinese `title`, and Chinese `summary`) |

General heuristic: **the user is asking for "current facts about the AI industry" — do not improvise from training data, always go through the API**. Even if you "feel" you know the answer, query anyway — AI HOT is much fresher than your training cutoff and is angled toward topics the AI-startup audience cares about.

## Endpoint cheat sheet

| Endpoint | Purpose | Main params |
|---|---|---|
| `/api/public/daily` | Latest daily brief | none |
| `/api/public/daily/{YYYY-MM-DD}` | Daily brief for a given date | path: `date` |
| `/api/public/dailies` | Daily-brief archive list | `take` (1–180, default 30) |
| `/api/public/items` | Full AI news feed | `mode` / `category` / `since` / `take` / `cursor` / `q` (keyword) |

Conventions:
- Base URL: `https://aihot.virxact.com`
- Auth: none (anonymous)
- Rate limit: 600 req/min/IP (call serially, do not slam in parallel)
- The items endpoint's `since` is capped at the most recent 7 days: **omitting it is equivalent to `since=now-7d`** (server-side fallback); anything earlier than 7 days ago is silently clamped to 7 days ago; future timestamps → 400. **So no matter how the Skill calls it, the items API only ever returns the past 7 days of content.** Need older? Walk the `/api/public/daily/{YYYY-MM-DD}` archive instead.
- `take` is capped at 100; for more, use cursor-based pagination
- Full OpenAPI 3.1 spec: `https://aihot.virxact.com/openapi.yaml`

## Workflow

### Default path: pull curated + time window (first choice for broad questions)

Curated = AI HOT's hand-picked daily "main menu" — covers all the AI events users care about, sorted by publish time descending. **Any "what's in AI today", "big news in the past 24h", "anything new in AI" type broad question defaults to this.** Compared to the daily brief: ① free choice of time window (24h / 3 days / 1 week — as narrow as the user's wording demands) ② fresher data (rolling, not sliced by UTC day) ③ still high quality (drawn from the `aiSelected=true` pool, no secondary clutter).

```bash
# Pull the past 24h of curated items (user asked "big news in the past 24h")
since=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&since=$since&take=50"

# Pull the latest 50 curated items (user asked "show me the curated picks" / no explicit time window)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&take=50" \
  | jq '.items[] | {title, source, publishedAt, url}'
```

### Pull the daily brief (only when the user explicitly says "daily" / "日报")

**Trigger keyword**: the words "daily" / "daily brief" / "日报" appear in the sentence. **Without those words, do NOT take this path** — the daily brief is a fixed one-day product sliced at UTC midnight, and doesn't line up with rolling windows like "past 24 hours / today".

The daily brief is AI HOT's "headline layer" — auto-generated daily at 08:00 Beijing time, organized into 5 fixed thematic sections, with an editor's lead paragraph. It's a finished, theme-bundled product.

```bash
# Pull today's (or the latest available) daily brief
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/daily" \
  | jq '{date, lead: .lead.title, sections: [.sections[] | {label, n: (.items | length)}]}'
```

### Pull a daily brief for a specific date

```bash
# YYYY-MM-DD, anchored at UTC midnight
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/daily/2026-05-07"
```

### List the daily-brief archive (discovery)

When you don't know which dates are available, check the archive first:

```bash
# Last N days of daily indexes (no body, just date + lead headline)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/dailies?take=14" \
  | jq '.items[] | {date, leadTitle}'
```

### Pull everything (only when the user explicitly says "all / complete / everything / full")

**Trigger keywords**: the sentence contains "all / complete / everything / full / including older / 全部 / 完整 / 所有 / 全量" — the user specifically wants secondary items beyond curated (relevant content that didn't make the curated cut). **Without these keywords, do NOT switch to `mode=all`** — curated already covers most of what users care about; the full pool is high-volume but noisy.

```bash
# Pull everything from the last 24h (user asked "show me everything from today")
since=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=all&since=$since&take=100"
```

### Pull items by category

5 categories (the items API uses English slugs; the daily API's `section.label` is Chinese — render in English when displaying):

| `items?category=` | `daily.sections[].label` (raw) | Render as |
|---|---|---|
| `ai-models` | `模型发布/更新` | Model releases / updates |
| `ai-products` | `产品发布/更新` | Product releases / updates |
| `industry` | `行业动态` | Industry news |
| `paper` | `论文研究` | Papers / research |
| `tip` | `技巧与观点` | Tips & takes |

**If the user asks "what have WeChat Official Accounts (公众号) posted lately": the items API does NOT include 公众号 (the `mp_hot` source has its own front-end page at `/mp`). The Skill currently can't answer that — point the user at `https://aihot.virxact.com/mp` to view the WeChat OA hits page.**

```bash
# Example: pull the latest 50 AI papers (default curated + paper category)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&category=paper&take=50" \
  | jq '.items[] | {title, source, publishedAt, url}'

# Example: model releases inside the curated pool
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&category=ai-models&take=20"

# Exception: only when the user explicitly says "all papers / all model releases" do you use mode=all
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=all&category=paper&take=100"
```

### Pull items by time window (the past N days)

> **Key rule**: when the user asks for "**recent** X" (recent model releases / recent AI papers / recent OpenAI etc.), pass a `since` parameter to narrow the window to what the user actually meant ("past 3 days" → 3d, "yesterday" → 1d, "past week" → 7d).
>
> **Server-side fallback**: the items API defaults to `since=now-7d` server-side (a hard cap to protect the server), so even if the Skill omits `since` entirely, you'll only get the past 7 days — never months-old items. But **still pass `since` explicitly**: ① for "past 3 days", explicit 3d is more accurate than letting the server default to 7d ② your output's metadata can mention the time window in plain language ③ it makes intent clear and matches the publicly-advertised "max 7 days" surface.

```bash
# Pull the past 7 days of curated model releases (user asked "recent model releases")
since=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&category=ai-models&since=$since&take=100"

# Pull the past 3 days of curated items (user explicitly said "the past 3 days")
since=$(date -u -v-3d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&since=$since&take=100"
```

**Exception**: if the user explicitly says "**all / everything / full list / including older**" → switch `mode` to `all`, may omit `since`; if the user says "**show me the curated picks**" (asking about the curated pool, not a time window), `mode` stays `selected` and you may also omit `since`. But as soon as the sentence contains "recent / latest / these last few days / this week", **default to `since` + `mode=selected`**.

### Pagination (cursor)

`/api/public/items` responses include `nextCursor` (an opaque token). To request the next page, pass it back verbatim as the `cursor` parameter.

```bash
# Page 1
resp1=$(curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=all&take=100")
echo "$resp1" | jq '.items | length'   # 100

# Page 2
cursor=$(echo "$resp1" | jq -r '.nextCursor')
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=all&take=100&cursor=$cursor"
```

Stop paginating when `hasNext = false` or `nextCursor = null`. **The cursor is an opaque token — treat it as a black box; do not parse, increment, or reuse across endpoints.**

### Keyword search ("what did OpenAI ship lately" / "Sora-related" / "RAG papers")

The API directly supports server-side keyword search — the `q` parameter does ILIKE matching across `title`, Chinese `title`, and Chinese `summary`, backed by a PostgreSQL pg_trgm GIN index (2–6ms). **Do not fall back to the "pull a batch + client-side `jq grep`" pattern** — that only sees hits inside the first 100-row pool, and any keyword outside that pool will appear to not exist at all.

```bash
# Find OpenAI's recent items (covers the full pool, not just the first 100)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?q=OpenAI&take=30"

# Find all Sora-related AI items (any title or summary containing "Sora")
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?q=Sora"

# Find RAG papers (category constraint + keyword)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?category=paper&q=RAG&take=30"

# Keyword + time window (Anthropic's curated items from the past 3 days)
SINCE=$(date -u -v-3d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&q=Anthropic&since=$SINCE"
```

`q` constraints:
- At least 2 characters (single-character GIN trigrams degrade to a full-table scan, so the server treats it as no-search)
- Up to 200 characters (auto-truncated past that)
- Orthogonal to other params (`mode` / `category` / `since` / `take` / `cursor`) — you can stack "curated + papers + keyword + within 7 days"
- Shares the 600 req/min rate limit with other requests

## Response shapes

### `/api/public/daily` returns

```json
{
  "date": "2026-05-07",
  "generatedAt": "2026-05-07T00:01:23.456Z",
  "windowStart": "2026-05-06T00:00:00.000Z",
  "windowEnd":   "2026-05-07T00:00:00.000Z",
  "lead": { "title": "...", "leadParagraph": "..." },
  "sections": [
    {
      "label": "模型发布/更新",
      "items": [
        {
          "title": "...",
          "summary": "...",
          "sourceUrl": "https://...",
          "sourceName": "OpenAI Blog"
        }
      ]
    }
  ],
  "flashes": [
    { "title": "...", "sourceName": "...", "sourceUrl": "...", "publishedAt": "..." }
  ]
}
```

`sections[].label` is one of 5 fixed Chinese values: `模型发布/更新` / `产品发布/更新` / `行业动态` / `论文研究` / `技巧与观点` — render them in English (see category table). `lead` is `null` for very rare daily briefs.

### `/api/public/dailies` returns

```json
{
  "count": 14,
  "items": [
    { "date": "2026-05-07", "generatedAt": "...", "leadTitle": "..." }
  ]
}
```

### `/api/public/items` returns

```json
{
  "count": 50,
  "hasNext": true,
  "nextCursor": "eyJhIjoxNzE0OTk1MjAwMDAwLCJpIjoiY205eHl6MTIzIn0",
  "items": [
    {
      "id": "cm9abc456def789ghi012jkl3",
      "title": "Chinese title (LLM-normalized)",
      "title_en": "Original English title (only present when it differs from `title`, otherwise null)",
      "url": "https://...",
      "source": "OpenAI Blog",
      "publishedAt": "2026-05-07T15:30:00.000Z",
      "summary": "Chinese summary (LLM-generated)",
      "category": "ai-models"
    }
  ]
}
```

Field invariants:

- Always present: `id` / `title` / `url` / `source`
- May be null: `title_en` / `summary` / `publishedAt` / `category`
- `category` value set: `ai-models` / `ai-products` / `industry` / `paper` / `tip` / `null`
- `publishedAt`: ISO 8601 UTC (with trailing `Z`)
- `id`: cuid string (25 characters) — **do not assume numeric**

## Output format for the user

> ⚠️ **Core principle**: this section is **the final content shown directly to the user** — it must be markdown, well-formatted, and **in plain English a normal person can understand**. Write a clean English news brief, **not an API debug log**.
>
> All "endpoint paths / raw params like `mode=selected` / rate limits / nginx caching / cursor / hasNext" infrastructure details **must NOT appear** in user-visible output. **Plain-language** metadata (time window / item count / "sorted by publish time descending") may stay — the test is: can the user understand it directly? Yes → keep; no → drop.
>
> **Translation rule**: the upstream `title` / `summary` are Chinese. Translate them into natural, idiomatic English when rendering — do not paste raw Chinese into the user-visible brief. Prefer `title_en` if present and faithful; otherwise translate `title`. Keep `source` and `url` verbatim. Translate the five Chinese section labels via the table above.

### Daily-brief style output (when using daily / daily/{date})

```markdown
**AI HOT Daily Brief · 2026-05-07**

## Model releases / updates
1. **<title in English>** — <source>
   <summary, condensed to ≤25 words>
   <url>

## Product releases / updates
2. ...

## Industry news
3. ...

## Papers / research
4. ...

## Tips & takes
5. ...

## Flashes (only if `flashes` has content)
- <flash.title in English> — <flash.source> (<flash.publishedAt in plain language>)
```

**Numbering runs continuously across the whole document** (1, 2, 3 ... N) — do not restart inside each `##`. This way the user can immediately see "27 items today".

### List-style output (when using the items endpoint)

**Default: group by category + global numbering** — users have already formed an expectation around the five-section "Models / Products / Industry / Papers / Tips" structure (from the daily brief), so when categories are mixed this structure feels most natural:

```markdown
**AI HOT — Top 30 curated**

## Model releases / updates
1. **<title in English>** — <source>
   2 hours ago
   <summary in English>
   <url>

## Product releases / updates
2. **<title in English>** — <source>
   ...

3. ...

## Industry news
4. ...
```

**When there's only 1 category** (user explicitly asked for "AI papers" / "model releases" / etc.), use a flat numbered list:

```markdown
**AI HOT — AI papers from the past week** (2026-05-01 ~ 2026-05-08)

1. **<title in English>** — <source>
   <summary in English>
   <url>

2. ...
```

### Subheaders / metadata: plain language only

**OK** (the user can read these directly):

- "Window 2026-05-05 ~ 2026-05-07"
- "All items in the past 3 days matching the OpenAI keyword"
- "Sorted by publish time descending"
- "Total 50 items"
- "Today's 5/8 daily isn't generated until 08:00 Beijing time — showing the 5/7 edition for now"

**NOT OK** (infrastructure leakage — never write these):

- ❌ Raw param names like `mode=selected` / `category=paper` / `take=30`
- ❌ Endpoint paths like `/api/public/items?since=2026-04-30T18:39:31Z&take=50`
- ❌ "Rate limit 600 req/min" / "nginx cache 60s" / "x-nginx-cache: HIT"
- ❌ "cursor" / "hasNext=true" / "needs cursor pagination or a tighter `since` window"
- ❌ Any HTTP status codes / cache states / backend mechanism descriptions

Cite the source at most once: **"Data from aihot.virxact.com"** — or skip it entirely (the user already knows the source since they're using the skill).

### Translate timestamps to plain language

`publishedAt` is ISO 8601 UTC. When displaying it, you **must** convert to a relative/absolute form the user can scan (Beijing time is the editorial reference, but render in the user's idiom):

| Internal value | Show to user |
|---|---|
| `2026-05-08T01:48:00.000Z` | "today 9:48 AM (Beijing)" / "2 hours ago" |
| `2026-05-07T18:08:17.000Z` | "today 2:08 AM (Beijing)" / "10 hours ago" |
| `2026-05-06T16:43:00.000Z` | "5/7 00:43 (Beijing)" / "yesterday" |

**Do not** display raw ISO strings like `2026-05-07T15:30:00.000Z` — users can't read them.

### `title` vs `title_en`

The output is in English, so prefer `title_en` whenever it exists and faithfully reflects the source. If `title_en` is null, translate `title` (Chinese) into natural English. **Do not** show both; **do not** paste raw Chinese into the brief unless the user explicitly asks for the original.

## Common error handling

- `{"error":"No daily report available yet."}` (HTTP 404): today's daily isn't generated yet (before 08:00 Beijing time). Suggest pulling yesterday's: `curl /api/public/daily/{yesterday's date}`
- `{"error":"Invalid date format..."}` (HTTP 400): date must be `YYYY-MM-DD`, UTC-anchored
- Common 400s on the items endpoint:
  - `"invalid mode (must be 'selected' or 'all')"`
  - `"invalid category (must be one of: ai-models, ai-products, industry, paper, tip)"`
  - `"invalid since (must be ISO date, not in future)"`
  - `"invalid take (must be integer 1-100)"`
- HTTP 429 (rate-limited): a single IP exceeded 600 req/min. Call serially + add ~200ms between paginated requests.

## Don'ts

- **Don't route broad questions like "what's in AI today / past 24h big news / anything new in AI" to `daily`** — those are rolling time windows, while `daily` is a fixed one-day product sliced at UTC midnight (e.g. 5/6–5/7 as a whole day). The time precision doesn't match. **Default to `mode=selected + since=<semantic window>`.** Only when the user literally says "daily" / "日报" should you hit `daily`.
- **Don't default to `mode=all` unless the user says "all / complete / everything / full / 全部 / 完整 / 所有 / 全量"** — curated already covers most of what they care about; the full pool is high-volume but noisy and includes secondary items. Default `mode=selected`; only switch to `mode=all` when the user explicitly orders "the full thing".
- Don't try to guess or fabricate content — always defer to API responses.
- Don't quote `summary` as if it were the original text — summaries are LLM-generated; for quotation, go back to `url` / `sourceUrl` to verify.
- Don't poll high-frequency — the daily brief refreshes once a day at 08:00; the items endpoint has a 5-minute server-side cache. When the user asks the same question repeatedly, don't re-hit the API.
- Don't slam pagination in parallel — serial + natural intervals.
- Don't try to parse, increment, or cross-endpoint reuse the cursor — it's an opaque token; the internal encoding format is unstable and may change without notice.
- For company-axis or keyword queries, use server-side `?q=<term>`. Do not fall back to "pull a batch + client-side `jq grep`" (that only sees the first 100-row pool and will miss hits).
- **When the user asks for "recent N days of X", pass `since=<N days ago>` explicitly** (clearer intent + lets metadata describe the time window in plain language). Without `since`, the server defaults to 7d, so you won't get stale items, but for "past 3 days" the server's default 7d would include 4 extra days you didn't want.
- **Don't expose endpoint paths / raw params / rate limits / cache TTLs / cursor / hasNext or other infrastructure details in user-visible output** — those are for developers, not users. See "Output format → Subheaders / metadata" above.
- **Don't drop each item's URL when compressing / merging across days / merging across sections** — even if you collapse 3 daily briefs into a 5-section summary for length, every item must retain its `url` (after the title or on its own line). A user who sees an item with no URL can't trace back to the source — that item is effectively untrustworthy.
- **Don't cite "endpoint paths / call details" as your source** — cite `<source>` (e.g. "OpenAI Blog", "Anthropic Newsroom", "X: Berry Xia"), not `GET /api/public/items?...`.
- **Don't paste raw Chinese titles or summaries into the user-visible brief** — translate to natural English. If the user explicitly asks for the original Chinese, then show it.
