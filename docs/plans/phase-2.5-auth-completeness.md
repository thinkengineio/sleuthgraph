# Phase 2.5 — Auth UI Completeness Implementation Plan

**Goal:** Fill the auth-UX gaps left by Phase 2. Today users can only log in; they can't register (even with `AUTH_ALLOW_SIGNUP=true`) and they can't reset a forgotten password. After this phase a self-host operator can stand up the stack, create additional users, and let people recover their own passwords.

**Scope boundary:** OIDC full login/callback flow is bigger (PKCE, discovery doc, state management) — deferred to Phase 2.6. This phase is local-auth only.

**Architecture:**
- Backend: mount fastapi-users' bundled `get_reset_password_router` + `get_verify_router`. Both are already wired through `UserManager.reset_password_token_secret` / `verification_token_secret` (HKDF-derived in Phase 2). Email delivery → a pluggable `EmailSender` interface with an `ConsoleEmailSender` default that prints to stderr (MVP; SMTP delivery is a later follow-up).
- Frontend: 3 new pages + supporting UI. Matches existing Mantine + @mantine/form patterns.

**Repos:** `~/sleuthgraph-api/` (backend) + `~/sleuthgraph-web/` (frontend), parallelizable.

---

## Backend work (Phase 2.5-api)

**Files:**
- Modify: `src/sleuthgraph/auth/manager.py` — implement `on_after_forgot_password` + `on_after_request_verify` callbacks that hand the token off to an `EmailSender`
- Create: `src/sleuthgraph/auth/email.py` — `EmailSender` protocol + `ConsoleEmailSender` default (logs `[email] to=... subject=... body=...` with reset link)
- Modify: `src/sleuthgraph/main.py` — mount reset + verify routers conditionally when `AUTH_ALLOW_PASSWORD_RESET` and `AUTH_ALLOW_EMAIL_VERIFY` are truthy
- Modify: `src/sleuthgraph/config.py` — add two env flags + `AUTH_FRONTEND_BASE_URL` (for links in email)
- Tests: `tests/test_auth_reset_password.py`, `tests/test_auth_verify_email.py`

**Endpoints mounted:**
- `POST /auth/forgot-password` body `{email}` → 202 (always, to prevent email enumeration)
- `POST /auth/reset-password` body `{token, password}` → 200 or 400
- `POST /auth/request-verify-token` body `{email}` → 202
- `POST /auth/verify` body `{token}` → 200 or 400

All of these are already implemented by fastapi-users; we just `include_router`.

**Gates:**
- `AUTH_ALLOW_PASSWORD_RESET` (default `true` — contrast with `AUTH_ALLOW_SIGNUP=false`; reset is low-risk enough to default on)
- `AUTH_ALLOW_EMAIL_VERIFY` (default `false` — most self-hosters don't need this)

**ConsoleEmailSender** (MVP):
```python
class ConsoleEmailSender:
    async def send_password_reset(self, to: str, token: str) -> None:
        link = f"{get_settings().auth_frontend_base_url}/reset-password?token={token}"
        log.info("[email] to=%s subject='Reset your Sleuthgraph password' link=%s", to, link)
```

Operator reads the link from the API container logs to paste in the browser. SMTP comes later.

Tests verify: forgot-password fires the callback exactly once, email sender receives the right token, reset-password with bad token → 400, with good token → password updated + can log in.

Target: ~6 new tests, ~10 min of implementation.

---

## Frontend work (Phase 2.5-web)

**Files:**
- Create: `app/register/page.tsx` — signup form (visible only if `AUTH_ALLOW_SIGNUP=true` from oidc-status endpoint; else show "Registration is disabled — contact your administrator")
- Create: `app/forgot-password/page.tsx` — email input → POST /auth/forgot-password → "Check your email" neutral message
- Create: `app/reset-password/page.tsx` — reads `?token=` from query → new password form → POST /auth/reset-password → redirect to /login
- Modify: `app/login/page.tsx` — add "Forgot your password?" link + "Don't have an account? Register" link (conditional on signup enabled)
- Modify: `lib/api.ts` — add `apiRegister(email, password, name?)`, `apiForgotPassword(email)`, `apiResetPassword(token, password)`

**Backend signup-status endpoint** — we don't currently have a public endpoint that says "is signup enabled?". Two options:
1. Use `GET /auth/oidc-status` pattern and extend it — too coupled
2. Add a new `GET /auth/config` returning `{signup_enabled: bool, password_reset_enabled: bool, oidc_enabled: bool}` — cleaner

Do option 2. Small backend addition in Phase 2.5-api.

**Tests:**
- Mantine forms validate email + password strength (≥8 chars per Phase 2 policy)
- Register page shows disabled message when config endpoint reports `signup_enabled: false`
- Reset page handles missing/expired token gracefully
- Navigation links on login page only render when feature enabled

Target: ~8 new frontend tests.

---

## Commits (~8 total across both repos)

Backend:
1. `feat(auth): add /auth/config endpoint for frontend feature detection`
2. `feat(auth): add EmailSender protocol + ConsoleEmailSender default`
3. `feat(auth): mount reset-password + verify routers (gated by env)`
4. `test(auth): reset + verify flow coverage`

Frontend:
5. `feat(api): register + forgot/reset password client helpers + config fetch`
6. `feat(ui): /register page with signup-disabled fallback`
7. `feat(ui): /forgot-password + /reset-password pages`
8. `feat(ui): add navigation links on login page`

---

## Out of scope / follow-ups

- OIDC full login/callback flow → Phase 2.6 (separate plan — PKCE state, discovery doc cache, token exchange)
- SMTP email delivery (replace ConsoleEmailSender) → Phase 7 or when a user asks
- Password strength meter UI → nice-to-have
- Rate limiting on forgot-password to prevent enumeration/spam → already filed as follow-up #14 (rate-limit login); extend scope
- Email verification enforcement on login → `is_verified` flag exists; wire into login guard later

## Test plan

- [ ] Backend: `POST /auth/forgot-password {email: "admin@local.dev"}` → 202 + console log prints reset link
- [ ] Paste link into browser → `/reset-password?token=...` → submit new password → redirect to /login
- [ ] Log in with new password → works
- [ ] Enable `AUTH_ALLOW_SIGNUP=true`, restart → visit `/register` → submit form → auto-login or redirect to /login
- [ ] Disable `AUTH_ALLOW_SIGNUP`, restart → visit `/register` → see "disabled" message
- [ ] Click "Forgot password?" from login page → works
- [ ] Register + Forgot links hidden appropriately per config
