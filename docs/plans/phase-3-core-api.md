# Phase 3 — Cases + Entities + Relationships API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Backend-only REST API for the core investigation model: cases, entities (8 types), relationships. Source of truth in Postgres relational tables; mirrored to Apache AGE graph so Phase 9's Cytoscape view can run Cypher queries. Authed behind Phase 2's `current_active_user`.

**Architecture:**
- Relational tables are the write path and audit trail (`cases`, `entities`, `relationships`).
- AGE graph is a materialized mirror — every entity INSERT/UPDATE/DELETE writes a matching vertex; every relationship INSERT/DELETE writes a matching edge. Entity attributes get copied onto the vertex. `id` is the foreign key that ties graph vertex ↔ SQL row.
- Postgres transactions keep SQL + AGE consistent (single `BEGIN; ... COMMIT;`).
- Soft-delete with `deleted_at` for entities/relationships (needed for evidence chain-of-custody in Phase 4: deleting a case should not erase the ledger).
- Cases have an `owner_id` FK → users. All endpoints scoped to owned-by-current-user (no sharing in MVP — single-tenant still).

**Tech Stack:**
- Existing: FastAPI, SQLAlchemy 2.x async, Alembic, pytest-asyncio, Apache AGE
- No new runtime deps (AGE is accessed via raw SQL)
- `uuid.UUID` ids everywhere

**Repo scope:** `~/sleuthgraph-api/` only.

---

## Scope / data model summary

### Entities (8 types)

| Type | Example `label` | Typical `attrs` keys |
|---|---|---|
| `PERSON` | "Ali Rıza Kaya" | dob, nationality, aliases[] |
| `ORGANIZATION` | "Arkaya Inşaat Ltd." | country, registration_id, sector |
| `DOMAIN` | "example.com" | registrar, created, expires |
| `IP_ADDRESS` | "203.0.113.5" | asn, country, first_seen |
| `EMAIL` | "a@example.com" | domain, verified |
| `PHONE` | "+90 232 555 0100" | country, carrier |
| `URL` | "https://site/path" | status, archived_at |
| `CRYPTO_ADDRESS` | "bc1q..." | chain, balance |

Stored as `entities.type` (Postgres enum or string with CHECK constraint — we use string + app-layer validation for easier extension in Phase 5).

### Relationships (typed)

Initial types: `OWNS`, `EMPLOYED_BY`, `REGISTERED_BY`, `HOSTED_ON`, `RESOLVES_TO`, `ASSOCIATED_WITH`, `COMMUNICATED_WITH`, `MENTIONS`. Stored as `relationships.rel_type` string.

### AGE graph contract

- One graph per case (`case_<uuid>`) OR one shared graph with case label? → Pick **one shared graph** named `sleuthgraph` (already created in Phase 1) with `case_id` as a property on vertices. Simpler ops; the query layer filters.
- Vertex label: the entity type (`PERSON`, `DOMAIN`, etc.)
- Vertex properties: `{id, case_id, label, confidence, created_at}` + flattened `attrs` (or `attrs` as a JSON property — use JSON property for simplicity).
- Edge label: the relationship type
- Edge properties: `{id, case_id, confidence, source_plugin, created_at}`

---

## File structure

```
src/sleuthgraph/
├── cases/
│   ├── __init__.py
│   ├── models.py           # Case ORM
│   ├── schemas.py          # Pydantic: CaseCreate / CaseRead / CaseUpdate / CaseList
│   ├── repository.py       # CRUD against SQL
│   └── router.py           # /cases endpoints
├── entities/
│   ├── __init__.py
│   ├── models.py           # Entity ORM
│   ├── schemas.py
│   ├── types.py            # EntityType enum + validation
│   ├── repository.py
│   ├── age.py              # AGE vertex read/write helpers
│   └── router.py           # /cases/{cid}/entities
├── relationships/
│   ├── __init__.py
│   ├── models.py           # Relationship ORM
│   ├── schemas.py
│   ├── types.py            # RelationshipType enum
│   ├── repository.py
│   ├── age.py              # AGE edge read/write helpers
│   └── router.py           # /cases/{cid}/relationships
└── graph/
    ├── __init__.py
    ├── queries.py          # Cypher query builders (shared by entities/relationships AGE modules)
    └── router.py           # /cases/{cid}/graph — returns vertices+edges for Cytoscape
```

