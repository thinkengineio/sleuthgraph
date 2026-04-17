# Sleuthgraph

Open-source OSINT investigation workbench. Self-hostable. Apache 2.0.

> **Status:** Pre-alpha. Not yet usable. See [spec](docs/specs/2026-04-17-sleuthgraph-mvp-design.md).

## Repos

| Repo | Purpose |
|---|---|
| [`sleuthgraph`](https://github.com/sleuthgraph/sleuthgraph) | This meta repo — docs, specs, plans, docker-compose |
| [`sleuthgraph-api`](https://github.com/sleuthgraph/sleuthgraph-api) | Backend: FastAPI + Postgres+AGE + plugin SDK |
| [`sleuthgraph-web`](https://github.com/sleuthgraph/sleuthgraph-web) | Frontend: Next.js + Cytoscape.js |

## Quickstart (local dev)

Requires: Docker 24+, Docker Compose v2, git.

```bash
# Clone all three repos as siblings
git clone https://github.com/sleuthgraph/sleuthgraph.git
git clone https://github.com/sleuthgraph/sleuthgraph-api.git
git clone https://github.com/sleuthgraph/sleuthgraph-web.git

cd sleuthgraph/deploy
cp .env.example .env
make up
```

Open http://localhost:3000 (web) and http://localhost:8000/docs (api).

## Docs

- [MVP design spec](docs/specs/2026-04-17-sleuthgraph-mvp-design.md)
- [Implementation plans](docs/plans/README.md)

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Status

| Phase | Status | Notes |
|---|---|---|
| 1. Foundation | ✅ Complete (2026-04-17) | `make up` brings full stack healthy; 12 tests passing; all 3 repos live |
| 2. Auth (Grafana-style) | ⏳ Pending | |
| 3. Cases + Entities API | ⏳ Pending | |
| 4. Evidence chain of custody | ⏳ Pending | |
| 5. Plugin SDK | ⏳ Pending | |
| 6. Free-tier plugins (7) | ⏳ Pending | |
| 7. BYOK plugins | ⏳ Pending | |
| 8. Frontend shell | ⏳ Pending | |
| 9. Graph visualization | ⏳ Pending | |
| 10. AI + Reports + polish | ⏳ Pending | |

### Phase 1 exit state (as of 0.1.0-alpha)

- Meta, API, and Web repos public on GitHub (currently private under `francose/`)
- `docker compose up` brings up 5 healthy services: db (Postgres+AGE), redis, minio, api, web
- API: `/health`, `/readiness`, `/docs` endpoints live on :8000
- Web: landing page with live API health indicator on :3000
- MinIO console on :9001 with `evidence` bucket pre-created
- AGE extension installed with `sleuthgraph` graph
- 12 unit tests passing (7 API + 5 Web)
- CI pipelines configured on all three repos
