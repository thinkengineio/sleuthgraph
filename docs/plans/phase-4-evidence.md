# Phase 4 — Evidence Chain of Custody Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Immutable, hash-verifiable evidence ledger per case. Every piece of evidence (plugin response now + manual capture for MVP) stores the raw payload in MinIO, SHA-256 hash of the canonical payload, reproducibility spec (how to re-fetch it), timestamp, source plugin name+version, and FK to case + entity. No update, no delete — only create + list + fetch.

**Architecture:**
- Evidence row is the audit trail; payload blob lives in MinIO (S3-compatible).
- Blob key is derived from the hash: `case/{case_id}/ev/{sha256}` — same payload never uploaded twice.
- `response_uri` field stores the object key (not a signed URL — URLs get generated on-demand per request).
- `reproducibility_spec` is a JSONB blob with whatever context lets a future auditor reproduce: HTTP method, URL, request headers (sanitized of credentials), request body, response headers.
- Manual evidence (Phase 4) = user uploads a file + describes where/when. Plugin evidence (Phase 5+) = plugin runtime fills reproducibility_spec programmatically.
- Append-only enforced at the repository layer + at the router (no PATCH/PUT, no DELETE).
- Deleting a case does NOT hard-delete evidence — soft-delete cascade via `case.deleted_at` is enough. Evidence outlives the case for potential legal review.

**Tech stack (new):**
- `boto3` + `aioboto3` for async S3/MinIO client (boto3 already in deps from Phase 1 — verify aioboto3 needed or sync-over-thread is fine for MVP)
- `hashlib.sha256` for payload hashing (stdlib)

**Repo scope:** `~/sleuthgraph-api/` only. Evidence UI is Phase 4.5 (separate plan).

---

## File structure

```
src/sleuthgraph/
├── evidence/
│   ├── __init__.py          # empty
│   ├── models.py            # Evidence ORM
│   ├── schemas.py           # EvidenceCreate / EvidenceRead
│   ├── hashing.py           # canonical_hash() helper
│   ├── storage.py           # MinIO client wrapper (put/get/presign)
│   ├── repository.py        # append-only, with blob upload inside transaction
│   └── router.py            # /cases/{id}/evidence endpoints
tests/test_evidence_*.py
alembic/versions/XXXX_evidence.py
```

---

## Tasks

### Task 4.1 — Evidence model + migration

**Columns:**
- `id: UUID` PK
- `case_id: UUID` FK → cases.id ON DELETE CASCADE, indexed
- `entity_id: UUID | None` FK → entities.id ON DELETE SET NULL, indexed (optional — some evidence is case-level, not entity-bound)
- `source_plugin: str(128)` — "manual" for user-uploaded, plugin name+version for Phase 5+ (e.g. "crt.sh@0.1.0")
- `query: str(1024)` — human-readable query description ("lookup example.com on crt.sh")
- `response_hash: str(64)` — SHA-256 hex digest of canonical payload
- `response_uri: str(512)` — MinIO object key
- `response_bytes: bigint` — payload size
- `response_content_type: str(128) | None`
- `timestamp: timestamptz` — server_default now()
- `reproducibility_spec: JSON` — default empty dict
- `created_by: UUID | None` FK → users.id ON DELETE SET NULL

**No `updated_at`, no `deleted_at`** — append-only by design. Deletion via CASCADE when parent case is hard-deleted; soft-delete of case keeps evidence.

Branch: `phase-4/evidence-model`. Commit: `feat(evidence): add Evidence model + migration`.

### Task 4.2 — Evidence schemas

