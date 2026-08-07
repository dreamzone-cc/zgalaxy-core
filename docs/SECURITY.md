# Security

Security policy for the zgalaxy-core repository.

## 1. Never commit secrets

The following MUST never be committed to this repository (tracked or
untracked files):

* `cloudflare_apiToken` / any Cloudflare API token
* Any API key, password, or credential
* `identity.secret`, signing keys, or private keys
* Server SSH usernames/passwords
* `local.conf` from production servers (may contain auth settings)

These live **only** on the production servers (in the ZGALAXY `config/`
directory, e.g. `/home/<deploy-user>/zgalaxy/config/`) and are protected by
root-only file permissions.

The `.gitignore` includes guards for common secret file names:
`*.api_token`, `*cloudflare*config*`, `*.secret`, `*.key`, `config/`, `.env`,
`.env.*`.

## 2. Verification before pushing

Run this from the repository root before any `git push`:

```bash
# Confirm no Cloudflare token or API keys
rg -rn "cfat_|apiToken|api[_-]?key|secret" --glob '!ext/**' --glob '!rustybits/**' .

# Confirm no server usernames (e.g. "dzNNN")
rg -rn "dz[0-9]+" .

# Confirm no passwords (use a pattern, not the real value)
rg -rn "<your-real-password>" .

# Or block common secret-looking strings
rg -rn "[A-Za-z0-9]{8,}[@#!$%^&*]" --glob '*.json' .
```

Any output means **stop** — remove the file/value before pushing.

## 3. If a secret was exposed

1. Rotate the credential immediately (Cloudflare tokens, passwords, keys).
2. Remove it from git history (see GitHub documentation on rewriting
   history / `git filter-repo`).
3. Notify the repository owner.

## 4. Production config directory

The ZGALAXY control-plane configuration (`cloudflare_config.json`,
`ddns_config.json`, `domains.json`, `.secret_key`) exists only on the ZGALAXY
server in its `config/` directory. It is **not** part of this repository and
must never be copied in.
