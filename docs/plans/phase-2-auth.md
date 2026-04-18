# Phase 2 — Auth (Grafana-style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backend-only Grafana-style auth: local email/password users + OIDC config scaffold, session cookies, admin bootstrap on startup, disable-able signup. Frontend auth UI is deferred to Phase 8.

**Architecture:** Use `fastapi-users[sqlalchemy]` for the heavy lifting (user table, password hashing, register/login/me routers). Cookie transport + JWT strategy (stateless; DB-backed revocation can come post-MVP). OIDC via `httpx-oauth` (Authlib-compatible) — scaffold only in Phase 2, full OIDC flow wired in Phase 2.5 if demand exists. Admin user is bootstrapped from env on first startup so `docker compose up` yields a logged-in-able instance without manual DB seeding.

**Tech Stack:**
- `fastapi-users[sqlalchemy]>=14` (users table, password hashing, auth routers)
- `httpx-oauth>=0.16` (OIDC clients, required by fastapi-users oauth extra)
- `pyjwt[crypto]` (JWT strategy; bundled via fastapi-users)
- existing: FastAPI, SQLAlchemy 2.x async, Alembic, pytest + pytest-asyncio

**Repo scope:** `~/sleuthgraph-api/` only. Meta + web untouched except `.env.example` additions.

---

## File structure

**New files in `~/sleuthgraph-api/`:**
- `src/sleuthgraph/auth/__init__.py` — subpackage init
- `src/sleuthgraph/auth/models.py` — `User` SQLAlchemy model
- `src/sleuthgraph/auth/schemas.py` — `UserRead`, `UserCreate`, `UserUpdate` Pydantic schemas
- `src/sleuthgraph/auth/manager.py` — `UserManager` (callbacks, password policy)
- `src/sleuthgraph/auth/backend.py` — `CookieTransport` + `JWTStrategy` + `AuthenticationBackend`
- `src/sleuthgraph/auth/deps.py` — `fastapi_users` instance + `current_active_user` dependency
- `src/sleuthgraph/auth/bootstrap.py` — admin bootstrap on startup
- `src/sleuthgraph/auth/oidc.py` — OIDC config loader (stub; not wired into login flow yet)
- `alembic/versions/XXXX_auth_users.py` — users table migration
- `tests/test_auth_register_login.py` — register → login → /users/me → logout flow
- `tests/test_auth_bootstrap.py` — admin bootstrap tests
- `tests/test_auth_signup_disabled.py` — signup-disabled-by-default test

**Modified files:**
- `pyproject.toml` — add deps
- `src/sleuthgraph/config.py` — add auth settings
- `src/sleuthgraph/main.py` — include auth routers, run bootstrap on startup
- `src/sleuthgraph/db.py` — expose user-related session factory if needed
- `~/sleuthgraph/deploy/.env.example` — new auth env vars
- `~/sleuthgraph/deploy/docker-compose.yml` — pass auth env vars to api service

---

## Conventions

- **Branch strategy:** all tasks on `phase-2/<task-slug>`. Rebase onto `main` before merge.
- **Commits:** one commit per task, Conventional Commits (`feat(auth): ...`, `test(auth): ...`).
- **TDD:** red → green → refactor → commit. Every task has tests.
- **Secrets:** `SLEUTHGRAPH_AUTH_JWT_SECRET` required in prod — fail loudly at startup if unset and not in dev mode.

---

## Task 2.1 — Add auth dependencies

**Files:**
- Modify: `~/sleuthgraph-api/pyproject.toml`

**Context:** fastapi-users pulls in passlib[bcrypt], pyjwt, and the SQLAlchemy user adapter. `httpx-oauth` is needed even though we're not fully wiring OIDC yet because the router helpers import it when the oauth extra is used. We install it as a first-class dep so the OIDC scaffold in Task 2.11 doesn't require a second install pass.

- [ ] **Step 1:** Add to `[project]` dependencies in `pyproject.toml`:

```toml
  "fastapi-users[sqlalchemy]>=14,<15",
  "httpx-oauth>=0.16,<1",
```

- [ ] **Step 2:** Re-lock and install:

```bash
cd ~/sleuthgraph-api && python -m pip install -e .[dev]
```

Expected: no resolver errors.

- [ ] **Step 3:** Sanity import check:

```bash
python -c "import fastapi_users, httpx_oauth; print(fastapi_users.__version__)"
```

Expected: prints 14.x.

- [ ] **Step 4:** Commit.

```bash
git checkout -b phase-2/deps
git add pyproject.toml
git commit -m "feat(auth): add fastapi-users and httpx-oauth deps"
```

---

## Task 2.2 — Add auth settings to config

