# OSINTkit — MVP Design Spec

**Status:** Draft v1 · **Date:** 2026-04-17 · **Author:** Sadik Erisen (product)
**Working name:** OSINTkit *(TBD — placeholder for spec)*

---

## 1. Summary

OSINTkit is a **self-hostable, open-source OSINT investigation workbench** that unifies free data sources natively and integrates commercial sources via Bring-Your-Own-Key (BYOK), with built-in forensic chain of custody and AI-assisted pivot suggestions.

The product is positioned as **"Grafana for OSINT"** — not a competitor to OCCRP Aleph, Sayari, SpiderFoot, or Maltego, but a unified interface that aggregates them.

**Strategic positioning:**

| vs. | OSINTkit differentiation |
|---|---|
| Maltego | Open source, modern UX, AI-assisted, affordable, easier extensibility |
| Sayari Graph | Individual analyst accessible (not enterprise-only), self-hostable, BYOK |
| SpiderFoot | Better UX, evidence chain of custody, structured investigation workflow |
| OCCRP Aleph | General-purpose investigation workspace vs journalism-indexed archive |
| Manual (curl + notes) | Persistent workspace, auto-capture, pivot suggestions, reproducible evidence |

---

## 2. Goals

1. **Primary**: Give individual investigators and small teams a single interface to conduct OSINT investigations across multiple data sources, with evidence standards that hold up to government / legal handoff.
2. **Secondary**: Build an open-source community around an extensible plugin architecture.
3. **Tertiary**: Establish credibility for the research LLC with the goal of attracting SBIR/DHS/NSF grants.

## 3. Non-goals

- We are **not** indexing corporate data (Sayari does).
- We are **not** crawling investigative journalism (Aleph does).
- We are **not** hosting breach data (IntelX, Dehashed, HIBP do).
- We are **not** building a multi-tenant SaaS in the open-source core.
- We are **not** replacing enterprise-grade threat intel platforms (Recorded Future, Flashpoint).

## 4. Users

| Persona | Needs | How OSINTkit serves them |
|---|---|---|
| **Independent investigator / PI** | Low cost, self-hostable, unified workflow | OSS core, BYOK, no vendor lock-in |
| **Investigative journalist** | Evidence chain of custody, open source (trust), collaboration-ready | Hashed evidence + transparent methodology |
| **Small gov/LEA team** | Self-hostable (air-gap OK), IC-tradecraft reports, no procurement hurdles | OSS deploy, IC-aligned report format |
| **Cybersecurity researcher** | Extensibility for custom pipelines | Plugin SDK, open API |
| **Corporate due-diligence analyst** | Speed, BYOK integration with commercial sources | Unified graph, BYOK for Sayari/IntelX etc. |

## 5. Architecture

### 5.1 High-level

```
┌─────────────────────────────────────────────────────────────────┐
│                      Next.js Frontend                            │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ Case UI     │  │ Graph View   │  │ Evidence Viewer      │   │
│  │             │  │ (Cytoscape)  │  │ + Report Generator   │   │
│  └──────┬──────┘  └──────┬───────┘  └──────────┬───────────┘   │
└─────────┼────────────────┼──────────────────────┼───────────────┘
          │                │                      │
┌─────────▼────────────────▼──────────────────────▼───────────────┐
│                  FastAPI Backend (Python)                        │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ Cases API   │  │ Entities API │  │ Plugin Orchestrator  │   │
│  │             │  │              │  │ (async, rate-limited)│   │
│  └─────────────┘  └──────────────┘  └──────────┬───────────┘   │
│  ┌─────────────┐  ┌──────────────┐             │               │
│  │ Evidence    │  │ AI Assistant │             │               │
│  │ (hash+log)  │  │ (Claude API) │             │               │
│  └─────────────┘  └──────────────┘             │               │
└─────────────────────────────────────────────────┼───────────────┘
                                                  │
           ┌──────────────────────────────────────┼──────────────────────────────┐
           │                                      │                              │
┌──────────▼────────┐  ┌───────────────┐  ┌──────▼─────────┐  ┌─────────────────┐
│ Free-tier plugins │  │ BYOK plugins  │  │ Custom plugins │  │ Scraper plugins │
│ (embedded API)    │  │ (user creds)  │  │ (community)    │  │ (for sites w/o  │
│                   │  │               │  │                │  │  API — optional) │
│ - OCCRP Aleph     │  │ - IntelX      │  │ - ???          │  │                 │
│ - OpenSanctions   │  │ - Dehashed    │  │                │  │                 │
│ - OpenCorporates  │  │ - Sayari      │  │                │  │                 │
│ - crt.sh          │  │ - VirusTotal  │  │                │  │                 │
│ - Wayback         │  │ - Shodan      │  │                │  │                 │
│ - DNS/WHOIS       │  │ - GreyNoise   │  │                │  │                 │
│ - HIBP            │  │ - ...         │  │                │  │                 │
│ - GitHub Search   │  │               │  │                │  │                 │
└───────────────────┘  └───────────────┘  └────────────────┘  └─────────────────┘

  ┌──────────────────────┐   ┌──────────────────┐   ┌────────────────────────┐
  │ PostgreSQL + AGE     │   │ Redis            │   │ Object storage         │
  │ (relational + graph) │   │ (queue, cache)   │   │ (evidence artifacts —  │
  │                      │   │                  │   │  S3-compatible or local│
  └──────────────────────┘   └──────────────────┘   └────────────────────────┘
```

