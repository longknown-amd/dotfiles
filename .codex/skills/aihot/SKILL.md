---
name: aihot
description: >
  Fetch curated AI HOT news briefs and item feeds. Trigger whenever the user
  asks for today’s AI news, AI HOT picks, AI industry updates, recent AI model
  releases, or similar queries that need fresh information.
---

# AI HOT Skill

This skill queries https://aihot.virxact.com for the latest curated and full AI
news feeds. No browser or API key is required.

> **Language note:** The upstream data mixes English source titles with Chinese
> summaries. Always render user-facing output in natural English. Translate any
> Chinese titles or summaries on the fly while leaving `source` names and URLs
> verbatim. Section labels returned in Chinese (`模型发布/更新`, etc.) must also be
> rendered in English (see the category table below).

## Prerequisite: Send a Browser User-Agent

The `/api/public/*` endpoints reject generic `curl/X.Y` user agents. Set and use
a browser UA header on every API request:

```bash
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/daily"
```

The installation files under `/aihot-skill/` are exempt and can be fetched with
the default UA, but every `/api/public/*` call must carry the browser UA.

## Which Endpoint to Use

Default to the curated items feed plus an appropriate `since` window. Only fall
back to other endpoints when the user explicitly asks:

| User intent | Endpoint |
| --- | --- |
| “What’s new in AI today / past 24 h / lately” | `GET /api/public/items?mode=selected&since=<ISO timestamp>` |
| “Show me the AI HOT daily” | `GET /api/public/daily` |
| “Daily for YYYY-MM-DD” | `GET /api/public/daily/{YYYY-MM-DD}` |
| “List recent dailies” | `GET /api/public/dailies?take=N` |
| “Show everything / full list / all items” | `GET /api/public/items?mode=all[&since=…]` |
| “Model releases / product launches / AI papers” | `GET /api/public/items?mode=selected&category=<slug>&since=…` |
| “What did OpenAI / Anthropic ship” (company keywords) | `GET /api/public/items?q=<keyword>[&since=…]` |

Remember that `mode=all` is noisier; do not use it unless the user explicitly
says “all,” “complete,” or similar.

### Category Slugs

| Query parameter | Chinese label | Render as |
| --- | --- | --- |
| `ai-models` | `模型发布/更新` | Model releases / updates |
| `ai-products` | `产品发布/更新` | Product releases / updates |
| `industry` | `行业动态` | Industry news |
| `paper` | `论文研究` | Papers / research |
| `tip` | `技巧与观点` | Tips & takes |

The WeChat Official Account feed (`/mp`) is not exposed via the API; point the
user to the website when they ask for 公众号 coverage.

### Time Windows

`since` can reference at most the trailing 7 days; the server clamps anything
older. Explicitly choose the window that matches the user’s phrasing (“past
24 hours”, “last 3 days”, etc.).

Example helper:

```bash
SINCE=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&since=$SINCE&take=50"
```

### Pagination

`/api/public/items` returns `hasNext` and `nextCursor`. Pass the cursor back
verbatim for subsequent pages:

```bash
resp=$(curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&take=100")
cursor=$(echo "$resp" | jq -r '.nextCursor')
curl -sH "User-Agent: $UA" "https://aihot.virxact.com/api/public/items?mode=selected&take=100&cursor=$cursor"
```

Stop when `cursor` is `null` or `hasNext` is false.

## Response Shapes

### Daily Endpoint

```json
{
  "date": "2026-05-07",
  "sections": [
    {
      "label": "模型发布/更新",
      "items": [
        {
          "title": "Chinese title",
          "summary": "Chinese summary",
          "sourceName": "OpenAI Blog",
          "sourceUrl": "https://…"
        }
      ]
    }
  ],
  "flashes": [...]
}
```

### Items Endpoint

```json
{
  "items": [
    {
      "id": "cm1abc…",
      "title": "Chinese title",
      "title_en": "English source title (optional)",
      "summary": "Chinese summary (optional)",
      "source": "OpenAI Blog",
      "url": "https://…",
      "publishedAt": "2026-05-07T15:30:00.000Z",
      "category": "ai-models"
    }
  ],
  "nextCursor": "opaque token or null"
}
```

`title_en` is only present when the source already published an English title.
Prefer `title_en` if it exists; otherwise translate `title`.

## Rendering Output

> **Never** expose raw endpoint URLs, query parameters, rate-limit details, or
> cursor tokens to the user. Deliver a clean English brief.

### Daily Brief Format

Group by the five sections, translate the labels, and use a single running
numbering sequence:

```markdown
**AI HOT Daily Brief · 2026-05-07**

## Model releases / updates
1. **Title (translated)** — Source  
   2 hours ago  
   Summary (translated)  
   URL
```

Include the “Flashes” section only when the API returns entries.

### Items Feed Format

Group by category when multiple categories appear; otherwise use a flat numbered
list. Always translate timestamps to human-readable form (e.g., “today 17:32
(Beijing)” or “2 hours ago”) instead of exposing raw ISO strings.

### Translation Rules

- Translate Chinese titles and summaries into idiomatic English.
- Keep `source` names and URLs as-is.
- Call out the time window in plain language (e.g., “Window 2026-05-05 ~
  2026-05-07”).

### Source Attribution

At most once per response, mention that data came from AI HOT (e.g., “Data:
aihot.virxact.com”). Do not print endpoint paths or query strings.

## Error Handling

- 404 with `"No daily report available yet."`: Today’s daily isn’t published
  (the publish job runs 08:00 Beijing). Suggest yesterday’s date.
- 400 errors: fix the bad parameter (bad mode/category/since/take).
- 429 (rate limit): throttle requests; the limit is 600 req/min per IP.

## Don’ts

- Don’t improvise “news” from training data—always call the API for fresh info.
- Don’t default to `mode=all` for broad prompts.
- Don’t reveal raw API debug output to the user.
- Don’t drop URLs; every item must link back to the source.
- Don’t keep raw Chinese text in the response unless the user explicitly asks.