**Files:**
- Modify: `~/sleuthgraph-api/src/sleuthgraph/config.py`
- Modify: `~/sleuthgraph-api/tests/test_config.py` (create if absent)

**Context:** Settings needed:
- `AUTH_JWT_SECRET` — required, no default (prod must set)
- `AUTH_COOKIE_NAME` — default `sleuthgraph_session`
- `AUTH_COOKIE_SECURE` — default True (set False for local http)
- `AUTH_SESSION_LIFETIME_SECONDS` — default 3600*24*7 (1 week)
- `AUTH_ALLOW_SIGNUP` — default False (Grafana default: admin creates users)
- `AUTH_ADMIN_EMAIL` — optional (bootstrap)
- `AUTH_ADMIN_PASSWORD` — optional (bootstrap)
- `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` — all optional

- [ ] **Step 1:** Write failing test `tests/test_config.py::test_auth_settings_defaults`:

```python
from sleuthgraph.config import Settings


def test_auth_settings_defaults(monkeypatch):
    monkeypatch.setenv("AUTH_JWT_SECRET", "test-secret")
    s = Settings()
    assert s.auth_jwt_secret == "test-secret"
    assert s.auth_cookie_name == "sleuthgraph_session"
    assert s.auth_cookie_secure is True
    assert s.auth_session_lifetime_seconds == 60 * 60 * 24 * 7
    assert s.auth_allow_signup is False
    assert s.auth_admin_email is None


def test_auth_jwt_secret_required(monkeypatch):
    import pytest
    from pydantic import ValidationError
    monkeypatch.delenv("AUTH_JWT_SECRET", raising=False)
    with pytest.raises(ValidationError):
        Settings()
```

- [ ] **Step 2:** Run tests; confirm they fail with `AttributeError` / `ValidationError` not being raised.

```bash
pytest tests/test_config.py -v
```

- [ ] **Step 3:** Add fields to `Settings` in `src/sleuthgraph/config.py`:

```python
    auth_jwt_secret: str
    auth_cookie_name: str = "sleuthgraph_session"
    auth_cookie_secure: bool = True
    auth_session_lifetime_seconds: int = 60 * 60 * 24 * 7
    auth_allow_signup: bool = False
    auth_admin_email: str | None = None
    auth_admin_password: str | None = None
    oidc_issuer: str | None = None
    oidc_client_id: str | None = None
    oidc_client_secret: str | None = None
```

- [ ] **Step 4:** Run tests; confirm pass.

- [ ] **Step 5:** Commit.

```bash
git checkout -b phase-2/config
git add src/sleuthgraph/config.py tests/test_config.py
git commit -m "feat(auth): add auth/oidc settings with required jwt secret"
```

---

## Task 2.3 — User SQLAlchemy model

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/auth/__init__.py` (empty)
- Create: `~/sleuthgraph-api/src/sleuthgraph/auth/models.py`
- Create: `~/sleuthgraph-api/tests/test_auth_model.py`

**Context:** `fastapi-users-db-sqlalchemy` provides `SQLAlchemyBaseUserTableUUID` which gives `id: UUID`, `email`, `hashed_password`, `is_active`, `is_superuser`, `is_verified`. We add `name` (display name) and `oidc_sub` (OIDC subject, nullable for local users).

- [ ] **Step 1:** Write failing test `tests/test_auth_model.py`:

```python
from sleuthgraph.auth.models import User


def test_user_table_columns():
    cols = {c.name for c in User.__table__.columns}
    assert {"id", "email", "hashed_password", "is_active", "is_superuser", "is_verified", "name", "oidc_sub"} <= cols


def test_user_oidc_sub_nullable():
    col = User.__table__.c.oidc_sub
    assert col.nullable is True
```

- [ ] **Step 2:** Run test — expect `ModuleNotFoundError`.

```bash
pytest tests/test_auth_model.py -v
```

- [ ] **Step 3:** Write `src/sleuthgraph/auth/__init__.py` as empty file.

- [ ] **Step 4:** Write `src/sleuthgraph/auth/models.py`:

```python
from fastapi_users_db_sqlalchemy import SQLAlchemyBaseUserTableUUID
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from sleuthgraph.db import Base


class User(SQLAlchemyBaseUserTableUUID, Base):
    __tablename__ = "users"

    name: Mapped[str | None] = mapped_column(String(length=255), nullable=True)
    oidc_sub: Mapped[str | None] = mapped_column(String(length=255), nullable=True, unique=True)