### 5.2 Component responsibilities

**Backend (FastAPI / Python)**
- `cases` — CRUD on investigations
- `entities` — CRUD on entities + relationships
- `plugins` — plugin registry, credential management, query orchestration
- `evidence` — immutable ledger: hash, timestamp, source, method, query, response
- `reports` — render Markdown/PDF from case state
- `ai` — pivot suggestions via Claude API (LLM structured output)

**Frontend (Next.js / TypeScript)**
- `/cases` — list + create cases
- `/cases/:id` — single case workspace
- `/cases/:id/graph` — Cytoscape graph visualization
- `/cases/:id/evidence` — evidence ledger viewer
- `/cases/:id/report` — report editor + export
- `/settings/plugins` — plugin install, enable/disable
- `/settings/credentials` — encrypted BYOK vault
- `/settings/auth` — Grafana-style auth config (local + OIDC)

**Data model (simplified)**

```sql
cases (id, name, status, created_at, created_by, tags jsonb)
entities (id, case_id, type, label, attrs jsonb, confidence, created_by, created_at)
relationships (id, src_entity_id, dst_entity_id, rel_type, confidence, source_plugin, created_at)
evidence (id, case_id, entity_id, source_plugin, query, response_hash, response_uri, timestamp, reproducibility_spec jsonb)
plugins (id, name, version, type, config jsonb, enabled)
credentials (id, plugin_id, user_id, encrypted_payload)
users (id, email, name, hashed_password_or_null, oidc_sub, role)
```

### 5.3 Plugin system

**Plugin contract (Python):**

```python
class OSINTPlugin(ABC):
    name: str
    version: str
    entity_types_accepted: list[EntityType]
    entity_types_produced: list[EntityType]
    requires_credentials: bool
    rate_limit: RateLimit

    @abstractmethod
    async def query(
        self,
        input_entity: Entity,
        credentials: Credentials | None,
        context: QueryContext,
    ) -> QueryResult:
        """
        Returns entities, relationships, and evidence records.
        Each response is deterministically hashable for chain of custody.
        """
```

Plugins can be:
- **Embedded** — ship with core (OCCRP, OpenSanctions, etc.)
- **BYOK** — ship with core, require user credentials (IntelX, Sayari)
- **Community** — installable via `osintkit plugin install <git-url>` (v1.1+)

### 5.4 Evidence chain of custody

Every plugin query produces an evidence record containing:
- Query input (entity + parameters)
- SHA-256 hash of raw response
- Timestamp (UTC, ISO 8601)
- Source plugin name + version
- Reproducibility spec (HTTP method, URL, headers, request body — sanitized)
- Response blob (stored in object storage, referenced by URI)

Evidence is **append-only** — never modified after creation. Cases can be exported with full evidence ledger for chain-of-custody handoff.

### 5.5 AI-assisted pivots (NOT full orchestration in MVP)

**Scope for MVP:** Given an entity, LLM returns 3-5 suggested next pivots with rationale. User clicks to execute.

Out of MVP scope: autonomous multi-step investigation loops. That's a v2 feature once the evidence/plugin foundation is solid.

---

## 6. MVP feature scope

### 6.1 In MVP

| # | Feature | Definition of done |
|---|---|---|
| 1 | Case management | Create, list, rename, archive, tag cases |
| 2 | Entity model + graph | 8 entity types, typed relationships, CRUD |
| 3 | Cytoscape graph UI | Pan/zoom/search/filter/node-click-detail |
| 4 | Evidence chain of custody | Immutable ledger, hash-verifiable, exportable |
| 5 | Plugin SDK (Python) | Base class + test harness + example plugin |
| 6 | Free-tier plugins (8) | OCCRP, OpenSanctions, OpenCorporates, crt.sh, Wayback, DNS/WHOIS, HIBP, GitHub |
| 7 | BYOK plugins (2) | IntelX + one other (Dehashed or VirusTotal) |
| 8 | AI pivot suggestions | Entity → LLM → 3-5 next-step options |
| 9 | Report export | Markdown + PDF, IC-tradecraft structure |
| 10 | Docker Compose deploy | `docker compose up` to local dev/prod |
| 11 | Grafana-style auth | Local users + OIDC config; no multi-tenant |

