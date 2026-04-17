# Phase 1 — Foundation (Part 2: API repo scaffold)

> Continues from [`phase-1-foundation.md`](phase-1-foundation.md). Same goal: at end of Phase 1, `make up` produces a healthy stack.

This part creates the `sleuthgraph-api` repo from scratch with minimal FastAPI app, async SQLAlchemy connection, Alembic for migrations, `/health` endpoint, Dockerfile, CI, and unit tests.

---

## 2. API repo — `~/sleuthgraph-api/`

### Task 2.1: Initialize API repo

**Files:**
- Create: `~/sleuthgraph-api/` directory structure

- [ ] **Step 1: Create and initialize the repo**

```bash
mkdir -p ~/sleuthgraph-api/src/sleuthgraph/routers
mkdir -p ~/sleuthgraph-api/tests
mkdir -p ~/sleuthgraph-api/.github/workflows
cd ~/sleuthgraph-api
git init -q
```

- [ ] **Step 2: Write `.python-version`**

Path: `~/sleuthgraph-api/.python-version`
```
3.12
```

- [ ] **Step 3: Write `.gitignore`**

Path: `~/sleuthgraph-api/.gitignore`
```gitignore
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
*.egg-info/
.eggs/
dist/
build/

# Virtualenv
.venv/
venv/
env/

# Tooling caches
.pytest_cache/
.ruff_cache/
.mypy_cache/
.coverage
htmlcov/

# IDE
.vscode/
.idea/
*.swp

# Env
.env
.env.local

# OS
.DS_Store

# Docker
.docker/
```

- [ ] **Step 4: Commit**

```bash
cd ~/sleuthgraph-api
git add -A
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "chore: initial repo structure"
```

---

### Task 2.2: pyproject.toml + install dependencies

**Files:**
- Create: `~/sleuthgraph-api/pyproject.toml`

- [ ] **Step 1: Write pyproject.toml**

Path: `~/sleuthgraph-api/pyproject.toml`
```toml
[project]
name = "sleuthgraph"
version = "0.1.0-dev"
description = "Sleuthgraph OSINT investigation backend"
authors = [{ name = "Sadik Erisen" }]
requires-python = ">=3.12"
license = { text = "Apache-2.0" }
dependencies = [
    "fastapi[standard]>=0.115.0",
    "uvicorn[standard]>=0.32.0",
    "sqlalchemy[asyncio]>=2.0.36",
    "asyncpg>=0.30.0",
    "alembic>=1.14.0",
    "pydantic>=2.10.0",
    "pydantic-settings>=2.6.0",
    "httpx>=0.28.0",
    "redis[hiredis]>=5.2.0",
    "boto3>=1.35.0",
    "python-jose[cryptography]>=3.3.0",
    "passlib[bcrypt]>=1.7.4",
    "authlib>=1.3.2",
    "anthropic>=0.40.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.0",
    "pytest-asyncio>=0.24.0",
    "pytest-cov>=6.0.0",
    "httpx>=0.28.0",
    "ruff>=0.7.0",
    "mypy>=1.13.0",
    "aiosqlite>=0.20.0",
]

[build-system]
requires = ["setuptools>=70.0"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
pythonpath = ["src"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B", "A", "C4", "SIM", "RET"]
ignore = ["E501"]
```

- [ ] **Step 2: Create virtualenv and install**

```bash
cd ~/sleuthgraph-api
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e ".[dev]"
```

Expected: all deps install without errors.

- [ ] **Step 3: Commit**

```bash
cd ~/sleuthgraph-api
git add pyproject.toml
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "chore: pyproject.toml with runtime and dev deps"
```

---

### Task 2.3: ruff.toml and pytest.ini

**Files:**
- Create: `~/sleuthgraph-api/ruff.toml`
- Create: `~/sleuthgraph-api/pytest.ini`

- [ ] **Step 1: Skip — already in pyproject.toml**

Ruff and pytest config are embedded in pyproject.toml (see Task 2.2). No separate files needed.

---

### Task 2.4: Write config.py with pydantic-settings

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/__init__.py`
- Create: `~/sleuthgraph-api/src/sleuthgraph/config.py`
- Create: `~/sleuthgraph-api/tests/test_config.py`

- [ ] **Step 1: Write the failing test**

Path: `~/sleuthgraph-api/tests/test_config.py`
```python
"""Tests for src/sleuthgraph/config.py."""

import os

from sleuthgraph.config import Settings