```

- [ ] **Step 5:** Run tests; confirm pass.

- [ ] **Step 6:** Commit.

```bash
git checkout -b phase-2/user-model
git add src/sleuthgraph/auth/__init__.py src/sleuthgraph/auth/models.py tests/test_auth_model.py
git commit -m "feat(auth): add User SQLAlchemy model with oidc_sub"
```

---

## Task 2.4 — Alembic migration for users table

**Files:**
- Create: `~/sleuthgraph-api/alembic/versions/0002_auth_users.py` (use `alembic revision --autogenerate -m "auth: users"` to generate, then review)

**Context:** Autogeneration should pick up the new `User` model since `Base.metadata` sees it via the `sleuthgraph.auth.models` import (we'll add to `alembic/env.py` target_metadata imports). For UUID id column on Postgres we need `postgresql.UUID(as_uuid=True)`.

- [ ] **Step 1:** Ensure `alembic/env.py` imports the User model so metadata is populated. Add near the top:

```python
from sleuthgraph.auth import models as _auth_models  # noqa: F401
```

- [ ] **Step 2:** Generate migration:

```bash
cd ~/sleuthgraph-api && alembic revision --autogenerate -m "auth: users"
```

- [ ] **Step 3:** Open the generated file, verify it creates `users` with: `id` (UUID PK), `email` (unique, indexed), `hashed_password`, `is_active`, `is_superuser`, `is_verified`, `name`, `oidc_sub` (unique, nullable). If autogeneration dropped columns unrelated to this change, hand-edit to remove spurious drops.

- [ ] **Step 4:** Apply the migration in a throwaway db and roll back:

```bash
alembic upgrade head
alembic downgrade -1
alembic upgrade head
```

Expected: all three succeed.

- [ ] **Step 5:** Commit.

```bash
git checkout -b phase-2/users-migration
git add alembic/env.py alembic/versions/0002_auth_users.py
git commit -m "feat(auth): add users table migration"
```

---

## Task 2.5 — User Pydantic schemas

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/auth/schemas.py`
- Create: `~/sleuthgraph-api/tests/test_auth_schemas.py`

**Context:** fastapi-users requires `BaseUser`, `BaseUserCreate`, `BaseUserUpdate` subclasses with matching id type (UUID). We extend each to include `name` so it's exposed on `/users/me` and settable on register.

- [ ] **Step 1:** Write failing test:

```python
import uuid

from sleuthgraph.auth.schemas import UserCreate, UserRead, UserUpdate


def test_user_create_requires_email_password():
    uc = UserCreate(email="a@b.com", password="hunter222", name="Alice")
    assert uc.email == "a@b.com"
    assert uc.name == "Alice"


def test_user_read_has_id_name():
    uid = uuid.uuid4()
    ur = UserRead(
        id=uid, email="a@b.com", is_active=True, is_superuser=False, is_verified=False, name="Alice"
    )
    assert ur.id == uid
    assert ur.name == "Alice"


def test_user_update_allows_partial():
    uu = UserUpdate(name="Bob")
    assert uu.name == "Bob"
```

- [ ] **Step 2:** Run — expect `ModuleNotFoundError`.

- [ ] **Step 3:** Write `src/sleuthgraph/auth/schemas.py`:

```python
import uuid

from fastapi_users import schemas


class UserRead(schemas.BaseUser[uuid.UUID]):
    name: str | None = None


class UserCreate(schemas.BaseUserCreate):
    name: str | None = None


class UserUpdate(schemas.BaseUserUpdate):
    name: str | None = None
```

- [ ] **Step 4:** Run — pass.

- [ ] **Step 5:** Commit.

```bash
git checkout -b phase-2/user-schemas
git add src/sleuthgraph/auth/schemas.py tests/test_auth_schemas.py
git commit -m "feat(auth): add User pydantic schemas"
```

---

## Task 2.6 — UserManager

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/auth/manager.py`
- Create: `~/sleuthgraph-api/tests/test_auth_manager.py`

**Context:** `UserManager` owns password policy and callbacks (`on_after_register`, `on_after_login`). For MVP we no-op the callbacks and enforce minimum password length 8 via `validate_password`. Verification is disabled (email sends not in scope).

- [ ] **Step 1:** Write failing test:

```python
import pytest

from sleuthgraph.auth.manager import UserManager


@pytest.mark.asyncio
async def test_validate_password_rejects_short():
    mgr = UserManager(user_db=None)  # user_db unused for validation
    with pytest.raises(Exception):  # InvalidPasswordException
        await mgr.validate_password("short", user=None)


@pytest.mark.asyncio
async def test_validate_password_accepts_8_or_more():
    mgr = UserManager(user_db=None)
    # should not raise
    await mgr.validate_password("longenough", user=None)
