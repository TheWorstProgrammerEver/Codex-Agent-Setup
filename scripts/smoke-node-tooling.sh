#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cd "$tmp_dir"

npm init -y >/dev/null
npm install --save-dev vite vitest typescript >/dev/null
npm install @supabase/supabase-js >/dev/null

node --version
npm --version
npm exec vite -- --version
npm exec vitest -- --version
node --input-type=module -e "import { createClient } from '@supabase/supabase-js'; const client = createClient('https://example.supabase.co', 'anon-key'); if (!client) throw new Error('Supabase client was not created');"
