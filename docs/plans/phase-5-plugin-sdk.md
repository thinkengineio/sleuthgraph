# Phase 5 — Plugin SDK + First Plugin (crt.sh) Implementation Plan

**Goal:** Python plugin system that turns input entities into new entities, relationships, and evidence. First plugin ships: `crt.sh` (free, public, no credentials) that takes a DOMAIN and produces discovered subdomains + a SUBDOMAIN_OF relationship per cert match + the raw crt.sh response as evidence.

**Architecture:**
- `OSINTPlugin` abstract base class with `query(input_entity, credentials, context) -> QueryResult`
- `QueryResult` = `{entities, relationships, evidence}` — plain dataclasses-style Pydantic models
- In-memory plugin registry, bootstrapped at app startup from a single `PLUGINS` list
- `PluginRunner` takes an input entity, looks up applicable plugins, awaits the plugin's `query`, writes entities/relationships/evidence with **deduplication**, records a `plugin_runs` row for audit
- **Sync in-request** for MVP. No job queue yet. crt.sh responds in 2–5s. Slower plugins in Phase 6 need async — fine to re-architect then.
- Plugin-generated evidence reuses Phase 4's append-only ledger with `source_plugin="<name>@<version>"`.
- New relationship type: `SUBDOMAIN_OF` — added to the `RelationshipType` enum (stored as VARCHAR, no migration needed).

**Tech stack (new):**
- `httpx` (already a dep) for plugin HTTP calls
- `tenacity` for retry with exponential backoff (new dep)

**Repo:** `~/sleuthgraph-api/` only. Plugin UI (run button on case detail, plugin results viewer) is Phase 5.5.

---

## Design decisions

### Deduplication strategy