```

- [ ] **Step 2:** Run — expect `ModuleNotFoundError`.

- [ ] **Step 3:** Write `src/sleuthgraph/auth/manager.py`:

```python
import uuid
from typing import Any

from fastapi_users import BaseUserManager, InvalidPasswordException, UUIDIDMixin

from sleuthgraph.auth.models import User
from sleuthgraph.config import get_settings


class UserManager(UUIDIDMixin, BaseUserManager[User, uuid.UUID]):
    @property
    def reset_password_token_secret(self) -> str:
        return get_settings().auth_jwt_secret

    @property
    def verification_token_secret(self) -> str:
        return get_settings().auth_jwt_secret

    async def validate_password(self, password: str, user: Any) -> None:
        if len(password) < 8:
            raise InvalidPasswordException(reason="Password must be at least 8 characters.")
```

- [ ] **Step 4:** Run — pass.

- [ ] **Step 5:** Commit.

```bash
git checkout -b phase-2/user-manager
git add src/sleuthgraph/auth/manager.py tests/test_auth_manager.py
git commit -m "feat(auth): add UserManager with 8-char min password"
```

---

## Task 2.7 — Auth backend (cookie transport + JWT strategy)

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/auth/backend.py`
- Create: `~/sleuthgraph-api/tests/test_auth_backend.py`

**Context:** Cookie transport so a browser session works out of the box. JWT strategy for stateless — revocation can be added later by switching to `DatabaseStrategy` without touching routes.

- [ ] **Step 1:** Write failing test:

```python
from sleuthgraph.auth.backend import auth_backend, cookie_transport


def test_cookie_transport_name_matches_settings(monkeypatch):
    from sleuthgraph.config import get_settings
    settings = get_settings()
    assert cookie_transport.cookie_name == settings.auth_cookie_name


def test_auth_backend_name():
    assert auth_backend.name == "cookie-jwt"
```

- [ ] **Step 2:** Run — expect `ModuleNotFoundError`.

- [ ] **Step 3:** Write `src/sleuthgraph/auth/backend.py`:

```python
from fastapi_users.authentication import (
    AuthenticationBackend,
    CookieTransport,
    JWTStrategy,
)

from sleuthgraph.config import get_settings


def _get_jwt_strategy() -> JWTStrategy:
    s = get_settings()
    return JWTStrategy(secret=s.auth_jwt_secret, lifetime_seconds=s.auth_session_lifetime_seconds)


_settings = get_settings()

cookie_transport = CookieTransport(
    cookie_name=_settings.auth_cookie_name,
    cookie_max_age=_settings.auth_session_lifetime_seconds,
    cookie_secure=_settings.auth_cookie_secure,
    cookie_httponly=True,
    cookie_samesite="lax",
)

auth_backend = AuthenticationBackend(
    name="cookie-jwt",
    transport=cookie_transport,
    get_strategy=_get_jwt_strategy,
)
```

- [ ] **Step 4:** Run — pass.

- [ ] **Step 5:** Commit.

```bash
git checkout -b phase-2/auth-backend
git add src/sleuthgraph/auth/backend.py tests/test_auth_backend.py
git commit -m "feat(auth): add cookie+JWT auth backend"
```

---

## Task 2.8 — FastAPIUsers wiring + current_user dependency

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/auth/deps.py`

**Context:** This module instantiates `FastAPIUsers`, exposes `current_active_user` and `current_superuser` dependencies, and exposes `get_user_manager` / `get_user_db` for the routers. No new tests — this is wiring covered by Task 2.10 integration tests.

- [ ] **Step 1:** Write `src/sleuthgraph/auth/deps.py`:

```python
import uuid
from collections.abc import AsyncGenerator

from fastapi import Depends
from fastapi_users import FastAPIUsers
from fastapi_users_db_sqlalchemy import SQLAlchemyUserDatabase
from sqlalchemy.ext.asyncio import AsyncSession

from sleuthgraph.auth.backend import auth_backend
from sleuthgraph.auth.manager import UserManager
from sleuthgraph.auth.models import User
from sleuthgraph.db import get_session


async def get_user_db(
    session: AsyncSession = Depends(get_session),
) -> AsyncGenerator[SQLAlchemyUserDatabase, None]:
    yield SQLAlchemyUserDatabase(session, User)


async def get_user_manager(
    user_db: SQLAlchemyUserDatabase = Depends(get_user_db),
) -> AsyncGenerator[UserManager, None]:
    yield UserManager(user_db)


fastapi_users = FastAPIUsers[User, uuid.UUID](get_user_manager, [auth_backend])

