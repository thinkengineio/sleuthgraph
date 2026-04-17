# Phase 1 — Foundation (Part 3: finish API repo)

Continues from [part 2](phase-1-foundation-part-2.md). Tasks 2.7 – 2.12 complete the API repo.

---

### Task 2.7: main.py — FastAPI app factory

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/main.py`

- [ ] **Step 1: Write main.py**

Path: `~/sleuthgraph-api/src/sleuthgraph/main.py`
```python
"""FastAPI application factory.

Starlette/uvicorn imports `sleuthgraph.main:app`. Keep it minimal; mount
routers from this single file so startup/shutdown events are centralized.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from sleuthgraph import __version__
from sleuthgraph.config import get_settings
from sleuthgraph.db import get_engine
from sleuthgraph.routers import health


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    engine = get_engine()
    yield
    # Shutdown
    await engine.dispose()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        version=__version__,
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health.router)

    return app


app = create_app()
```

- [ ] **Step 2: Run health + previous tests together**

```bash
cd ~/sleuthgraph-api
source .venv/bin/activate
pytest -v
```

Expected: All tests pass (config, db, health). If `test_readiness_checks_db` fails, it's likely due to the sqlite fixture not providing engine correctly — debug with `pytest -vv --tb=short`.

- [ ] **Step 3: Smoke-test the app manually**

```bash
cd ~/sleuthgraph-api
source .venv/bin/activate
export DATABASE_URL="sqlite+aiosqlite:///:memory:"
export REDIS_URL="redis://localhost:6379/0"
export S3_ENDPOINT="http://minio:9000"
export S3_ACCESS_KEY="x"
export S3_SECRET_KEY="x"
export SECRET_KEY="$(openssl rand -hex 32)"
uvicorn sleuthgraph.main:app --port 8000 &
PID=$!
sleep 2
curl -fsS http://localhost:8000/health | python3 -m json.tool
curl -fsS http://localhost:8000/readiness | python3 -m json.tool
kill $PID
```

Expected: Both endpoints return `200` with JSON bodies.

- [ ] **Step 4: Commit**

```bash
cd ~/sleuthgraph-api
git add src/sleuthgraph/main.py src/sleuthgraph/routers/__init__.py src/sleuthgraph/routers/health.py tests/conftest.py tests/test_health.py
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "feat: FastAPI app factory, /health and /readiness endpoints"
```

---

### Task 2.8: Alembic init

**Files:**
- Create: `~/sleuthgraph-api/alembic/` directory tree (via `alembic init`)
- Modify: `~/sleuthgraph-api/alembic.ini`
- Modify: `~/sleuthgraph-api/alembic/env.py`

- [ ] **Step 1: Run alembic init**

```bash
cd ~/sleuthgraph-api
source .venv/bin/activate
alembic init -t async alembic
```

This creates `alembic/` and `alembic.ini`.

- [ ] **Step 2: Edit alembic.ini — remove the hardcoded sqlalchemy.url**

Open `~/sleuthgraph-api/alembic.ini` and find the line:

```
sqlalchemy.url = driver://user:pass@localhost/dbname
```

Replace with:

```
# sqlalchemy.url is set programmatically from env in alembic/env.py
```

- [ ] **Step 3: Edit alembic/env.py to use Settings**

Path: `~/sleuthgraph-api/alembic/env.py`

Replace the entire file with:
```python
"""Alembic migration environment.