- **Entity dedup:** within a case, `(type, label)` is the dedup key. Plugin asks for an entity; repository returns existing one if match found, creates if not. Confidence is **max** of existing + new.
- **Relationship dedup:** within a case, `(src_entity_id, dst_entity_id, rel_type)` is the dedup key. If exists, skip (immutable-by-design means we don't overwrite).
- **Evidence dedup:** content-addressed MinIO key already dedups identical blobs. SQL rows are always inserted (each plugin run is a fresh audit record).

Dedup happens in the repository layer (new helper methods), NOT the plugin layer — keeps plugins simple.

### Plugin registry

Single module `sleuthgraph/plugins/__init__.py` exports a `PLUGINS: list[OSINTPlugin]` list. Each plugin is a subclass. App startup builds an `{name: plugin_instance}` dict. Adding a plugin = importing + appending to the list. No DB-backed registration.

### Plugin runs audit

New `plugin_runs` table:
```
id UUID PK
case_id UUID FK→cases CASCADE
input_entity_id UUID FK→entities SET NULL
plugin_name String(128)
plugin_version String(32)
started_at timestamptz server_default now()
finished_at timestamptz nullable
status String(16) ["running","succeeded","failed"]
error_message text nullable
entities_created_count int default 0
relationships_created_count int default 0
evidence_count int default 0
created_by UUID FK→users SET NULL
```

Surfaces "which plugin ran on what, when, did it succeed" for the frontend to render a run history per case.

### SUBDOMAIN_OF relationship type

Added to `RelationshipType` enum. No DB migration (string VARCHAR). Frontend's `RelationshipType` enum in `lib/entityTypes.ts` needs the same value added — deferred to Phase 5.5 UI work.

---

## File structure

```
src/sleuthgraph/
├── plugins/
│   ├── __init__.py              # PLUGINS: list[OSINTPlugin]
│   ├── base.py                  # OSINTPlugin ABC, QueryResult, PluginContext, RateLimit
│   ├── registry.py              # PluginRegistry (in-memory dict)
│   ├── runner.py                # PluginRunner (orchestration + dedup + audit)
│   ├── models.py                # PluginRun ORM
│   ├── schemas.py               # PluginRunRead, PluginInfo
│   ├── repository.py            # PluginRunRepository
│   ├── router.py                # HTTP endpoints
│   └── builtin/
│       ├── __init__.py
│       └── crtsh.py             # CrtShPlugin — DOMAIN → subdomains
├── entities/repository.py       # ADD: get_or_create() helper
├── relationships/repository.py  # ADD: create_if_not_exists() helper
├── relationships/types.py       # ADD: SUBDOMAIN_OF enum value
alembic/versions/XXXX_plugin_runs.py
tests/test_plugins_*.py
```

---

## Tasks (11 total, parallelized in waves)

### Wave 1 — foundations (parallel)

**Task 5.1 — Plugin base class + types**
- Files: `src/sleuthgraph/plugins/__init__.py` (empty), `src/sleuthgraph/plugins/base.py`, `tests/test_plugins_base.py`
- Define `OSINTPlugin(ABC)` with class attributes `name`, `version`, `entity_types_accepted: list[EntityType]`, `entity_types_produced: list[EntityType]`, `requires_credentials: bool = False`, and abstract `async def query(input_entity: Entity, credentials: dict | None, context: PluginContext) -> QueryResult`
- Define `QueryResult(BaseModel)` = `{entities: list[EntityProposal], relationships: list[RelationshipProposal], evidence: list[EvidenceProposal]}`
- Define `EntityProposal` = `{type, label, attrs?, confidence?}` (no id — runner assigns after dedup)
- Define `RelationshipProposal` = `{src_ref, dst_ref, rel_type, confidence?, attrs?}` where `*_ref` is an in-proposal reference: either a string identifier pointing to another proposal in the same batch, or the input_entity's id if we want to link back to the input
- Define `EvidenceProposal` = `{query, payload: bytes, content_type, reproducibility_spec}` — the runner hashes and uploads
- Define `PluginContext` = `{case_id, input_entity, http_client}` — http client is an httpx.AsyncClient with reasonable timeout
- Tests: abstract class can't be instantiated, concrete subclass with minimal impl works, QueryResult model shape validates
- Branch: `phase-5/plugin-base`. Commit: `feat(plugins): add OSINTPlugin base class + proposal types`

**Task 5.2 — PluginRun model + migration**
- Files: `src/sleuthgraph/plugins/models.py`, `alembic/versions/XXXX_plugin_runs.py`, `tests/test_plugins_model.py`
- Columns as above. FK CASCADE on case; FK SET NULL on input_entity (entities can be deleted without breaking the run history).
- No `updated_at` — runs transition through status but a single audit snapshot is fine; add `finished_at` rather than tracking intermediate updates.
- Autogen migration from live postgres, verify hash is real.
- Branch: `phase-5/plugin-run-model`. Commit: `feat(plugins): add PluginRun model + migration`

### Wave 2 — helpers (parallel, depend on Phase 3 entities/relationships + Task 5.1)

**Task 5.3 — Entity dedup helper**
- Modify `src/sleuthgraph/entities/repository.py`: add `async def get_or_create(case_id, created_by, data: EntityCreate) -> tuple[Entity, bool]` returning (entity, was_created). Match on (case_id, type, label). If exists, bump `confidence` to `max(existing, new)`. Re-mirrors to AGE on update.
- Tests: creates when absent, returns existing when duplicate, confidence max semantics.
- Branch: `phase-5/entity-get-or-create`. Commit: `feat(entities): add get_or_create helper for plugin deduplication`

**Task 5.4 — Relationship dedup helper + SUBDOMAIN_OF type**
- Modify `src/sleuthgraph/relationships/types.py`: add `SUBDOMAIN_OF = "SUBDOMAIN_OF"` to the enum.
- Modify `src/sleuthgraph/relationships/repository.py`: add `async def create_if_not_exists(case_id, created_by, data: RelationshipCreate) -> tuple[Relationship, bool]`. Match on (case_id, src_entity_id, dst_entity_id, rel_type). Return (existing, False) or (new, True).
- Tests: creates when absent, returns existing when duplicate, confidence unchanged on dedup (immutability).
- Branch: `phase-5/rel-create-if-not-exists`. Commit: `feat(relationships): add create_if_not_exists helper + SUBDOMAIN_OF type`

### Wave 3 — runner + repo (depend on waves 1+2)

**Task 5.5 — PluginRegistry + PluginRunner**
- Files: `src/sleuthgraph/plugins/registry.py`, `src/sleuthgraph/plugins/runner.py`, `tests/test_plugins_runner.py`
- `PluginRegistry` — `{name: plugin_instance}` dict, loaded at startup from `PLUGINS` list
- `PluginRunner` — takes session + storage + registry. Core flow:
  1. Create PluginRun row with status="running"
  2. Load input entity from DB (validate case ownership already done at router layer)
  3. Build httpx.AsyncClient with timeout (30s default, configurable per-plugin)
  4. Call `plugin.query(input, creds, context)` — wrap in try/except; any exception → status="failed", finished_at=now, error_message=str(e); re-raise as `PluginExecutionError`
  5. On success: resolve proposal refs → concrete entity ids (using get_or_create), write relationships (using create_if_not_exists), write evidence records with source_plugin=`<name>@<version>`
  6. Update PluginRun row: status="succeeded", counts, finished_at=now
- Tests use a FakeCrtShPlugin that returns fixtures — verify entities created, rels created, evidence written, counts correct, error path sets failed status
- Branch: `phase-5/runner`. Commit: `feat(plugins): add PluginRegistry + PluginRunner with dedup + audit`

**Task 5.6 — PluginRun repository + schemas**
- Files: `src/sleuthgraph/plugins/repository.py`, `src/sleuthgraph/plugins/schemas.py`, `tests/test_plugins_repository.py`
- `PluginRunRepository`: `get(run_id, case_id)`, `list_for_case(case_id, status=None, limit=50, offset=0) -> tuple[list, int]`
- Schemas: `PluginInfo` (name/version/accepted/produced/requires_creds — for the /plugins list endpoint), `PluginRunRead` (from ORM)
- Tests standard CRUD shape
- Branch: `phase-5/plugin-repo`. Commit: `feat(plugins): add PluginRunRepository + schemas`

### Wave 4 — first plugin + router (depend on wave 3)

**Task 5.7 — crt.sh plugin**
- Files: `src/sleuthgraph/plugins/builtin/__init__.py`, `src/sleuthgraph/plugins/builtin/crtsh.py`, `tests/test_plugins_crtsh.py`
- crt.sh API: `GET https://crt.sh/?q=<domain>&output=json` returns JSON array of cert entries. Fields we care about: `name_value` (multi-line string of SAN names), `issuer_name`, `entry_timestamp`.
- Parse: flatten name_value, drop wildcards and duplicates, filter to unique subdomains OF the input domain (skip exact matches and unrelated domains).
- Produce: one DOMAIN EntityProposal per unique subdomain; one SUBDOMAIN_OF RelationshipProposal per subdomain → input domain; one EvidenceProposal with `query="crt.sh lookup for <domain>"`, payload=raw response bytes, content_type="application/json", reproducibility_spec={"url": "https://crt.sh/?q=...", "method": "GET", "queried_at": "..."}.
- Rate limit: honor crt.sh's `Retry-After` if present; otherwise 1 req/s max. Use tenacity retry for 5xx with exp backoff.
- Tests use a stubbed httpx response (golden fixture from a real crt.sh call saved to tests/fixtures/crtsh_example.json).
- Branch: `phase-5/crtsh-plugin`. Commit: `feat(plugins): add crt.sh builtin plugin`

**Task 5.8 — Plugin HTTP router**
- Files: `src/sleuthgraph/plugins/router.py`, tests
- Modify `src/sleuthgraph/main.py`: register `PLUGINS` list (including CrtShPlugin) at import; instantiate `PluginRegistry` singleton; include the router
- Endpoints:
  - `GET /plugins` → `list[PluginInfo]` (public-ish — authed but no case-scope)
  - `GET /cases/{case_id}/plugins/runs` → paginated run history
  - `GET /cases/{case_id}/plugins/runs/{run_id}` → one run
  - `POST /cases/{case_id}/plugins/{plugin_name}/run` → `{input_entity_id: UUID}` → 201 with `{run: PluginRunRead, entities: [...], relationships: [...], evidence: [...]}` (the results)
- Ownership check on every case-scoped endpoint. 404 for non-owned cases. 404 for unknown plugin names.
- 422 if input entity's type is not in plugin.entity_types_accepted.
- Tests: unauthed 401, invalid plugin name 404, wrong entity type 422, successful run happy path (mocked CrtShPlugin).
- Branch: `phase-5/plugin-router`. Commit: `feat(plugins): add plugin HTTP router`

### Wave 5 — integration

**Task 5.9 — Integration + E2E + docs**
- Consolidate onto `phase-5/integration`
- Full test suite green (expect ~280/280 after everything lands)
- E2E: login → create case → create DOMAIN entity ("example.com") → `POST /cases/{id}/plugins/crtsh/run` → response shows N subdomains + N relationships + 1 evidence record; GET case/entities shows the new rows; plugin_runs history shows one succeeded row
- README section for plugins
- Branch: `phase-5/integration`. Commit: `docs(plugins): endpoint table + plugin SDK overview`

---

## Conventions

- NO Claude attribution in commits (hard rule)
- Append-only audit: `plugin_runs` never updated except `status` + `finished_at` + counts (single transaction at end of run)
- Activate `.venv` before running tests (`source .venv/bin/activate`)
- Use isolated git worktrees for parallel subagents
- Use real alembic-generated hash (don't let agents write placeholder `1234567890ab`)

---

## Out of scope / deferred

- **Async job queue** (redis/arq) — Phase 6 when we add slower plugins
- **BYOK credentials vault** — Phase 7 separate
- **Community plugin install** (`osintkit plugin install <git-url>`) — v1.1
- **Progress streaming to frontend** — WebSocket, Phase 9+
- **Multi-step autonomous investigation** — v2
- **Plugin results UI** (run button on case detail, history viewer) — Phase 5.5

## Test plan (E2E)

- [ ] `docker compose up` healthy
- [ ] Login admin; POST case "example.com investigation"
- [ ] POST entity `{type: "DOMAIN", label: "example.com"}` → get entity_id
- [ ] `POST /cases/{id}/plugins/crtsh/run` body `{"input_entity_id": entity_id}`
- [ ] Response: 201 with ~5–20 subdomain entities, matching SUBDOMAIN_OF rels, 1 evidence row
- [ ] `GET /cases/{id}/entities?type=DOMAIN` shows example.com + all subdomains
- [ ] `GET /cases/{id}/relationships?rel_type=SUBDOMAIN_OF` shows the edges
- [ ] `GET /cases/{id}/evidence` shows the crt.sh JSON blob
- [ ] `GET /cases/{id}/plugins/runs` shows one succeeded row with correct counts
- [ ] `GET /cases/{id}/graph` renders the new vertices + edges