### 6.2 Explicitly out of MVP

- Multi-tenant SaaS hosting
- Team/collaboration features
- SAML / RBAC (Enterprise tier, later)
- Browser extension
- Mobile app
- Plugin marketplace / registry
- Autonomous AI investigation loops
- Built-in Tor/proxy routing (user configures at Docker-network level if wanted)
- Real-time collaboration
- Audit logs (basic event log in MVP, full audit is Enterprise)

### 6.3 Post-MVP roadmap (sketch)

- **v1.1**: Community plugins via git install
- **v1.2**: Browser extension (capture evidence while browsing)
- **v1.3**: Autonomous AI investigation (given a goal, agent runs pipeline)
- **v2.0**: Hosted SaaS tier + Enterprise features (SAML, RBAC, audit, SSO)

---

## 7. Tech stack

| Layer | Choice | Rationale |
|---|---|---|
| Backend | Python 3.12 + FastAPI + SQLAlchemy 2.x + Pydantic 2.x | OSINT ecosystem is Python; FastAPI gives us OpenAPI for free |
| Frontend | Next.js 15 + TypeScript + Tailwind + shadcn/ui | Modern, batteries-included, ecosystem velocity |
| Graph viz | Cytoscape.js | More powerful than vis.js for complex OSINT graphs |
| DB | PostgreSQL 16 + Apache AGE extension | Single DB for relational + graph; simpler ops than Neo4j |
| Queue | Redis + RQ or Arq (async Python native) | Plugin queries run async |
| Object storage | MinIO (S3-compatible) or local FS | Evidence blobs |
| AI | Claude API (anthropic SDK) | Best structured output; aligns with IC OSINT Strategy 2024-2026 |
| Auth | FastAPI-Users + python-jose + OIDC via Authlib | Grafana-style: local + OIDC |
| Deploy | Docker Compose (MVP), Kubernetes Helm chart (later) | Self-hostable, standard |
| Telemetry | OpenTelemetry (opt-in) | Standard, respects user privacy |
| CI/CD | GitHub Actions | Open-source standard |
| License | Apache 2.0 (core), commercial add-ons TBD | Most permissive for government adoption |

---

## 8. Open questions for post-spec decisions

1. **Name** — OSINTkit / Invest / OpenCase / something else? (bikeshed)
2. **Logo / branding** — later
3. **Domain name** — need to check availability once name is chosen
4. **GitHub org** — personal account or new org?
5. **Initial scope of IC-tradecraft report format** — full ICD 203 compliance is aspirational; MVP is "IC-tradecraft-inspired"
6. **First public release** — private beta with ~10 users → public 0.1.0?

---

## 9. Success criteria (MVP)

**Technical:**
- `docker compose up` works on a fresh machine, end-to-end, < 5 minutes
- Run a full investigation (create case → query 3+ plugins → export report) < 15 minutes
- Evidence chain is hash-verifiable end-to-end
- All 10 MVP features functional and tested

**Adoption:**
- 10 early users running it for real investigations within 3 months of 0.1.0
- 1 government or investigative-journalism org evaluating seriously within 6 months

**Grant readiness:**
- Complete enough product to demo in an SBIR Phase I pitch
- Open source, Apache 2.0, GitHub-hosted, reproducible deployment

---

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Data source API changes break plugins | Plugin versioning, community contributions, integration test suite |
| Founder bandwidth (single-maintainer) | Open-source community contributions; keep MVP scope small |
| Legal exposure from aggregating paid sources | Strict BYOK — never cache/resell paid source data beyond session |
| Competitive response from Maltego | Open source + community moat; Maltego can't easily pivot |
| Scope creep | This spec; MVP list is fixed until 0.1.0 ships |
| AI/LLM cost (Claude API) | Cache aggressively; user brings their own Claude API key in MVP |

---

## 11. Next steps after spec approval

1. User reviews this spec, requests changes or approves
2. Invoke `writing-plans` skill to produce a step-by-step implementation plan
3. Implementation plan breaks MVP into ordered tasks with dependencies
4. Execute in phases, with review checkpoints

---

*End of spec. Awaiting user review.*
