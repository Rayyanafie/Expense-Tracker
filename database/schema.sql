-- Tracker Expense — PostgreSQL schema
-- Mirrors the live tables used by the n8n workflow suite.
-- Run against your n8n/expense database:  psql -U postgres -d <db> -f schema.sql

-- Users are created implicitly by Sub-Tracker (upsert on first expense).
CREATE TABLE IF NOT EXISTS users (
  telegram_id BIGINT PRIMARY KEY,            -- Telegram user id (scoping key for isolation)
  username    VARCHAR(64),                   -- @username, if set
  first_name  VARCHAR(64),
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- One row per logged expense.
CREATE TABLE IF NOT EXISTS transactions (
  id           SERIAL PRIMARY KEY,
  telegram_id  BIGINT NOT NULL REFERENCES users(telegram_id) ON DELETE CASCADE,
  date         DATE NOT NULL,                -- receipt date or today (manual entry)
  time         TIME,                         -- null when not visible on receipt
  total_amount INTEGER NOT NULL,             -- rupiah, no decimals (Rp 35.000 -> 35000)
  merchant     VARCHAR(50),                  -- store/person name, or 'Unknown'
  category     VARCHAR(50) NOT NULL,         -- one of the allowed categories
  line_items   JSONB DEFAULT '[]'::jsonb,    -- [{"name": "...", "price": N}, ...]
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Fast per-user date-range queries (Sub-Query monthly/weekly totals).
CREATE INDEX IF NOT EXISTS idx_transactions_owner_date
  ON transactions (telegram_id, date);