Tests mirror the structure under `tests/`.

---

## Conventions

- **Branches:** `phase-3/<task-slug>`. Base off `main` after Phase 2 merges; otherwise off `phase-2/auth`.
- **Commits:** one per task, Conventional Commits.
- **TDD** throughout.
- **Ownership rule:** every endpoint checks the `case_id` path param belongs to `current_active_user` (404 if not — don't leak existence).
- **AGE consistency:** entity/relationship repo methods are transactional; if AGE write fails, SQL rolls back.
- **No bulk endpoints yet** — add in Phase 5 when plugins ingest.

---

## Task 3.1 — Case model + migration

**Files:**
- Create: `src/sleuthgraph/cases/__init__.py` (empty)
- Create: `src/sleuthgraph/cases/models.py`
- Create: `alembic/versions/XXXX_cases.py`
- Create: `tests/test_cases_model.py`

**Columns:** `id: UUID`, `owner_id: UUID (FK users.id, CASCADE on delete-user is questionable → set NULL instead so evidence survives)`, `name: str(255)`, `status: str(32)` (one of `active`, `archived`), `tags: JSONB default '[]'`, `created_at: timestamptz default now()`, `updated_at: timestamptz default now() auto-update`, `deleted_at: timestamptz nullable`.

- [ ] **Step 1** — branch:
  ```bash
  cd ~/sleuthgraph-api
  git checkout main  # or phase-2/auth if not yet merged
  git checkout -b phase-3/cases-model
  ```

- [ ] **Step 2** — write failing test `tests/test_cases_model.py`:
  ```python
  from sleuthgraph.cases.models import Case


  def test_case_columns():
      cols = {c.name for c in Case.__table__.columns}
      assert {"id", "owner_id", "name", "status", "tags", "created_at", "updated_at", "deleted_at"} <= cols


  def test_case_owner_id_fk():
      owner = Case.__table__.c.owner_id
      fks = list(owner.foreign_keys)
      assert len(fks) == 1
      assert fks[0].column.table.name == "users"


  def test_case_tablename():
      assert Case.__tablename__ == "cases"
  ```

- [ ] **Step 3** — run: `pytest tests/test_cases_model.py -v`. Expect `ModuleNotFoundError`.

- [ ] **Step 4** — write `src/sleuthgraph/cases/models.py`:
  ```python
  import uuid
  from datetime import datetime

  from sqlalchemy import JSON, DateTime, ForeignKey, String, func
  from sqlalchemy.orm import Mapped, mapped_column
  from fastapi_users_db_sqlalchemy.generics import GUID

  from sleuthgraph.db import Base


  class Case(Base):
      __tablename__ = "cases"

      id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
      owner_id: Mapped[uuid.UUID | None] = mapped_column(
          GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
      )
      name: Mapped[str] = mapped_column(String(255), nullable=False)
      status: Mapped[str] = mapped_column(String(32), nullable=False, default="active")
      tags: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
      created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
      updated_at: Mapped[datetime] = mapped_column(
          DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
      )
      deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
  ```

- [ ] **Step 5** — create alembic revision:
  ```bash
  # Ensure alembic/env.py imports this model so autogen sees it
  ```
  Add to `alembic/env.py`:
  ```python
  from sleuthgraph.cases import models as _cases_models  # noqa: F401
  ```
  Then:
  ```bash
  alembic revision --autogenerate -m "phase3: cases"
  ```
  Review the file. Expect `create_table('cases', ...)` with the columns above.

- [ ] **Step 6** — run tests: `pytest tests/test_cases_model.py -v` + `pytest -q`. Expect green.

- [ ] **Step 7** — commit:
  ```bash
  git add src/sleuthgraph/cases/__init__.py src/sleuthgraph/cases/models.py alembic/env.py alembic/versions/*_cases.py tests/test_cases_model.py
  git commit -m "feat(cases): add Case model + migration"
  ```

---

## Task 3.2 — Case schemas

**Files:**
- Create: `src/sleuthgraph/cases/schemas.py`
- Create: `tests/test_cases_schemas.py`

- [ ] **Step 1** — branch from `phase-3/cases-model`:
  ```bash
  git checkout phase-3/cases-model && git checkout -b phase-3/cases-schemas
  ```

- [ ] **Step 2** — failing test:
  ```python
  import uuid
  from datetime import datetime, timezone

  import pytest
  from pydantic import ValidationError

  from sleuthgraph.cases.schemas import CaseCreate, CaseRead, CaseUpdate


  def test_case_create_requires_name():
      with pytest.raises(ValidationError):
          CaseCreate()


  def test_case_create_accepts_name_and_tags():
      c = CaseCreate(name="Target Foo", tags=["bar"])
      assert c.name == "Target Foo"
      assert c.tags == ["bar"]


  def test_case_create_defaults_tags_empty():
      c = CaseCreate(name="x")
      assert c.tags == []


  def test_case_read_shape():
      cr = CaseRead(
          id=uuid.uuid4(), owner_id=uuid.uuid4(), name="x", status="active",
          tags=[], created_at=datetime.now(timezone.utc), updated_at=datetime.now(timezone.utc),
      )
      assert cr.status == "active"


  def test_case_update_partial():
      cu = CaseUpdate(name="renamed")
      assert cu.name == "renamed"
      assert cu.status is None
  ```

- [ ] **Step 3** — run: expect `ModuleNotFoundError`.

- [ ] **Step 4** — write `src/sleuthgraph/cases/schemas.py`:
  ```python
  import uuid
  from datetime import datetime
  from typing import Literal

  from pydantic import BaseModel, Field


  CaseStatus = Literal["active", "archived"]


  class CaseCreate(BaseModel):
      name: str = Field(min_length=1, max_length=255)
      tags: list[str] = Field(default_factory=list)


  class CaseUpdate(BaseModel):
      name: str | None = Field(default=None, min_length=1, max_length=255)
      status: CaseStatus | None = None
      tags: list[str] | None = None


  class CaseRead(BaseModel):
      id: uuid.UUID
      owner_id: uuid.UUID | None
      name: str
      status: CaseStatus
      tags: list[str]
      created_at: datetime
      updated_at: datetime

      class Config:
          from_attributes = True
  ```

- [ ] **Step 5** — run tests → pass.

- [ ] **Step 6** — commit: `feat(cases): add Case pydantic schemas`.

---

## Task 3.3 — Case repository

**Files:**
- Create: `src/sleuthgraph/cases/repository.py`
- Create: `tests/test_cases_repository.py`

**Methods:**
- `async def create(session, owner_id, data: CaseCreate) -> Case`
- `async def get(session, case_id, owner_id) -> Case | None` — returns None when not owned (don't leak existence)
- `async def list_for_owner(session, owner_id, status=None, limit=50, offset=0) -> list[Case]` — excludes soft-deleted
- `async def update(session, case_id, owner_id, data: CaseUpdate) -> Case | None`
- `async def soft_delete(session, case_id, owner_id) -> bool`

- [ ] **Step 1** — branch off `phase-3/cases-schemas`.

- [ ] **Step 2** — failing tests: cover each method including 404-on-wrong-owner. Use the existing `test_engine` fixture; create a user row first (via raw SQL or fastapi-users-db helper).

  Test file skeleton (fill in full assertions):
  ```python
  import uuid
  import pytest
  from sqlalchemy.ext.asyncio import async_sessionmaker

  from sleuthgraph.auth.models import User
  from sleuthgraph.cases.repository import CaseRepository
  from sleuthgraph.cases.schemas import CaseCreate, CaseUpdate


  @pytest.fixture
  async def db(test_engine):
      TestSession = async_sessionmaker(test_engine, expire_on_commit=False)
      async with TestSession() as s:
          yield s


  @pytest.fixture
  async def owner(db):
      u = User(id=uuid.uuid4(), email="a@b.com", hashed_password="x",
               is_active=True, is_superuser=False, is_verified=False)
      db.add(u); await db.commit(); await db.refresh(u)
      return u


  @pytest.mark.asyncio
  async def test_create_case_assigns_owner(db, owner):
      repo = CaseRepository(db)
      c = await repo.create(owner.id, CaseCreate(name="Foo"))
      assert c.owner_id == owner.id
      assert c.status == "active"


  @pytest.mark.asyncio
  async def test_get_returns_none_for_wrong_owner(db, owner):
      repo = CaseRepository(db)
      c = await repo.create(owner.id, CaseCreate(name="Foo"))
      other = uuid.uuid4()
      assert await repo.get(c.id, other) is None


  @pytest.mark.asyncio
  async def test_list_excludes_soft_deleted(db, owner):
      repo = CaseRepository(db)
      c1 = await repo.create(owner.id, CaseCreate(name="Foo"))
      c2 = await repo.create(owner.id, CaseCreate(name="Bar"))
      await repo.soft_delete(c2.id, owner.id)
      items = await repo.list_for_owner(owner.id)
      assert {c.id for c in items} == {c1.id}


  @pytest.mark.asyncio
  async def test_update_renames(db, owner):
      repo = CaseRepository(db)
      c = await repo.create(owner.id, CaseCreate(name="Foo"))
      updated = await repo.update(c.id, owner.id, CaseUpdate(name="Bar"))
      assert updated.name == "Bar"


  @pytest.mark.asyncio
  async def test_update_wrong_owner_returns_none(db, owner):
      repo = CaseRepository(db)
      c = await repo.create(owner.id, CaseCreate(name="Foo"))
      other = uuid.uuid4()
      assert await repo.update(c.id, other, CaseUpdate(name="Bar")) is None
  ```

- [ ] **Step 3** — run; expect `ModuleNotFoundError`.

- [ ] **Step 4** — write `src/sleuthgraph/cases/repository.py`:
  ```python
  import uuid
  from datetime import datetime, timezone

  from sqlalchemy import select
  from sqlalchemy.ext.asyncio import AsyncSession

  from sleuthgraph.cases.models import Case
  from sleuthgraph.cases.schemas import CaseCreate, CaseUpdate


  class CaseRepository:
      def __init__(self, session: AsyncSession):
          self.session = session

      async def create(self, owner_id: uuid.UUID, data: CaseCreate) -> Case:
          case = Case(owner_id=owner_id, name=data.name, tags=data.tags)
          self.session.add(case)
          await self.session.commit()
          await self.session.refresh(case)
          return case

      async def get(self, case_id: uuid.UUID, owner_id: uuid.UUID) -> Case | None:
          q = select(Case).where(
              Case.id == case_id,
              Case.owner_id == owner_id,
              Case.deleted_at.is_(None),
          )
          return (await self.session.execute(q)).scalar_one_or_none()

      async def list_for_owner(
          self, owner_id: uuid.UUID, status: str | None = None,
          limit: int = 50, offset: int = 0,
      ) -> list[Case]:
          q = select(Case).where(
              Case.owner_id == owner_id, Case.deleted_at.is_(None),
          )
          if status:
              q = q.where(Case.status == status)
          q = q.order_by(Case.created_at.desc()).limit(limit).offset(offset)
          return list((await self.session.execute(q)).scalars())

      async def update(
          self, case_id: uuid.UUID, owner_id: uuid.UUID, data: CaseUpdate,
      ) -> Case | None:
          case = await self.get(case_id, owner_id)
          if not case:
              return None
          payload = data.model_dump(exclude_unset=True)
          for k, v in payload.items():
              setattr(case, k, v)
          await self.session.commit()
          await self.session.refresh(case)
          return case

      async def soft_delete(self, case_id: uuid.UUID, owner_id: uuid.UUID) -> bool:
          case = await self.get(case_id, owner_id)
          if not case:
              return False
          case.deleted_at = datetime.now(timezone.utc)
          await self.session.commit()
          return True
  ```

- [ ] **Step 5** — run → pass. Full suite green.

- [ ] **Step 6** — commit: `feat(cases): add CaseRepository with CRUD + soft-delete`.

---

## Task 3.4 — Case router (CRUD endpoints)

**Files:**
- Create: `src/sleuthgraph/cases/router.py`
- Modify: `src/sleuthgraph/main.py` (include router)
- Create: `tests/test_cases_router.py`

**Endpoints:**
- `POST /cases` → 201, returns CaseRead
- `GET /cases` → 200, paginated list for current user (query: `status?`, `limit?`, `offset?`)
- `GET /cases/{case_id}` → 200 or 404
- `PATCH /cases/{case_id}` → 200 or 404
- `DELETE /cases/{case_id}` → 204 (soft delete)

All require `current_active_user`.

- [ ] **Step 1** — branch from `phase-3/cases-repository`.

- [ ] **Step 2** — failing integration tests using `signup_client` fixture + registering a user. (Full test code — cover each status code and ownership isolation between two users.)

- [ ] **Step 3** — run; expect 404.

- [ ] **Step 4** — write `src/sleuthgraph/cases/router.py`:
  ```python
  import uuid
  from fastapi import APIRouter, Depends, HTTPException, Query, status
  from sqlalchemy.ext.asyncio import AsyncSession

  from sleuthgraph.auth.deps import current_active_user
  from sleuthgraph.auth.models import User
  from sleuthgraph.cases.repository import CaseRepository
  from sleuthgraph.cases.schemas import CaseCreate, CaseRead, CaseUpdate
  from sleuthgraph.db import get_session

  router = APIRouter(prefix="/cases", tags=["cases"])


  def _repo(session: AsyncSession = Depends(get_session)) -> CaseRepository:
      return CaseRepository(session)


  @router.post("", response_model=CaseRead, status_code=status.HTTP_201_CREATED)
  async def create_case(
      data: CaseCreate,
      user: User = Depends(current_active_user),
      repo: CaseRepository = Depends(_repo),
  ) -> CaseRead:
      case = await repo.create(user.id, data)
      return CaseRead.model_validate(case)


  @router.get("", response_model=list[CaseRead])
  async def list_cases(
      status_: str | None = Query(default=None, alias="status"),
      limit: int = Query(default=50, le=200),
      offset: int = Query(default=0, ge=0),
      user: User = Depends(current_active_user),
      repo: CaseRepository = Depends(_repo),
  ) -> list[CaseRead]:
      items = await repo.list_for_owner(user.id, status=status_, limit=limit, offset=offset)
      return [CaseRead.model_validate(c) for c in items]


  @router.get("/{case_id}", response_model=CaseRead)
  async def get_case(
      case_id: uuid.UUID,
      user: User = Depends(current_active_user),
      repo: CaseRepository = Depends(_repo),
  ) -> CaseRead:
      case = await repo.get(case_id, user.id)
      if not case:
          raise HTTPException(status_code=404, detail="not found")
      return CaseRead.model_validate(case)


  @router.patch("/{case_id}", response_model=CaseRead)
  async def update_case(
      case_id: uuid.UUID,
      data: CaseUpdate,
      user: User = Depends(current_active_user),
      repo: CaseRepository = Depends(_repo),
  ) -> CaseRead:
      case = await repo.update(case_id, user.id, data)
      if not case:
          raise HTTPException(status_code=404, detail="not found")
      return CaseRead.model_validate(case)


  @router.delete("/{case_id}", status_code=status.HTTP_204_NO_CONTENT)
  async def delete_case(
      case_id: uuid.UUID,
      user: User = Depends(current_active_user),
      repo: CaseRepository = Depends(_repo),
  ) -> None:
      ok = await repo.soft_delete(case_id, user.id)
      if not ok:
          raise HTTPException(status_code=404, detail="not found")
  ```

- [ ] **Step 5** — include router in `main.py`:
  ```python
  from sleuthgraph.cases.router import router as cases_router
  app.include_router(cases_router)
  ```

- [ ] **Step 6** — run; pass.

- [ ] **Step 7** — commit: `feat(cases): add cases CRUD router`.

---

## Task 3.5 — Entity types + model + migration

**Files:**
- Create: `src/sleuthgraph/entities/{__init__,types,models}.py`
- Create: `alembic/versions/XXXX_entities.py`
- Create: `tests/test_entities_model.py`

**EntityType enum** (string enum so it stores as VARCHAR):
```python
class EntityType(str, Enum):
    PERSON = "PERSON"
    ORGANIZATION = "ORGANIZATION"
    DOMAIN = "DOMAIN"
    IP_ADDRESS = "IP_ADDRESS"
    EMAIL = "EMAIL"
    PHONE = "PHONE"
    URL = "URL"
    CRYPTO_ADDRESS = "CRYPTO_ADDRESS"
```

**Entity columns:** `id UUID PK`, `case_id UUID FK→cases ON DELETE CASCADE`, `type VARCHAR(32)`, `label VARCHAR(512)`, `attrs JSONB default '{}'`, `confidence REAL default 1.0` (0.0-1.0), `created_by UUID FK→users SET NULL`, `created_at timestamptz`, `updated_at timestamptz`, `deleted_at timestamptz nullable`.

- [ ] Branch, failing test (column shape, FK to cases, FK to users), write model, migration, tests pass, commit.

Implementation code:
```python
# src/sleuthgraph/entities/types.py
from enum import Enum

class EntityType(str, Enum):
    PERSON = "PERSON"
    ORGANIZATION = "ORGANIZATION"
    DOMAIN = "DOMAIN"
    IP_ADDRESS = "IP_ADDRESS"
    EMAIL = "EMAIL"
    PHONE = "PHONE"
    URL = "URL"
    CRYPTO_ADDRESS = "CRYPTO_ADDRESS"
```

```python
# src/sleuthgraph/entities/models.py
import uuid
from datetime import datetime

from sqlalchemy import JSON, DateTime, Float, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column
from fastapi_users_db_sqlalchemy.generics import GUID

from sleuthgraph.db import Base


class Entity(Base):
    __tablename__ = "entities"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    case_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("cases.id", ondelete="CASCADE"), nullable=False, index=True
    )
    type: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    label: Mapped[str] = mapped_column(String(512), nullable=False)
    attrs: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=1.0)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

Commit: `feat(entities): add Entity model + types + migration`.

---

## Task 3.6 — Entity schemas

```python
# src/sleuthgraph/entities/schemas.py
import uuid
from datetime import datetime
from pydantic import BaseModel, Field, field_validator

from sleuthgraph.entities.types import EntityType


class EntityCreate(BaseModel):
    type: EntityType
    label: str = Field(min_length=1, max_length=512)
    attrs: dict = Field(default_factory=dict)
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)


class EntityUpdate(BaseModel):
    label: str | None = Field(default=None, min_length=1, max_length=512)
    attrs: dict | None = None
    confidence: float | None = Field(default=None, ge=0.0, le=1.0)


class EntityRead(BaseModel):
    id: uuid.UUID
    case_id: uuid.UUID
    type: EntityType
    label: str
    attrs: dict
    confidence: float
    created_by: uuid.UUID | None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
```

Tests: enum rejected bad value, confidence 0–1 bounded, label length. Commit.

---

## Task 3.7 — AGE helpers for entities

**Files:**
- Create: `src/sleuthgraph/graph/__init__.py`, `src/sleuthgraph/graph/queries.py`
- Create: `src/sleuthgraph/entities/age.py`
- Create: `tests/test_entities_age.py` (skipped under sqlite; gated with `pytest.importorskip` + env check for postgres URL)

**Design:** Every AGE call goes through a small helper that:
1. Sets `search_path` to include `ag_catalog`
2. Runs `SELECT * FROM cypher('sleuthgraph', $$ ... $$) AS (v agtype)` via raw SQL
3. Returns parsed rows

```python
# src/sleuthgraph/entities/age.py
import json
import uuid
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from sleuthgraph.entities.models import Entity

GRAPH_NAME = "sleuthgraph"


async def upsert_vertex(session: AsyncSession, entity: Entity) -> None:
    """Create/merge a vertex for this entity."""
    props = {
        "id": str(entity.id),
        "case_id": str(entity.case_id),
        "label": entity.label,
        "confidence": entity.confidence,
        "attrs": entity.attrs,
    }
    props_json = json.dumps(props)
    cypher = f"""
        MERGE (v:{entity.type} {{id: '{entity.id}'}})
        SET v = {props_json}
        RETURN v
    """
    await session.execute(text(
        f"SELECT * FROM cypher('{GRAPH_NAME}', $$ {cypher} $$) AS (v agtype)"
    ))


async def delete_vertex(session: AsyncSession, entity_id: uuid.UUID) -> None:
    cypher = f"""
        MATCH (v {{id: '{entity_id}'}})
        DETACH DELETE v
    """
    await session.execute(text(
        f"SELECT * FROM cypher('{GRAPH_NAME}', $$ {cypher} $$) AS (v agtype)"
    ))
```

**SAFETY NOTE:** Cypher literal injection via `entity.label` / `entity.attrs` is a risk. Escape via `json.dumps` (as above) — AGE parses JSON literally. DO NOT f-string user input into Cypher; always pass as a JSON property payload.

**Test gating:** these tests require AGE. In conftest, add a `postgres_age_session` fixture that skips if `DATABASE_URL` doesn't start with `postgresql+asyncpg`. The sqlite suite skips AGE tests entirely.

Commit: `feat(entities): add AGE vertex upsert/delete helpers`.

---

## Task 3.8 — Entity repository (SQL + AGE atomic)

```python
# src/sleuthgraph/entities/repository.py
# Mirror Case repo shape. Each create/update/delete calls AGE helper in the
# same transaction. On AGE failure, SQL rollback.
```

Methods:
- `create(case_id, user_id, data) -> Entity`
- `get(entity_id, case_id) -> Entity | None`
- `list_for_case(case_id, type=None, limit, offset) -> list[Entity]`
- `update(entity_id, case_id, data) -> Entity | None`
- `soft_delete(entity_id, case_id) -> bool`

Tests: CRUD round-trip + verify AGE vertex exists after create (when postgres available) + verify vertex removed on delete.

Commit: `feat(entities): add EntityRepository with AGE mirror`.

---

## Task 3.9 — Entity router

Endpoints nested under cases:
- `POST   /cases/{cid}/entities` → 201 EntityRead
- `GET    /cases/{cid}/entities` → list (filter `?type=`, `?limit=`, `?offset=`)
- `GET    /cases/{cid}/entities/{eid}` → 200 or 404
- `PATCH  /cases/{cid}/entities/{eid}` → 200 or 404
- `DELETE /cases/{cid}/entities/{eid}` → 204

All endpoints check case ownership (via `CaseRepository.get(case_id, user.id)`) BEFORE entity lookup — so a user can't enumerate entities of a case they don't own.

Tests: full CRUD + ownership isolation across two users.

Commit: `feat(entities): add entities CRUD router nested under cases`.

---

## Task 3.10 — Relationship types + model + migration

```python
# src/sleuthgraph/relationships/types.py
class RelationshipType(str, Enum):
    OWNS = "OWNS"
    EMPLOYED_BY = "EMPLOYED_BY"
    REGISTERED_BY = "REGISTERED_BY"
    HOSTED_ON = "HOSTED_ON"
    RESOLVES_TO = "RESOLVES_TO"
    ASSOCIATED_WITH = "ASSOCIATED_WITH"
    COMMUNICATED_WITH = "COMMUNICATED_WITH"
    MENTIONS = "MENTIONS"
```

**Columns:** `id UUID`, `case_id UUID FK→cases CASCADE`, `src_entity_id UUID FK→entities CASCADE`, `dst_entity_id UUID FK→entities CASCADE`, `rel_type VARCHAR(32)`, `confidence REAL default 1.0`, `source_plugin VARCHAR(128) nullable`, `attrs JSONB default '{}'`, `created_by UUID FK→users SET NULL`, `created_at timestamptz`, `deleted_at timestamptz nullable`.

Constraint: `CHECK (src_entity_id != dst_entity_id)` — no self-loops without explicit opt-in. Or: allow self-loops (for `ASSOCIATED_WITH` etc.)? → Allow them. Drop the constraint. Note in docstring.

Commit: `feat(relationships): add Relationship model + types + migration`.

---

## Task 3.11 — Relationship schemas + repository

Mirror the Entity pattern. Key difference: on create, verify BOTH `src_entity_id` and `dst_entity_id` exist and belong to the same `case_id`. Reject with 400 if not.

Methods: `create`, `get`, `list_for_case(type=, src=, dst=)`, `soft_delete`. No update — edges are immutable except for soft-delete (chain-of-custody consideration: editing a relationship in place feels wrong; delete + recreate instead).

Commit: `feat(relationships): add Relationship repository`.

---

## Task 3.12 — AGE helpers for relationships

```python
async def upsert_edge(session, rel: Relationship) -> None:
    props = {
        "id": str(rel.id),
        "case_id": str(rel.case_id),
        "confidence": rel.confidence,
        "source_plugin": rel.source_plugin,
    }
    cypher = f"""
        MATCH (s {{id: '{rel.src_entity_id}'}}), (d {{id: '{rel.dst_entity_id}'}})
        MERGE (s)-[r:{rel.rel_type} {{id: '{rel.id}'}}]->(d)
        SET r = {json.dumps(props)}
    """
    ...
```

Tests (postgres-only): create relationship, verify edge exists via `MATCH (a)-[r]->(b) WHERE a.id = 'x' AND b.id = 'y' RETURN r`.

Commit: `feat(relationships): add AGE edge upsert/delete helpers`.

---

## Task 3.13 — Relationship router

Endpoints under case:
- `POST   /cases/{cid}/relationships` → 201
- `GET    /cases/{cid}/relationships` → list
- `GET    /cases/{cid}/relationships/{rid}` → 200 or 404
- `DELETE /cases/{cid}/relationships/{rid}` → 204

Validation:
- Source + destination entity IDs must both exist in `cid`
- `rel_type` must be a valid `RelationshipType`
- No update endpoint

Commit: `feat(relationships): add relationships router`.

---

## Task 3.14 — Graph query router (read-only Cypher-friendly)

**File:** `src/sleuthgraph/graph/router.py`

Single endpoint:
- `GET /cases/{cid}/graph` → `{vertices: [...], edges: [...]}` in a Cytoscape-friendly shape

```json
{
  "vertices": [
    {"id": "uuid", "label": "EntityType", "properties": {...}}
  ],
  "edges": [
    {"id": "uuid", "source": "src_uuid", "target": "dst_uuid", "label": "REL_TYPE", "properties": {...}}
  ]
}
```

Implementation:
1. Verify case ownership
2. SELECT vertices from SQL for this case (with type, label, confidence)
3. SELECT edges from SQL for this case
4. Return as `{vertices: [...], edges: [...]}`

(Using SQL rather than AGE for this endpoint is simpler and avoids needing AGE for the read path. Phase 9 can add Cypher-powered query endpoints for graph traversals.)

Tests: populate 3 entities + 2 relationships via router calls, hit `/graph`, assert shape.

Commit: `feat(graph): add GET /cases/{id}/graph endpoint`.

---

## Task 3.15 — E2E smoke + docs

- [ ] Populate `deploy/.env`; bring stack up.
- [ ] Login as admin, POST a case, POST 3 entities, POST 2 relationships, GET /graph, DELETE the case.
- [ ] Verify graph rows removed from AGE (spot-check with `SELECT * FROM cypher(...)`).
- [ ] Update `sleuthgraph-api/README.md` with endpoint table.
- [ ] Merge each task branch, clean up.

---

## Deferred

- Search (full-text label search) — Phase 6 when we have data
- Bulk import — Phase 5 (plugin SDK ingest path)
- Entity merge/deduplication — Phase 10 polish
- Relationship update (edit in place) — intentionally NOT offered; delete + recreate
- Case sharing between users — not in MVP (single-tenant)
- Cypher passthrough query endpoint — Phase 9

---

## Self-review checklist

- [x] All 8 entity types covered
- [x] Ownership isolation on every endpoint (case-owner check)
- [x] Soft-delete preserves evidence trail (Phase 4 will reference this)
- [x] SQL + AGE stay consistent via transactional helpers
- [x] Cypher injection mitigated by JSON property payload pattern
- [x] Each task is TDD with a commit

---

## Execution

Subagent-driven-development. Each task = fresh subagent + commit. Phase 2 merges to main first (to avoid divergent migration history).
