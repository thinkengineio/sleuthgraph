# Sleuthgraph

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Open-source OSINT investigation workbench — Grafana for OSINT. Self-hostable. Apache 2.0.

> **Status:** Pre-alpha — APIs may change between releases. Core investigation workflow is end-to-end usable: log in, create a case, add entities, pivot across 8 free OSINT plugins, inspect results in an interactive Cytoscape graph with full evidence chain of custody.

## What is it?

Sleuthgraph is what you reach for when you've outgrown a spreadsheet of URLs and screenshots but don't want to pay for Maltego. It's a typed entity-and-relationship graph backed by Postgres + Apache AGE, wrapped in a case-scoped workspace with append-only evidence storage and a pluggable adapter SDK for any OSINT data source.

Think **Grafana for OSINT**: you bring the cases, plugins pivot across public APIs (Certificate Transparency, DNS, Wayback Machine, OpenCorporates, GitHub, OpenSanctions, Aleph, URLhaus — all free), every HTTP call is captured as timestamped evidence with content-addressed storage, and the resulting entity graph is rendered interactively so you can spot patterns a table view hides.

### Features (shipped)

- **Grafana-style auth** — email/password or OIDC SSO (Keycloak / Authentik / Google), bootstrapped admin, disable-able signup, password reset via email, cookie-backed sessions
- **Case workspace** — case-scoped isolation, ownership enforced at every layer, soft delete
- **Typed entity graph** — 8 core types (PERSON, ORGANIZATION, DOMAIN, IP_ADDRESS, EMAIL, PHONE, URL, CRYPTO_ADDRESS); 9 relationship types; Postgres + Apache AGE dual-write so both SQL and Cypher queries work
- **Evidence chain of custody** — every plugin HTTP call captured with SHA-256-addressed raw payload in MinIO, `reproducibility_spec` JSON, append-only ledger, CSV export with formula-injection neutralization
- **Plugin SDK** — Python `OSINTPlugin` ABC with `EntityProposal` / `RelationshipProposal` / `EvidenceProposal` types; dedup helpers; sync + async (arq worker) dispatch; per-plugin byte + proposal caps
- **8 built-in plugins** — crt.sh, DNS/WHOIS (RDAP), Wayback CDX, OpenCorporates, GitHub public, OpenSanctions, Aleph (OCCRP), URLhaus. All free, no API keys required.
- **Interactive graph viz** — Cytoscape.js canvas with 4 layouts (cose-bilkent, concentric, breadthfirst, dagre), animated transitions, hover focus lens, type-colored nodes, click-to-drawer entity/relationship detail
- **Async task queue** — arq + Redis worker for long-running plugin runs; sync plugins return inline, async ones return 202 and poll
- **Security-conscious defaults** — HKDF subkey derivation from a single `SECRET_KEY`, PKCE S256 on OIDC, id_token validation (signature + iss + aud + nonce), `email_verified` enforcement on auto-link, password rotation on account link, Redis AUTH required, SSRF hardening on plugin inputs

### Pending

- **Phase 7** — BYOK credentialed plugins (HIBP, VirusTotal, IntelX, Shodan premium) with encrypted credential vault
- **Phase 10** — AI-assisted pivot suggestions + report export (Claude API integration)

## Editions

Sleuthgraph ships in two editions — Community (open source, Apache 2.0) and
Cloud (hosted at sleuthgraph.io). **Community is free forever.** See
[TIERS.md](TIERS.md) for the full matrix of what ships in each tier.

## 2-minute quickstart

Requires Docker 24+, Docker Compose v2, and git.

```bash
git clone https://github.com/francose/sleuthgraph.git
git clone https://github.com/francose/sleuthgraph-api.git
git clone https://github.com/francose/sleuthgraph-web.git

cd sleuthgraph/deploy
cp .env.example .env   # edit SECRET_KEY, REDIS_PASSWORD, POSTGRES_PASSWORD, MINIO_ROOT_PASSWORD, AUTH_ADMIN_EMAIL, AUTH_ADMIN_PASSWORD
docker compose up
```

Open **http://localhost:3000** and log in with the admin credentials you set in `.env`.

- **API docs:** http://localhost:8000/docs
- **MinIO console:** http://localhost:9001 (evidence bucket pre-created)

Minimum required `.env` values (generate secrets with `openssl rand -hex 32`):