def test_settings_loads_defaults(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://test/test")
    monkeypatch.setenv("REDIS_URL", "redis://localhost:6379/0")
    monkeypatch.setenv("S3_ENDPOINT", "http://minio:9000")
    monkeypatch.setenv("S3_ACCESS_KEY", "test")
    monkeypatch.setenv("S3_SECRET_KEY", "test")
    monkeypatch.setenv("SECRET_KEY", "a" * 32)

    s = Settings()
    assert s.database_url.startswith("postgresql+asyncpg://")
    assert s.s3_bucket == "evidence"  # default
    assert s.cors_origins == ["http://localhost:3000"]  # default list


def test_settings_parses_cors_csv(monkeypatch):
    for k, v in [
        ("DATABASE_URL", "postgresql+asyncpg://test/test"),
        ("REDIS_URL", "redis://localhost:6379/0"),
        ("S3_ENDPOINT", "http://minio:9000"),
        ("S3_ACCESS_KEY", "x"),
        ("S3_SECRET_KEY", "x"),
        ("SECRET_KEY", "a" * 32),
        ("CORS_ORIGINS", "http://localhost:3000,http://localhost:3001"),
    ]:
        monkeypatch.setenv(k, v)

    s = Settings()
    assert s.cors_origins == ["http://localhost:3000", "http://localhost:3001"]
```

- [ ] **Step 2: Write `__init__.py`**

Path: `~/sleuthgraph-api/src/sleuthgraph/__init__.py`
```python
"""Sleuthgraph backend package."""

__version__ = "0.1.0-dev"
```

- [ ] **Step 3: Write config.py**

Path: `~/sleuthgraph-api/src/sleuthgraph/config.py`
```python
"""Runtime settings loaded from environment variables.

All settings REQUIRED in production (no defaults for secrets) surface
as validation errors at startup, not as surprise failures later.
"""

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", case_sensitive=False)

    # Database
    database_url: str = Field(..., description="asyncpg URL")

    # Redis
    redis_url: str = Field(...)

    # Object storage (S3-compatible; MinIO in dev)
    s3_endpoint: str = Field(...)
    s3_access_key: str = Field(...)
    s3_secret_key: str = Field(...)
    s3_bucket: str = Field("evidence")
    s3_region: str = Field("us-east-1")

    # Crypto
    secret_key: str = Field(..., min_length=32, description="Used for JWT signing + credential encryption")

    # CORS
    cors_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])

    # AI (optional — only required for Phase 10 features)
    anthropic_api_key: str | None = None

    # App
    app_name: str = "Sleuthgraph API"
    debug: bool = False

    @field_validator("cors_origins", mode="before")
    @classmethod
    def split_cors(cls, v):
        if isinstance(v, str):
            return [o.strip() for o in v.split(",") if o.strip()]
        return v


def get_settings() -> Settings:
    """Cached accessor. Overridden in tests via FastAPI dependency overrides."""
    return Settings()
```

- [ ] **Step 4: Run tests**

```bash
cd ~/sleuthgraph-api
source .venv/bin/activate
pytest tests/test_config.py -v
```

Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
cd ~/sleuthgraph-api
git add src/sleuthgraph/__init__.py src/sleuthgraph/config.py tests/test_config.py
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "feat: Settings class with env-loaded config + tests"
```

---

### Task 2.5: db.py — async SQLAlchemy engine and session

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/db.py`
- Create: `~/sleuthgraph-api/tests/test_db.py`

- [ ] **Step 1: Write the failing test**

Path: `~/sleuthgraph-api/tests/test_db.py`
```python
"""Tests for async database engine wiring."""

import pytest
from sqlalchemy import text

from sleuthgraph.db import Base, get_engine, get_session_factory