Pulls database URL from Sleuthgraph settings (env-driven) so CI / container
environments don't require an alembic.ini edit.
"""

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from sleuthgraph.config import get_settings
from sleuthgraph.db import Base

# Load models so their metadata is registered on Base.metadata.
# (No models yet — Phase 2 will add user, Phase 3 adds cases/entities.)
# Placeholder imports go here as models land.

config = context.config
config.set_main_option("sqlalchemy.url", get_settings().database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
```

- [ ] **Step 4: Generate an empty baseline revision**

```bash
cd ~/sleuthgraph-api
source .venv/bin/activate
export DATABASE_URL="sqlite+aiosqlite:///:memory:"
export REDIS_URL="redis://localhost:6379/0"
export S3_ENDPOINT="http://minio:9000"
export S3_ACCESS_KEY="x"
export S3_SECRET_KEY="x"
export SECRET_KEY="$(openssl rand -hex 32)"
alembic revision -m "baseline (no models yet)"
```

Expected: A new file under `alembic/versions/<hash>_baseline_no_models_yet.py` is created.

- [ ] **Step 5: Commit**

```bash
cd ~/sleuthgraph-api
git add alembic/ alembic.ini
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "feat: Alembic async env wired to settings + baseline revision"
```

---

### Task 2.9: Dockerfile + .dockerignore

**Files:**
- Create: `~/sleuthgraph-api/Dockerfile`
- Create: `~/sleuthgraph-api/.dockerignore`

- [ ] **Step 1: Write Dockerfile**

Path: `~/sleuthgraph-api/Dockerfile`
```dockerfile
# Multi-stage Dockerfile for Sleuthgraph API.

FROM python:3.12-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# --- deps layer (cached when pyproject.toml doesn't change) ---
COPY pyproject.toml ./
RUN pip install --upgrade pip \
 && pip install -e ".[dev]"

# --- app layer ---
COPY src ./src
COPY alembic ./alembic
COPY alembic.ini ./
COPY tests ./tests

# Non-root user for runtime.
RUN useradd -m -u 1000 app \
 && chown -R app:app /app
USER app

EXPOSE 8000

CMD ["uvicorn", "sleuthgraph.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 2: Write .dockerignore**

Path: `~/sleuthgraph-api/.dockerignore`
```
.git
.venv
__pycache__
*.pyc
.pytest_cache
.ruff_cache
.mypy_cache
.coverage
htmlcov
.env
.env.*
dist
build
*.egg-info
.github
.vscode
.idea
```

- [ ] **Step 3: Build and smoke-test**

```bash
cd ~/sleuthgraph-api
docker build -t sleuthgraph-api:dev .
docker run --rm -d --name sg-smoke \
  -e DATABASE_URL="sqlite+aiosqlite:///:memory:" \
  -e REDIS_URL="redis://localhost:6379/0" \
  -e S3_ENDPOINT="http://minio:9000" \
  -e S3_ACCESS_KEY=x -e S3_SECRET_KEY=x \
  -e SECRET_KEY="$(openssl rand -hex 32)" \
  -p 8001:8000 \
  sleuthgraph-api:dev
sleep 3
curl -fsS http://localhost:8001/health
docker stop sg-smoke
```

Expected: `{"status":"ok","service":"sleuthgraph-api"}`.

- [ ] **Step 4: Commit**

```bash
cd ~/sleuthgraph-api
git add Dockerfile .dockerignore
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "chore: multi-stage Dockerfile + .dockerignore"
```

---

### Task 2.10: GitHub Actions CI

**Files:**
- Create: `~/sleuthgraph-api/.github/workflows/ci.yml`

- [ ] **Step 1: Write ci.yml**

Path: `~/sleuthgraph-api/.github/workflows/ci.yml`
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint-and-test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: apache/age:PG16_latest
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"

      - name: Install deps
        run: |
          python -m pip install --upgrade pip
          pip install -e ".[dev]"

      - name: Ruff lint
        run: ruff check .

      - name: Ruff format check
        run: ruff format --check .

      - name: Pytest
        env:
          DATABASE_URL: postgresql+asyncpg://test:test@localhost:5432/test
          REDIS_URL: redis://localhost:6379/0
          S3_ENDPOINT: http://localhost:9000
          S3_ACCESS_KEY: x
          S3_SECRET_KEY: x
          SECRET_KEY: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        run: pytest --cov=src/sleuthgraph --cov-report=term-missing

  build-image:
    needs: lint-and-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - name: Build image (not pushed)
        uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          tags: sleuthgraph-api:ci
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 2: Commit**

```bash
cd ~/sleuthgraph-api
git add .github/
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "ci: ruff + pytest + docker build on push/PR"
```

---

### Task 2.11: README for API repo

**Files:**
- Create: `~/sleuthgraph-api/README.md`

- [ ] **Step 1: Write README**

Path: `~/sleuthgraph-api/README.md`
```markdown
# sleuthgraph-api

Backend for [Sleuthgraph](https://github.com/sleuthgraph/sleuthgraph) — FastAPI + Postgres+AGE + Redis + MinIO.

## Local development

Requires Python 3.12, Docker.

```bash
# 1. Python virtualenv
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"

# 2. Start infra (from the meta repo)
cd ../sleuthgraph/deploy
cp .env.example .env
docker compose --env-file .env -f docker-compose.yml up -d db redis minio minio-bootstrap

# 3. Run migrations
cd ../../sleuthgraph-api
export $(grep -v '^#' ../sleuthgraph/deploy/.env | sed 's/=db\b/=localhost/; s/=redis\b/=localhost/; s/=minio\b/=localhost/' | xargs)
alembic upgrade head

# 4. Run API
uvicorn sleuthgraph.main:app --reload
```

Docs: http://localhost:8000/docs

## Tests

```bash
pytest
```

## Lint

```bash
ruff check .
ruff format .
```

## License

Apache 2.0 — see [LICENSE](../sleuthgraph/LICENSE).
```

- [ ] **Step 2: Commit**

```bash
cd ~/sleuthgraph-api
git add README.md
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "docs: README with dev quickstart"
```

---

### Task 2.12: Push API repo to GitHub

- [ ] **Step 1: Create GitHub org + repo** (manual one-time)

You must do this via the GitHub web UI:
1. Go to https://github.com/account/organizations/new → create `sleuthgraph` org (free tier).
2. In the new org, create repo `sleuthgraph-api` (Public, Apache-2.0, no README/gitignore — we have them).

- [ ] **Step 2: Add remote and push**

```bash
cd ~/sleuthgraph-api
git remote add origin git@github.com:sleuthgraph/sleuthgraph-api.git
git branch -M main
git push -u origin main
```

- [ ] **Step 3: Verify CI runs**

Go to https://github.com/sleuthgraph/sleuthgraph-api/actions — the `CI` workflow should run and pass (both `lint-and-test` and `build-image` jobs green).

**Milestone:** API repo is public on GitHub, CI passes, Dockerfile builds cleanly, `/health` and `/readiness` endpoints work.

---

## Status tracker (API part, full)

- [x] 2.1 Init API repo
- [x] 2.2 pyproject.toml + deps
- [x] 2.3 (merged into 2.2)
- [x] 2.4 Settings + tests
- [x] 2.5 Async engine + session + tests
- [x] 2.6 /health router
- [x] 2.7 main.py app factory
- [x] 2.8 Alembic init
- [x] 2.9 Dockerfile
- [x] 2.10 GitHub Actions CI
- [x] 2.11 README
- [x] 2.12 Push to GitHub

**Next:** [`phase-1-foundation-part-4.md`](phase-1-foundation-part-4.md) — Web repo scaffold + end-to-end wire-up.