```bash
SECRET_KEY=...
REDIS_PASSWORD=...
POSTGRES_PASSWORD=...
MINIO_ROOT_PASSWORD=...
AUTH_ADMIN_EMAIL=you@example.com
AUTH_ADMIN_PASSWORD=your-strong-password
```

## Architecture

6-service Docker stack — all services defined in `deploy/docker-compose.yml`.

```
┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│   web        │────▶│    api      │────▶│ db           │
│ Next.js 16   │     │ FastAPI     │     │ Postgres+AGE │
│ Mantine v8   │     │ fastapi-    │     │ SQL + Cypher │
│ Cytoscape.js │     │ users       │     └──────────────┘
└──────────────┘     │             │     ┌──────────────┐
                     │ OSINTPlugin │────▶│ minio        │
                     │ SDK         │     │ evidence     │
                     └──────┬──────┘     └──────────────┘
                            │
                            ▼
                     ┌─────────────┐     ┌──────────────┐
                     │   worker    │────▶│ redis        │
                     │ arq async   │     │ queue +      │
                     │  dispatch   │     │ cache (AUTH) │
                     └─────────────┘     └──────────────┘
```

## Repos

| Repo | Visibility | Purpose |
|---|---|---|
| [`francose/sleuthgraph`](https://github.com/francose/sleuthgraph) | public | This meta repo — docs, specs, plans, docker-compose |
| [`francose/sleuthgraph-api`](https://github.com/francose/sleuthgraph-api) | public | Backend: Python 3.12 + FastAPI + Postgres + AGE + arq worker + plugin SDK |
| [`francose/sleuthgraph-web`](https://github.com/francose/sleuthgraph-web) | public | Frontend: Next.js 16 + Mantine v8 + Cytoscape.js |
| `francose/sleuthgraph-cloud` | private | Operator-only infrastructure for sleuthgraph.io — never distributed |

## Docs

- [MVP design spec](docs/specs/2026-04-17-sleuthgraph-mvp-design.md)
- [Implementation plans](docs/plans/) — phase-by-phase, TDD-style
- [OIDC setup guide](https://github.com/francose/sleuthgraph-api/blob/main/docs/auth-oidc.md) — Keycloak, Authentik, Google
- [Plugin catalog](https://github.com/francose/sleuthgraph-api/blob/main/docs/plugins.md) — all 8 built-in plugins with input/output contracts

## Phase status

| Phase | Status | Notes |
|---|---|---|
| 1. Foundation | ✅ 2026-04-17 | Docker stack, Postgres + AGE, MinIO, Redis, CI |
| 2. Auth (Grafana-style) | ✅ 2026-04-20 | fastapi-users, cookie+JWT, admin bootstrap, signup toggle |
| 2.5. Auth UI completeness | ✅ 2026-04-21 | Register / forgot-password / reset-password pages; `/auth/config` |
| 2.6. OIDC full flow | ✅ 2026-04-22 | PKCE, id_token validation, `email_verified` enforcement, account linking |
| 3. Cases + Entities + Relationships API | ✅ 2026-04-20 | SQL + AGE dual-write, ownership, typed enums |
| 3.5 / 3.6. Frontend shell + Entities UI | ✅ 2026-04-21 | Mantine dark theme, case detail page, entity / rel panels |
| 4. Evidence chain of custody | ✅ 2026-04-21 | MinIO content-addressed storage, append-only ledger, CSV export |
| 4.5. Evidence UI | ✅ 2026-04-21 | Upload modal, detail drawer, hash verification |
| 5. Plugin SDK + crt.sh | ✅ 2026-04-21 | `OSINTPlugin` ABC, runner, dedup, exception taxonomy |
| 5.5. Plugin run UI | ✅ 2026-04-21 | Run modal, runs table, status polling |
| 6. 7 more free plugins + arq queue | ✅ 2026-04-22 | dns_whois, wayback_cdx, opencorporates, github_public, opensanctions, aleph_occrp, urlhaus + async worker |
| 7. BYOK credentialed plugins | ⏳ Pending | HIBP, VirusTotal, IntelX, Shodan + encrypted credential vault |
| 8. Frontend shell | ✅ rolled into 3.5 / 3.6 / 4.5 / 5.5 | |
| 9. Graph visualization | ✅ 2026-04-22 | Cytoscape canvas, 4 layouts w/ animated transitions, hover focus lens |
| 10. AI + reports + polish | ⏳ Pending | Claude API pivot suggestions, report export, 0.1.0 release |

## License

Apache 2.0 — see [LICENSE](LICENSE).
