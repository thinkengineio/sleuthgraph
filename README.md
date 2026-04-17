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