@pytest.fixture
def sqlite_env(monkeypatch):
    """Force sqlite for this unit-level test — full postgres lives in integration tests."""
    monkeypatch.setenv("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
    monkeypatch.setenv("REDIS_URL", "redis://localhost:6379/0")
    monkeypatch.setenv("S3_ENDPOINT", "http://minio:9000")
    monkeypatch.setenv("S3_ACCESS_KEY", "x")
    monkeypatch.setenv("S3_SECRET_KEY", "x")
    monkeypatch.setenv("SECRET_KEY", "a" * 32)


@pytest.mark.asyncio
async def test_engine_connects(sqlite_env):
    engine = get_engine()
    async with engine.connect() as conn:
        result = await conn.execute(text("SELECT 1"))
        assert result.scalar() == 1
    await engine.dispose()


@pytest.mark.asyncio
async def test_session_roundtrip(sqlite_env):
    SessionLocal = get_session_factory()
    async with SessionLocal() as session:
        result = await session.execute(text("SELECT 1"))
        assert result.scalar() == 1


def test_base_is_declarative():
    # Base must exist so models can inherit it.
    assert hasattr(Base, "metadata")
```

- [ ] **Step 2: Write db.py**

Path: `~/sleuthgraph-api/src/sleuthgraph/db.py`
```python
"""Async SQLAlchemy engine + session factory.

Usage in endpoints:

    from fastapi import Depends
    from sleuthgraph.db import get_session

    @app.get("/things")
    async def list_things(session=Depends(get_session)):
        ...
"""

from collections.abc import AsyncIterator
from functools import cache

from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from sleuthgraph.config import get_settings


class Base(DeclarativeBase):
    """Declarative base for all ORM models."""


@cache
def get_engine() -> AsyncEngine:
    """One engine per process. `cache` makes this a singleton for the lifetime of the app."""
    settings = get_settings()
    return create_async_engine(
        settings.database_url,
        echo=settings.debug,
        pool_pre_ping=True,
        future=True,
    )


@cache
def get_session_factory() -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(
        bind=get_engine(),
        class_=AsyncSession,
        expire_on_commit=False,
        autoflush=False,
    )


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency: yields a session, rolls back on exception, always closes."""
    SessionLocal = get_session_factory()
    async with SessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        else:
            await session.commit()
```

- [ ] **Step 3: Run tests**

```bash
cd ~/sleuthgraph-api
source .venv/bin/activate
pytest tests/test_db.py -v
```

Expected: 3 passed.

- [ ] **Step 4: Commit**

```bash
cd ~/sleuthgraph-api
git add src/sleuthgraph/db.py tests/test_db.py
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "feat: async SQLAlchemy engine, session factory, declarative Base"
```

---

### Task 2.6: /health router

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/routers/__init__.py`
- Create: `~/sleuthgraph-api/src/sleuthgraph/routers/health.py`
- Create: `~/sleuthgraph-api/tests/conftest.py`
- Create: `~/sleuthgraph-api/tests/test_health.py`

- [ ] **Step 1: Write conftest.py**

Path: `~/sleuthgraph-api/tests/conftest.py`
```python
"""Shared pytest fixtures."""

import pytest
from httpx import ASGITransport, AsyncClient


@pytest.fixture(autouse=True)
def _set_env(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
    monkeypatch.setenv("REDIS_URL", "redis://localhost:6379/0")
    monkeypatch.setenv("S3_ENDPOINT", "http://minio:9000")
    monkeypatch.setenv("S3_ACCESS_KEY", "x")
    monkeypatch.setenv("S3_SECRET_KEY", "x")
    monkeypatch.setenv("SECRET_KEY", "a" * 32)


@pytest.fixture
async def client():
    # Import here so env fixtures apply first.
    from sleuthgraph.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
```

- [ ] **Step 2: Write failing health tests**

Path: `~/sleuthgraph-api/tests/test_health.py`
```python
"""Health and readiness endpoints."""

import pytest


@pytest.mark.asyncio
async def test_health_returns_ok(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "sleuthgraph-api"}


@pytest.mark.asyncio
async def test_readiness_checks_db(client):
    resp = await client.get("/readiness")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ready"
    assert body["checks"]["db"] == "ok"
```

- [ ] **Step 3: Write router package init**

Path: `~/sleuthgraph-api/src/sleuthgraph/routers/__init__.py`
```python
"""Route modules."""
```

- [ ] **Step 4: Write health router**

Path: `~/sleuthgraph-api/src/sleuthgraph/routers/health.py`
```python
"""Liveness and readiness endpoints.

/health    — cheap liveness check (no external deps)
/readiness — confirms the API can reach its critical dependencies (db for now)
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from sleuthgraph.db import get_session

router = APIRouter(tags=["meta"])


@router.get("/health", status_code=status.HTTP_200_OK)
async def health():
    return {"status": "ok", "service": "sleuthgraph-api"}


@router.get("/readiness", status_code=status.HTTP_200_OK)
async def readiness(session: AsyncSession = Depends(get_session)):
    checks = {}
    try:
        result = await session.execute(text("SELECT 1"))
        checks["db"] = "ok" if result.scalar() == 1 else "unexpected"
    except Exception as e:
        checks["db"] = f"error: {type(e).__name__}"

    overall = "ready" if all(v == "ok" for v in checks.values()) else "degraded"
    return {"status": overall, "checks": checks}
```

---

*(Continued in [`phase-1-foundation-part-3.md`](phase-1-foundation-part-3.md) — tasks 2.7 through 2.12 finish the API repo, then Web repo, then wire-up.)*

## Status tracker (API part)

- [x] 2.1 Initialize API repo
- [x] 2.2 pyproject.toml + deps
- [x] 2.3 (merged into 2.2)
- [x] 2.4 Settings + tests
- [x] 2.5 Async engine + session + tests
- [ ] 2.6 Health router (tests written — continue in part 3)
- [ ] 2.7 main.py (app factory)
- [ ] 2.8 Alembic init
- [ ] 2.9 Dockerfile + .dockerignore
- [ ] 2.10 GitHub Actions CI
- [ ] 2.11 README for API repo
- [ ] 2.12 Push to GitHub remote
