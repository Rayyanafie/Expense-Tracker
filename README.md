# Tracker Expense — AI Expense Tracker Bot for Telegram

**Snap a receipt, type "Coffee 35k", or ask "how much did I spend on food this month?" — Tracker Expense does the rest.**

A personal portfolio project: a 4-workflow n8n suite that turns Telegram messages and receipt photos into structured expenses in PostgreSQL, and answers plain-language questions about your spending — with per-user data isolation, guarded AI-generated SQL, and an error-alerting safety net.

Built with [n8n](https://n8n.io), Gemini (vision + text), and PostgreSQL (pgvector-enabled).

---

## The suite at a glance

| Workflow | Role |
|---|---|
| `Tracker Expense` | Orchestrator — Telegram trigger, intent classification, command routing |
| `Sub-Tracker` | Worker — receipt photo OCR + manual text parsing → structured expense rows |
| `Sub-Query` | Worker — natural-language question → guarded SQL → formatted spending answer |
| `Tracker Expense Log` | Safety net — pings the admin whenever any workflow errors |

```
┌─────────────────────────────────────────────────────────────┐
│                      Tracker Expense                          │
│  Telegram message/callback → route → Gemini intent classify  │
│     ├─ /start            → welcome + quick-start guide        │
│     ├─ delete_<id> cb    → DELETE scoped to sender → confirm  │
│     ├─ TRACK + photo     → Sub-Tracker (vision OCR)           │
│     ├─ TRACK + text      → Sub-Tracker (manual parse)         │
│     └─ QUERY             → Sub-Query (SQL + format)           │
└──────────────┬──────────────────────────┬─────────────────────┘
               │                          │
     ┌─────────▼─────────┐      ┌─────────▼──────────┐
     │    Sub-Tracker     │      │     Sub-Query      │
     │ receipt/manual →   │      │ question → Gemini  │
     │ Gemini JSON →      │      │ → JS guard → SQL   │
     │ upsert user →      │      │ → summarize → Rp   │
     │ INSERT tx → reply  │      └────────────────────┘
     │ 🗑️ button (3 min)  │
     └────────────────────┘
        Every failure → Tracker Expense Log → admin alert
```

---

## What makes it interesting

### 1. Receipt scanning that respects what *you* actually bought
Send a photo of a restaurant bill with a caption like **"mujair, kangkung, nasi"** and the extractor prices *only those items* from the receipt — it never imports the whole bill. No caption? It extracts everything and trusts the receipt total.

- Currency symbols stripped, Indonesian abbreviations parsed: `Rp 35.000` → `35000`, `35k` → `35000`, `50rb` → `50000`
- Structured `line_items` stored as `jsonb`, single-quotes safely escaped on insert

### 2. Text entry is as easy as a message
Type **"Coffee 35k"** → Sub-Tracker parses it into a dated, categorized expense with today's date/time. No forms, no menus.

### 3. Ask questions in plain language
- *"How much did I spend on Food & Beverage this month?"*
- *"Show me my transactions this week."*
- *"What was my biggest expense recently?"*
- *"How much did I spend on Pertamax total?"* — it searches inside `line_items` JSON too

Gemini writes the SQL against a strict schema (only known columns, `line_items` searched via `::text ILIKE`), a JavaScript guard **blocks anything but a single SELECT** (no DROP/DELETE/UPDATE), and the query is wrapped in a user-isolation CTE scoped to your Telegram ID — you only ever see *your* expenses.

### 4. Undo built in
Every logged expense gets a **🗑️ Delete Entry** button — which expires after 3 minutes via a Wait node + `editMessageText` swap. Accidental uploads are one tap to fix; stale buttons don't linger.

### 5. Errors page the admin
The suite routes every execution failure to `Tracker Expense Log`: workflow name, failing node, error message, execution ID — straight to the owner's Telegram. No silent failures.

### 6. Cost discipline
Gemini only runs where judgment is needed (classification, extraction, SQL, formatting). Everything else is n8n-native nodes + Postgres.

---

## Repository layout

```
tracker-expense/
├── README.md
├── Tracker Expense.json          ← import this first (orchestrator)
├── Sub-Tracker.json              ← worker: receipt + manual parsing
├── Sub-Query.json                ← worker: NL → guarded SQL
├── Tracker Expense Log.json      ← error alerting (set as error workflow)
└── database/
    └── schema.sql                ← users + transactions DDL (incl. jsonb line_items)
```

> **Import order:** all four files, then open *Tracker Expense → Settings → Error Workflow* and select *Tracker Expense Log* (workflow IDs are regenerated on import, so this one link must be re-pointed once).

---

# 🎓 Tutorial: set it up from scratch

Requirements: an n8n instance (Docker), a Telegram bot token, a Google Gemini API key, and PostgreSQL.

## 1. Get a Telegram bot token (via @BotFather)
1. Chat with [**@BotFather**](https://t.me/BotFather) → `/newbot`
2. Name it, username must end in `bot`
3. Copy the **HTTP API token** — keep it private, it lives only in n8n credentials

## 2. Get a Gemini API key
1. [Google AI Studio](https://aistudio.google.com/apikey) → **Create API key**
2. Copy the key (`AIza...`) — free tier is fine for testing

## 3. PostgreSQL schema
```sql
CREATE TABLE users (
  telegram_id  BIGINT PRIMARY KEY,
  username     TEXT,
  first_name   TEXT,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE transactions (
  id            SERIAL PRIMARY KEY,
  telegram_id   BIGINT NOT NULL REFERENCES users(telegram_id),
  date          DATE NOT NULL,
  time          TIME,
  total_amount  INTEGER NOT NULL,
  merchant      TEXT,
  category      TEXT,
  line_items    JSONB DEFAULT '[]'::jsonb
);
CREATE INDEX idx_transactions_owner ON transactions (telegram_id, date);
```

## 4. Run n8n
```bash
docker network create n8n_default 2>/dev/null || true
docker run -d --name n8n --network n8n_default -p 5678:5678 \
  -v n8n_data:/home/node/.n8n n8nio/n8n
```
Open http://localhost:5678, create your account, add your Postgres host to the same Docker network.

## 5. Import the workflows
In n8n: **Workflows → Import from File** — import `Sub-Tracker.json`, `Sub-Query.json`, `Tracker Expense Log.json`, then `Tracker Expense.json`. Save each once (webhook IDs regenerate).

## 6. Connect credentials
| Credential | Where | Fill with |
|---|---|---|
| `telegramApi` | all Telegram nodes | your bot token |
| `googlePalmApi` | Gemini nodes | your Gemini API key |
| `postgres` | SQL nodes | your Postgres connection |

Then re-point **Tracker Expense → Settings → Error Workflow → Tracker Expense Log**, and flip each workflow to **Active**.

## 7. Try it
- `/start` → guide
- Send a **receipt photo** (try a caption with specific items)
- Type **"Coffee 35k"**
- Ask **"how much did I spend this month?"**

---

## Privacy note

This repository is scrubbed for public sharing: credential IDs blanked, personal chat IDs generalized, webhook IDs and pinned test data removed. Real expense data lives only in your own PostgreSQL — never in these exports.

## Disclaimer

Personal portfolio project — no uptime guarantee, AI extraction can be wrong, use at your own risk. Not financial advice. 😄