current_active_user = fastapi_users.current_user(active=True)
current_superuser = fastapi_users.current_user(active=True, superuser=True)
```

- [ ] **Step 2:** Import-sanity:

```bash
python -c "from sleuthgraph.auth.deps import fastapi_users, current_active_user; print('ok')"
```

- [ ] **Step 3:** Commit.

```bash
git checkout -b phase-2/fastapi-users-wiring
git add src/sleuthgraph/auth/deps.py
git commit -m "feat(auth): wire FastAPIUsers instance + dependencies"
```

---

## Task 2.9 — Include auth routers in main.py (signup gated)

**Files:**
- Modify: `~/sleuthgraph-api/src/sleuthgraph/main.py`
- Create: `~/sleuthgraph-api/tests/test_auth_register_login.py`

**Context:** Routers:
- `/auth/login` + `/auth/logout` — always mounted
- `/users/me` + `/users/{id}` — always mounted (authed)
- `/auth/register` — ONLY mounted if `AUTH_ALLOW_SIGNUP=true`. Otherwise admin-only creation via `/users/` (superuser endpoint).

Integration test uses httpx AsyncClient + transport=ASGITransport. Each test sets up fresh Postgres state via the existing `conftest.py` fixtures (presumed from Phase 1). If those fixtures don't exist yet, add: per-function db reset via Alembic upgrade/downgrade or truncate.

- [ ] **Step 1:** Write failing test `tests/test_auth_register_login.py`:

```python
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_register_login_me_logout(client: AsyncClient, enable_signup):
    r = await client.post(
        "/auth/register",
        json={"email": "alice@example.com", "password": "hunter222", "name": "Alice"},
    )
    assert r.status_code == 201, r.text

    r = await client.post(
        "/auth/login",
        data={"username": "alice@example.com", "password": "hunter222"},
    )
    assert r.status_code == 204, r.text
    # cookie set by transport

    r = await client.get("/users/me")
    assert r.status_code == 200
    body = r.json()
    assert body["email"] == "alice@example.com"
    assert body["name"] == "Alice"

    r = await client.post("/auth/logout")
    assert r.status_code == 204

    r = await client.get("/users/me")
    assert r.status_code == 401
```

The `enable_signup` fixture sets `AUTH_ALLOW_SIGNUP=true` for the test and reloads settings.

- [ ] **Step 2:** Run — expect 404 on `/auth/register` (not mounted yet).

- [ ] **Step 3:** Modify `src/sleuthgraph/main.py` to include routers:

```python
from sleuthgraph.auth.deps import fastapi_users
from sleuthgraph.auth.backend import auth_backend
from sleuthgraph.auth.schemas import UserCreate, UserRead, UserUpdate
from sleuthgraph.config import get_settings

# inside app factory:
app.include_router(
    fastapi_users.get_auth_router(auth_backend),
    prefix="/auth",
    tags=["auth"],
)

if get_settings().auth_allow_signup:
    app.include_router(
        fastapi_users.get_register_router(UserRead, UserCreate),
        prefix="/auth",
        tags=["auth"],
    )

app.include_router(
    fastapi_users.get_users_router(UserRead, UserUpdate),
    prefix="/users",
    tags=["users"],
)
```

- [ ] **Step 4:** Run — expect pass.

- [ ] **Step 5:** Commit.

```bash
git checkout -b phase-2/include-routers
git add src/sleuthgraph/main.py tests/test_auth_register_login.py
git commit -m "feat(auth): mount login/logout/users routers, gate register on AUTH_ALLOW_SIGNUP"
```

---

## Task 2.10 — Signup-disabled-by-default test

**Files:**
- Create: `~/sleuthgraph-api/tests/test_auth_signup_disabled.py`

**Context:** Default posture is Grafana-like: no public signup. Admin creates users. Explicit test guards the default so nobody changes it by accident.

- [ ] **Step 1:** Write:

```python
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_register_disabled_by_default(client: AsyncClient):
    r = await client.post(
        "/auth/register",
        json={"email": "bob@example.com", "password": "hunter222"},
    )
    assert r.status_code == 404
```

- [ ] **Step 2:** Run — should pass immediately because the route is not mounted when the env flag is false.

- [ ] **Step 3:** Commit.

```bash
git checkout -b phase-2/signup-disabled-test
git add tests/test_auth_signup_disabled.py
git commit -m "test(auth): guard signup-disabled default"
```

---

## Task 2.11 — Admin bootstrap on startup

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/auth/bootstrap.py`
- Modify: `~/sleuthgraph-api/src/sleuthgraph/main.py` (call on lifespan startup)
- Create: `~/sleuthgraph-api/tests/test_auth_bootstrap.py`