- `EvidenceCreate` — `entity_id? source_plugin query reproducibility_spec?` (no hash/uri — those are server-computed); attrs validator for reproducibility_spec (reuse `_validate_attrs` from Phase 3's shared helpers)
- `EvidenceRead` — full row + presigned blob URL (injected at read time, not stored)
- `EvidenceList` — paginated list shape `{items: [...], total: int, limit: int, offset: int}` — total matters for "audit log is N records long"

Branch: `phase-4/evidence-schemas`. Commit: `feat(evidence): add Evidence pydantic schemas`.

### Task 4.3 — SHA-256 hashing utility

```python
# src/sleuthgraph/evidence/hashing.py
"""Canonical SHA-256 hashing for evidence payloads.

Binary payloads: raw bytes → sha256.
JSON payloads: canonical JSON (sorted keys, no whitespace, utf-8) → sha256.
The canonical form is what gets STORED, so downstream auditors can recompute
the hash from the stored blob byte-for-byte.
"""
```

Functions:
- `hash_bytes(data: bytes) -> str` → hex digest
- `canonical_json(obj) -> bytes` — `json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')`
- `hash_json(obj) -> tuple[str, bytes]` — returns (hex_hash, canonical_bytes) so caller can both store and hash

Tests: determinism across equivalent dicts, same hash for `{"a":1,"b":2}` and `{"b":2,"a":1}`, different hash for different contents, handles unicode, handles nested.

Branch: `phase-4/evidence-hashing`. Commit: `feat(evidence): add SHA-256 canonical hashing helpers`.

### Task 4.4 — MinIO storage wrapper

Wrapper around aioboto3 S3 client for the evidence bucket. Interface:

```python
# src/sleuthgraph/evidence/storage.py
class EvidenceStorage:
    async def put(self, key: str, data: bytes, content_type: str = "application/octet-stream") -> None: ...
    async def get(self, key: str) -> bytes: ...
    async def presign_get(self, key: str, expires_in: int = 300) -> str: ...
    async def exists(self, key: str) -> bool: ...
```

Key format: `case/{case_id}/ev/{sha256_hex}`.

`put` is idempotent — if the key already exists and etag matches the expected content, it's a no-op (S3 PutObject overwrites anyway, but we skip network roundtrip by doing a HEAD first for the hot path).

Config from existing Settings (`s3_endpoint`, `s3_access_key`, `s3_secret_key`, `s3_bucket`, `s3_region`).

Tests: integration test against the live MinIO container from docker compose (skip if MinIO not reachable).

Branch: `phase-4/evidence-storage`. Commit: `feat(evidence): add MinIO storage wrapper (put/get/presign)`.

### Task 4.5 — Evidence repository

```python
# src/sleuthgraph/evidence/repository.py
class EvidenceRepository:
    def __init__(self, session, storage: EvidenceStorage): ...

    async def create(
        self, case_id, created_by, data: EvidenceCreate,
        payload: bytes, content_type: str | None,
    ) -> Evidence:
        """Hash the payload, upload to MinIO, insert the ORM row.

        All three in the same DB transaction from the API perspective:
        blob upload happens BEFORE commit — if DB insert fails, rollback; the
        blob is still there (idempotent key based on hash, so orphan blob is
        cheap garbage to clean up later, not a correctness problem).
        """

    async def get(self, ev_id, case_id) -> Evidence | None: ...

    async def list_for_case(self, case_id, entity_id=None, source_plugin=None, limit=50, offset=0) -> tuple[list[Evidence], int]:
        """Returns (items, total_count) for paginated shell."""

    # NO update. NO delete. Append-only.
```

Note: `list_for_case` returns tuple because the schema expects a `total`. Use a separate COUNT query.

Tests (sqlite): create+get+list. Tests (postgres+minio): full integration with a real blob upload + retrieval.

Branch: `phase-4/evidence-repository`. Commit: `feat(evidence): add EvidenceRepository (append-only, blob+row atomic)`.

### Task 4.6 — Evidence router

**Endpoints** (all require `current_active_user` + case ownership):
- `POST /cases/{case_id}/evidence` → multipart: `file` + JSON-encoded `metadata` field → 201 EvidenceRead
- `GET /cases/{case_id}/evidence` → 200 EvidenceList (query: `entity_id? source_plugin? limit? offset?`)
- `GET /cases/{case_id}/evidence/{ev_id}` → 200 EvidenceRead
- `GET /cases/{case_id}/evidence/{ev_id}/blob` → 307 redirect to presigned MinIO URL (5-minute expiry)

**No PUT, PATCH, DELETE.** Attempted 405. Explicit test.

Branch: `phase-4/evidence-router`. Commit: `feat(evidence): add evidence CRUD router (create + list + get + blob redirect)`.

### Task 4.7 — Ledger export endpoint

`GET /cases/{case_id}/evidence/export?format=json|csv` → 200 (or 202 if we stream) with the full evidence ledger for the case. JSON dump: list of EvidenceRead objects (without presigned URLs). CSV: id, timestamp, source_plugin, query, response_hash, response_bytes, response_content_type.

For chain-of-custody handoff — investigator can attach the ledger to a legal filing.

Branch: `phase-4/evidence-export`. Commit: `feat(evidence): add ledger export endpoint (json + csv)`.

### Task 4.8 — Integration + E2E + docs

- Merge branches into `phase-4/integration`
- Full test suite passes
- E2E: login → POST case → POST evidence (upload a file) → GET list → GET presigned URL → verify hash matches → export as CSV
- Update README endpoint table
- Open PR

Branch: `phase-4/integration`. Commit: `docs(evidence): endpoint table + ledger export notes`.

---

## Deferred to later phases

- Plugin-generated evidence (Phase 5 — plugin SDK fills reproducibility_spec)
- Evidence viewer UI (Phase 4.5 — separate frontend plan)
- Evidence signing / notarization (Phase 10+ if demand)
- Automatic hash verification on retrieve (Phase 5 — cheap and defensive)
- Bulk export / archive format (Phase 10)

---

## Self-review checklist

- [x] Append-only at DB + API + HTTP levels
- [x] Hash is deterministic via canonical JSON (or raw bytes for non-JSON)
- [x] MinIO blob key = hash → dedup + collision impossible in practice
- [x] Presigned URLs expire (5 min)
- [x] reproducibility_spec uses the same validator as attrs (reuse from Phase 3)
- [x] Ownership check before evidence access (404 not 403)
- [x] Case soft-delete preserves evidence trail
- [x] Each task commits on a dedicated branch + TDD
