# Railway Admin Setup

How to set up admin access on a Paperclip deployment running on Railway with embedded PostgreSQL.

## Prerequisites

- Railway CLI installed and linked to the project (`worthy-curiosity`)
- Access to the Railway domain (e.g. `https://paperclipaiserver-production-a86c.up.railway.app`)

## Steps

### 1. Create an account via the web UI

Go to your Railway domain and use the "Create account" flow to sign up with email/password.

### 2. SSH into the server container

```bash
railway ssh -s "@paperclipai/server"
```

### 3. Verify the embedded PostgreSQL is running

```bash
ls /tmp/.s.PGSQL*
```

You should see `/tmp/.s.PGSQL.54329` — this confirms the embedded DB is listening on port 54329.

### 4. Find the postgres driver path

The container uses pnpm. The `postgres` package is in the pnpm store:

```bash
find /app/node_modules/.pnpm -path "*/postgres/src/index.js" 2>/dev/null | head -1
```

As of this writing: `/app/node_modules/.pnpm/postgres@3.4.8/node_modules/postgres/src/index.js`

### 5. Look up the user ID

**Important:** The table is `"user"` (not `users`), and it has no `id` column — use `SELECT *`.

Long commands break due to Railway SSH line wrapping. **Write to a file instead of using inline commands.**

```bash
vim /tmp/lookup.mjs
```

```js
import postgres from "/app/node_modules/.pnpm/postgres@3.4.8/node_modules/postgres/src/index.js";
const sql = postgres("postgres://paperclip:paperclip@127.0.0.1:54329/paperclip");
const r = await sql`SELECT * FROM "user"`;
console.log(JSON.stringify(r, null, 2));
await sql.end();
```

```bash
node /tmp/lookup.mjs
```

Copy the user ID from the output.

### 6. Promote the user to instance admin

```bash
vim /tmp/promote.mjs
```

```js
import postgres from "/app/node_modules/.pnpm/postgres@3.4.8/node_modules/postgres/src/index.js";
const sql = postgres("postgres://paperclip:paperclip@127.0.0.1:54329/paperclip");
var u = "PASTE_USER_ID_HERE";
var r = await sql`INSERT INTO instance_user_roles (id, user_id, role, created_at, updated_at) VALUES (gen_random_uuid(), ${u}, ${"instance_admin"}, NOW(), NOW()) RETURNING *`;
console.log(JSON.stringify(r));
await sql.end();
```

Replace `PASTE_USER_ID_HERE` with the actual user ID, save, then:

```bash
node /tmp/promote.mjs
```

### 7. Log in

Refresh the Railway domain and log in with the account you created. You now have full admin access and should see the onboarding screen.

## Password Reset (if needed)

If you need to reset a password, the `account` table stores scrypt hashes in `salt:hash` format.

```bash
vim /tmp/reset.mjs
```

```js
import postgres from "/app/node_modules/.pnpm/postgres@3.4.8/node_modules/postgres/src/index.js";
import crypto from "node:crypto";
const sql = postgres("postgres://paperclip:paperclip@127.0.0.1:54329/paperclip");
var password = "your-new-password";
var s = crypto.randomBytes(16).toString("hex");
var h = crypto.scryptSync(password, s, 64).toString("hex");
var u = "PASTE_USER_ID_HERE";
var r = await sql`UPDATE account SET password = ${s+":"+h} WHERE user_id = ${u} RETURNING *`;
console.log(JSON.stringify(r));
await sql.end();
```

**Note:** The default Node.js scrypt parameters may not match better-auth's parameters. If login fails after reset, create a new account via the UI instead and promote that one.

## Troubleshooting

### Line wrapping breaks long commands

Railway SSH terminals insert newlines into long strings, breaking `node -e` commands. **Always write `.mjs` files with vim and run them with `node`** instead of using inline one-liners.

### `psql` not available

The container doesn't ship `psql`. The embedded postgres binary is at:

```bash
ls /app/node_modules/.pnpm/@embedded*linux*/node*/*/linux*/native/bin/
```

It only has `initdb`, `pg_ctl`, and `postgres` — no `psql`. Use the node + `postgres` driver approach above.

### `pg` module not found / `require` not defined

- The monorepo uses `"type": "module"` — use `.mjs` files or `--input-type=module`
- The `pg` package isn't directly resolvable. Use the `postgres` package with its full pnpm store path.
- Don't use `require()` — use `import`.

### `relation "users" does not exist`

The table is `"user"` (singular, quoted because it's a reserved word in postgres).

### Instance admin required error after login

The `instance_user_roles` table must have a row with `role = 'instance_admin'` for your user. Verify:

```bash
vim /tmp/check.mjs
```

```js
import postgres from "/app/node_modules/.pnpm/postgres@3.4.8/node_modules/postgres/src/index.js";
const sql = postgres("postgres://paperclip:paperclip@127.0.0.1:54329/paperclip");
const r = await sql`SELECT * FROM instance_user_roles`;
console.log(JSON.stringify(r, null, 2));
await sql.end();
```

```bash
node /tmp/check.mjs
```

Make sure the `user_id` in the output matches the user you're logging in as.

### Embedded postgres not running

```bash
cat /proc/*/cmdline 2>/dev/null | tr '\0' ' ' | grep postgres
```

If no postgres processes appear, the app hasn't booted. Check service logs:

```bash
railway logs -s "@paperclipai/server"
```