**Context:** On startup, if `AUTH_ADMIN_EMAIL` + `AUTH_ADMIN_PASSWORD` are set and the email doesn't already exist as a user, create a superuser with that email/password. Idempotent. If the email exists, do NOT overwrite password — log a warning and move on. This gives `docker compose up` a usable admin without manual seed scripts.

- [ ] **Step 1:** Failing test:

```python
import pytest

from sleuthgraph.auth.bootstrap import bootstrap_admin


@pytest.mark.asyncio
async def test_bootstrap_creates_admin(session, monkeypatch):
    monkeypatch.setenv("AUTH_ADMIN_EMAIL", "admin@example.com")
    monkeypatch.setenv("AUTH_ADMIN_PASSWORD", "adminpass1")
    await bootstrap_admin()

    from sqlalchemy import select
    from sleuthgraph.auth.models import User
    result = await session.execute(select(User).where(User.email == "admin@example.com"))
    user = result.scalar_one()
    assert user.is_superuser is True


@pytest.mark.asyncio
async def test_bootstrap_idempotent(session, monkeypatch):
    monkeypatch.setenv("AUTH_ADMIN_EMAIL", "admin@example.com")
    monkeypatch.setenv("AUTH_ADMIN_PASSWORD", "adminpass1")
    await bootstrap_admin()
    await bootstrap_admin()  # second call should not raise

    from sqlalchemy import select, func
    from sleuthgraph.auth.models import User
    result = await session.execute(
        select(func.count()).select_from(User).where(User.email == "admin@example.com")
    )
    assert result.scalar() == 1
```

- [ ] **Step 2:** Run — expect `ModuleNotFoundError`.

- [ ] **Step 3:** Write `src/sleuthgraph/auth/bootstrap.py`:

```python
import logging

from sqlalchemy import select

from sleuthgraph.auth.manager import UserManager
from sleuthgraph.auth.models import User
from sleuthgraph.auth.schemas import UserCreate
from sleuthgraph.config import get_settings
from sleuthgraph.db import async_session_maker
from fastapi_users_db_sqlalchemy import SQLAlchemyUserDatabase

log = logging.getLogger(__name__)


async def bootstrap_admin() -> None:
    s = get_settings()
    if not s.auth_admin_email or not s.auth_admin_password:
        log.info("Admin bootstrap skipped: AUTH_ADMIN_EMAIL / AUTH_ADMIN_PASSWORD not set")
        return

    async with async_session_maker() as session:
        result = await session.execute(select(User).where(User.email == s.auth_admin_email))
        if result.scalar_one_or_none() is not None:
            log.warning("Admin user %s already exists; not overwriting", s.auth_admin_email)
            return

        user_db = SQLAlchemyUserDatabase(session, User)
        manager = UserManager(user_db)
        await manager.create(
            UserCreate(
                email=s.auth_admin_email,
                password=s.auth_admin_password,
                is_superuser=True,
                is_active=True,
                is_verified=True,
            ),
            safe=False,
        )
        log.info("Bootstrapped admin user %s", s.auth_admin_email)
```

- [ ] **Step 4:** Wire into app lifespan in `main.py`:

```python
from contextlib import asynccontextmanager
from sleuthgraph.auth.bootstrap import bootstrap_admin


@asynccontextmanager
async def lifespan(app: FastAPI):
    await bootstrap_admin()
    yield


app = FastAPI(lifespan=lifespan, ...)
```

- [ ] **Step 5:** Run — pass.

- [ ] **Step 6:** Commit.

```bash
git checkout -b phase-2/admin-bootstrap
git add src/sleuthgraph/auth/bootstrap.py src/sleuthgraph/main.py tests/test_auth_bootstrap.py
git commit -m "feat(auth): bootstrap admin user from env on startup"
```

---

## Task 2.12 — OIDC config stub

**Files:**
- Create: `~/sleuthgraph-api/src/sleuthgraph/auth/oidc.py`
- Create: `~/sleuthgraph-api/tests/test_auth_oidc_config.py`

**Context:** We do NOT wire full OIDC login flow in Phase 2. We DO add:
- A config loader that, given env vars, exposes `get_oidc_client()` returning a configured `httpx_oauth.clients.openid.OpenID` instance OR `None` if unconfigured.
- `/auth/oidc-status` endpoint that reports whether OIDC is configured (no secrets exposed).

This lets the frontend (Phase 8) render "Sign in with SSO" conditionally, and it documents the env var contract.

- [ ] **Step 1:** Failing test:

```python
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_oidc_status_disabled(client: AsyncClient):
    r = await client.get("/auth/oidc-status")
    assert r.status_code == 200
    assert r.json() == {"enabled": False}


@pytest.mark.asyncio
async def test_oidc_status_enabled(client: AsyncClient, monkeypatch):
    monkeypatch.setenv("OIDC_ISSUER", "https://id.example.com")
    monkeypatch.setenv("OIDC_CLIENT_ID", "cid")
    monkeypatch.setenv("OIDC_CLIENT_SECRET", "csec")
    # reload settings cache
    from sleuthgraph.config import get_settings
    get_settings.cache_clear()
    r = await client.get("/auth/oidc-status")
    assert r.json() == {"enabled": True, "issuer": "https://id.example.com"}
```

- [ ] **Step 2:** Run — 404.

- [ ] **Step 3:** Write `src/sleuthgraph/auth/oidc.py`:

```python
from fastapi import APIRouter

from sleuthgraph.config import get_settings

router = APIRouter()


@router.get("/oidc-status")
async def oidc_status() -> dict:
    s = get_settings()
    enabled = bool(s.oidc_issuer and s.oidc_client_id and s.oidc_client_secret)
    if not enabled:
        return {"enabled": False}
    return {"enabled": True, "issuer": s.oidc_issuer}
```

- [ ] **Step 4:** Include router in `main.py`:

```python
from sleuthgraph.auth.oidc import router as oidc_router
app.include_router(oidc_router, prefix="/auth", tags=["auth"])
```

- [ ] **Step 5:** Run — pass.

- [ ] **Step 6:** Commit.

```bash
git checkout -b phase-2/oidc-stub
git add src/sleuthgraph/auth/oidc.py src/sleuthgraph/main.py tests/test_auth_oidc_config.py
git commit -m "feat(auth): add OIDC config stub with /auth/oidc-status"
```

---

## Task 2.13 — Protect /readiness behind public; add /auth/ping authed smoke

**Files:**
- Modify: `~/sleuthgraph-api/src/sleuthgraph/routers/health.py`
- Create: `~/sleuthgraph-api/tests/test_auth_ping.py`

**Context:** `/health` and `/readiness` must remain public (load balancers / container orchestration probe them). Add one authed smoke endpoint `/auth/ping` that returns `{"user": email}` — proof-of-life for the whole auth chain that isn't `users/me` (which already has coverage). Useful for a Phase 8 frontend smoke check too.

- [ ] **Step 1:** Failing test:

```python
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_auth_ping_unauthed_401(client: AsyncClient):
    r = await client.get("/auth/ping")
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_auth_ping_authed(logged_in_client: AsyncClient):
    r = await logged_in_client.get("/auth/ping")
    assert r.status_code == 200
    assert "user" in r.json()
```

- [ ] **Step 2:** Run — expect 404.

- [ ] **Step 3:** Add route in a new `src/sleuthgraph/auth/ping.py`:

```python
from fastapi import APIRouter, Depends

from sleuthgraph.auth.deps import current_active_user
from sleuthgraph.auth.models import User

router = APIRouter()


@router.get("/ping")
async def auth_ping(user: User = Depends(current_active_user)) -> dict:
    return {"user": user.email}
```

- [ ] **Step 4:** Include in `main.py`:

```python
from sleuthgraph.auth.ping import router as auth_ping_router
app.include_router(auth_ping_router, prefix="/auth", tags=["auth"])
```

- [ ] **Step 5:** Run — pass.

- [ ] **Step 6:** Commit.

```bash
git checkout -b phase-2/auth-ping
git add src/sleuthgraph/auth/ping.py src/sleuthgraph/main.py tests/test_auth_ping.py
git commit -m "feat(auth): add /auth/ping authed smoke endpoint"
```

---

## Task 2.14 — Docs and env wiring

**Files:**
- Modify: `~/sleuthgraph/deploy/.env.example`
- Modify: `~/sleuthgraph/deploy/docker-compose.yml` (api service env)
- Modify: `~/sleuthgraph-api/README.md` (auth section)

**Context:** Document the env contract so a self-host operator knows exactly what to set. Specifically: how to bootstrap an admin, how to enable signup, how to configure OIDC.

- [ ] **Step 1:** Add to `deploy/.env.example`:

```bash
# --- Auth ---
# JWT signing secret. REQUIRED. Generate: openssl rand -hex 32
AUTH_JWT_SECRET=

# Cookie behavior
AUTH_COOKIE_NAME=sleuthgraph_session
AUTH_COOKIE_SECURE=false        # set true behind HTTPS
AUTH_SESSION_LIFETIME_SECONDS=604800

# Public self-signup (Grafana default: false; admin creates users)
AUTH_ALLOW_SIGNUP=false

# Bootstrap admin on first startup (skipped if unset, idempotent)
AUTH_ADMIN_EMAIL=
AUTH_ADMIN_PASSWORD=

# --- OIDC (optional) ---
OIDC_ISSUER=
OIDC_CLIENT_ID=
OIDC_CLIENT_SECRET=
```

