# Sleuthgraph MVP — Implementation Plan Index

**Spec:** [`../specs/2026-04-17-sleuthgraph-mvp-design.md`](../specs/2026-04-17-sleuthgraph-mvp-design.md)

## Repository structure (split: backend / frontend)

We use **two separate repositories** to keep concerns, CI, tests, release cadence, and deploy isolated.

```
~/sleuthgraph/                  # this meta repo (docs, specs, plans, compose)
├── docs/specs/                 # design docs
├── docs/plans/                 # implementation plans (this directory)
├── deploy/                     # root docker-compose.yml, .env examples, Makefile
│   ├── docker-compose.yml      # wires everything together for local dev and 0.1.0 self-host
│   ├── .env.example
│   └── Makefile
└── README.md                   # top-level quickstart

~/sleuthgraph-api/              # backend repo (Python / FastAPI / Postgres+AGE)
├── src/sleuthgraph/            # Python package
├── tests/
├── plugins/                    # first-party plugin modules (still in-repo for MVP)
├── alembic/                    # DB migrations
├── Dockerfile
├── pyproject.toml
└── .github/workflows/          # CI: ruff, pytest, build image

~/sleuthgraph-web/              # frontend repo (Next.js / TypeScript)
├── app/                        # Next.js App Router
├── components/
├── lib/                        # API client, shared types
├── tests/
├── Dockerfile
├── package.json
└── .github/workflows/          # CI: eslint, vitest, build image
```

**Benefits of the split:**
- Backend can be deployed/tested without any frontend running (CLI/API users)
- Frontend can be swapped (Next.js now, alternative UI later) without touching backend
- Independent semantic versioning (`sleuthgraph-api@0.1.0`, `sleuthgraph-web@0.1.0`)
- Separate GitHub repos means easier community contribution (plugin devs don't fork frontend)
- CI is faster — each repo's pipeline only runs its own tests

**Cross-cutting:**
- Root `~/sleuthgraph/` meta-repo owns the docker-compose + deploy glue
- OpenAPI schema is backend's source of truth; frontend generates TS client from it
- Both repos published under `github.com/sleuthgraph/` org

## Plan phases

Each phase is **scoped to either backend or frontend**, with clear dependencies. This makes parallel work possible post-Phase-4 and respects the split.

| # | Phase | Repo | Plan file | Delivers |
|---|---|---|---|---|
| 1 | Foundation (repos + infra) | meta + api + web | `phase-1-foundation.md` | 3 repos scaffolded, `docker compose up` runs Postgres+AGE+Redis+MinIO+API+Web with health checks |
| 2 | Auth (Grafana-style) | api | `phase-2-auth.md` | Register, login, sessions, OIDC config |
| 3 | Cases + Entities + Relationships | api | `phase-3-core-api.md` | REST API for investigations, entities, edges (AGE-backed) |
| 4 | Evidence chain of custody | api | `phase-4-evidence.md` | Immutable hashed evidence ledger with reproducibility spec |
| 5 | Plugin SDK + first plugin | api | `phase-5-plugin-sdk.md` | Python `OSINTPlugin` base, queue orchestration, working `crt.sh` plugin |
| 6 | Free-tier plugins (7 more) | api | `phase-6-free-plugins.md` | OCCRP, OpenSanctions, OpenCorporates, Wayback, DNS/WHOIS, HIBP, GitHub |
| 7 | BYOK plugins + credentials vault | api | `phase-7-byok-plugins.md` | Encrypted credential storage, IntelX + VirusTotal |
| 8 | Frontend shell + case workspace | web | `phase-8-frontend-shell.md` | Login, case list, case detail, entity CRUD, evidence viewer |
| 9 | Graph visualization (Cytoscape) | web | `phase-9-graph-viz.md` | Interactive graph, filters, search, click-to-pivot |
| 10 | AI pivots + Reports + final polish | api + web + meta | `phase-10-ai-reports-polish.md` | Claude pivots, Markdown/PDF export, top-level README, 0.1.0 tag |

## Parallelism / dependency graph

```
Phase 1 (foundation)
    ↓
Phase 2 (auth) ───────────┐
    ↓                      │
Phase 3 (core API) ────┐   │
    ↓                  │   │
Phase 4 (evidence)     │   │
    ↓                  │   │
Phase 5 (plugin SDK) ──┤   │
    ↓                  ↓   ↓
Phase 6 (free)      Phase 8 (frontend shell) ────┐
Phase 7 (BYOK)         ↓                         │
    ↓              Phase 9 (graph viz)           │
    └──────────────────┴─────────────────────────┘
                         ↓
              Phase 10 (AI + reports + polish → 0.1.0)
```

**Parallel windows** (if bandwidth allows, though founder is solo):
- Phase 6 and Phase 7 can be interleaved (both are plugin work)
- Phase 8 and 9 are frontend; can begin after Phase 3 ships the API surface

**Strict dependencies:**
- Phase 2 needs Phase 1 (need a DB + Alembic to create user tables)
- Phase 3 needs Phase 2 (need user context for `created_by`)
- Phase 4 needs Phase 3 (evidence belongs to entities/cases)
- Phase 5 needs Phase 4 (plugins write evidence)
- Phases 6-7 need Phase 5 (SDK + orchestrator)
- Phase 8 needs Phase 3 (API to call)
- Phase 9 needs Phase 8 + Phase 3 (AGE graph queries)
- Phase 10 needs all of the above

## Checkpoint boundaries (what's demo-able when)

- **After Phase 1**: "Hello world" deploy. Infrastructure up, health checks green.
- **After Phase 2**: Register and log in via curl or a minimal HTML form.
- **After Phase 3**: Create cases and entities via API (Postman / curl demo).
- **After Phase 4**: Manual evidence records work (precursor to plugins).
- **After Phase 5**: First automated plugin query (crt.sh) writes real evidence.
- **After Phase 7**: Full backend feature-complete. Investigators could drive via API only.
- **After Phase 8**: First UI demo. Case list + evidence viewer visible.
- **After Phase 9**: Graph-based investigation workflow demo. Resembles Maltego-lite.
- **After Phase 10**: **0.1.0 release candidate.**

## Conventions used across all plans

- **TDD** — test first, red → green → refactor → commit.
- **Bite-sized steps** — 2-5 minutes per step.
- **Complete code in every step** — no "TBD", "similar to Task N", "add error handling".
- **Commit frequency** — one commit per task.
- **Branch strategy** — `main` protected, feature branches per task: `phase-N/<task-slug>`.
- **Testing stack** — `pytest` + `pytest-asyncio` (backend), `vitest` + `@testing-library/react` (frontend).
- **Lint/format** — `ruff` (Python), `eslint` + `prettier` (TypeScript). Pre-commit hooks enforce.
- **API contract** — backend publishes OpenAPI at `/openapi.json`; frontend regenerates TS client via `openapi-typescript` on each backend version bump.

## Engineer assumptions

The executor is a skilled developer new to:
- FastAPI + SQLAlchemy 2.x async
- Apache AGE (cypher over PostgreSQL)
- Cytoscape.js
- The OSINT problem domain

Every task includes context where non-obvious.

## Execution recommendation

Use `superpowers:subagent-driven-development` per phase — fresh subagent per task with two-stage review. For a solo founder this gives pair-programming rhythm without coordination.