- [ ] **Step 2:** Pass all of these through in the api service block of `deploy/docker-compose.yml` (append to existing `environment:` list).

- [ ] **Step 3:** In `~/sleuthgraph-api/README.md`, add a section:

````markdown
## Auth

Sleuthgraph follows Grafana-style auth: local users + optional OIDC, single-tenant.

- `/auth/login` — form-encoded `username` + `password`, sets session cookie
- `/auth/logout` — clears cookie
- `/auth/ping` — authed smoke; returns `{user: email}`
- `/users/me` — current user profile
- `/auth/oidc-status` — reports whether OIDC is wired

**Bootstrap admin** by setting `AUTH_ADMIN_EMAIL` + `AUTH_ADMIN_PASSWORD` in `.env` before first `docker compose up`. The user is created on startup and only on startup; delete the row from `users` to re-trigger.

**Enable public registration** (Phase 2 disables by default) with `AUTH_ALLOW_SIGNUP=true`.

**OIDC** is scaffolded (config loader + status endpoint) but the login flow is Phase 2.5.
````

- [ ] **Step 4:** Commit across both repos:

```bash
# in sleuthgraph-api
git checkout -b phase-2/docs
git add README.md
git commit -m "docs(auth): document env contract + endpoints"

# in sleuthgraph (meta)
cd ~/sleuthgraph
git checkout -b phase-2/deploy-env
git add deploy/.env.example deploy/docker-compose.yml
git commit -m "chore(deploy): pass auth env vars to api service"
```

---

## Task 2.15 — E2E smoke: `docker compose up` → login works

**Files:** none new — integration check.

**Context:** Full end-to-end: bring the stack up, verify admin is bootstrapped, log in via curl, hit `/auth/ping`.

- [ ] **Step 1:** Populate `deploy/.env` with a test admin:

```bash
cd ~/sleuthgraph/deploy
cp .env.example .env
# edit: set AUTH_JWT_SECRET, AUTH_ADMIN_EMAIL=admin@local, AUTH_ADMIN_PASSWORD=adminpass1
```

- [ ] **Step 2:** Bring stack up:

```bash
make up
```

Expected: 5/5 healthy.

- [ ] **Step 3:** Verify admin bootstrap in logs:

```bash
docker compose logs api | grep "Bootstrapped admin user"
```

Expected: 1 line.

- [ ] **Step 4:** Login via curl:

```bash
curl -i -c /tmp/cookies.txt -X POST http://localhost:8000/auth/login \
    -d "username=admin@local&password=adminpass1"
```

Expected: `HTTP/1.1 204 No Content`; `set-cookie: sleuthgraph_session=...`.

- [ ] **Step 5:** Hit authed endpoint:

```bash
curl -b /tmp/cookies.txt http://localhost:8000/auth/ping
```

Expected: `{"user":"admin@local"}`.

- [ ] **Step 6:** Hit without cookie:

```bash
curl -i http://localhost:8000/auth/ping
```

Expected: `401`.

- [ ] **Step 7:** If all pass, merge each phase-2 branch to `main` with a clean PR per task (per the `gh pr merge` workflow — no auto-delete, no Claude attribution). Create the follow-up GitHub issues for what's deferred:
- "Phase 2.5: full OIDC login flow (httpx-oauth integration + callback)"
- "Phase 2.5: password reset flow"
- "Phase 2.5: admin UI for user management (when frontend shell lands in Phase 8)"

---

## Deferred (explicitly NOT in Phase 2)

- Full OIDC login/callback flow (scaffold only in Task 2.12)
- Password reset emails
- Email verification
- Per-user API tokens (needed for CLI/plugin authors — add in Phase 5 with plugin SDK)
- DB-backed session revocation (currently JWT)
- Frontend login page (Phase 8)
- Role-based access beyond `is_superuser`

## Self-review checklist

- [x] Every MVP spec auth requirement covered: local users (Task 2.3), OIDC config (2.12), session cookies (2.7), bootstrap (2.11), disable-able signup (2.9/2.10)
- [x] No placeholders — every step has the code or command it needs
- [x] Type/name consistency: `auth_backend`, `cookie_transport`, `fastapi_users`, `current_active_user`, `bootstrap_admin` all reused as defined
- [x] TDD flow preserved across every task that produces code
- [x] Every task ends in a commit

---

## Execution

**Subagent-Driven** recommended (per session convention). Fresh subagent per task, two-stage review (spec then code quality), commit on approval.
