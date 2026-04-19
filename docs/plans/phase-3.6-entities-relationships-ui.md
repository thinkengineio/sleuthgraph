# Phase 3.6 — Entities + Relationships UI Implementation Plan

**Goal:** Complete the investigation workspace by surfacing Phase 3's entity + relationship backends in the Sleuthgraph web UI. Close the gap between "cases + evidence viewable" and "full Maltego-lite workflow usable without curl."

**Architecture:** Pure frontend. No backend changes. Extends the existing Mantine v8 + Next.js 16 codebase, mirrors the EvidencePanel pattern from Phase 4.5.

**Scope boundary:** NO graph visualization — Cytoscape is Phase 9. This phase delivers **form/table UI only** for entity + relationship CRUD. The user will see their graph as a flat list; visual-graph rendering comes later.

**Repo:** `~/sleuthgraph-web/` only.

---

## What exists vs what we add

**Case detail page today:**
- Edit form (name, status, tags)
- Archive / Delete
- **EvidencePanel** (table + upload + export)
- `Entities (coming next phase)` placeholder Card

**Case detail page after this phase:**
- Edit form (unchanged)
- **EntityPanel** (table + create modal + detail drawer) ← replaces placeholder
- **RelationshipPanel** (table + create modal + detail drawer)
- **EvidencePanel** (unchanged)

---

## API contract (Phase 3 backend — already live)

### Entities

| Method | Path | Notes |
|---|---|---|
| POST | `/cases/{id}/entities` | `{type, label, attrs?, confidence?}` → 201 EntityRead |
| GET | `/cases/{id}/entities` | `?type=&limit=&offset=` → 200 `EntityRead[]` |
| GET | `/cases/{id}/entities/{eid}` | 200 or 404 |
| PATCH | `/cases/{id}/entities/{eid}` | `{label?, attrs?, confidence?}` (type immutable) |
| DELETE | `/cases/{id}/entities/{eid}` | 204 (soft-delete) |

**Entity types (8):** `PERSON`, `ORGANIZATION`, `DOMAIN`, `IP_ADDRESS`, `EMAIL`, `PHONE`, `URL`, `CRYPTO_ADDRESS`.

### Relationships

| Method | Path | Notes |
|---|---|---|
| POST | `/cases/{id}/relationships` | `{src_entity_id, dst_entity_id, rel_type, confidence?, source_plugin?, attrs?}` → 201 |
| GET | `/cases/{id}/relationships` | `?rel_type=&src=&dst=&limit=&offset=` → 200 |
| GET | `/cases/{id}/relationships/{rid}` | 200 or 404 |
| DELETE | `/cases/{id}/relationships/{rid}` | 204 (immutable — no PATCH, delete+recreate) |

**Relationship types (8):** `OWNS`, `EMPLOYED_BY`, `REGISTERED_BY`, `HOSTED_ON`, `RESOLVES_TO`, `ASSOCIATED_WITH`, `COMMUNICATED_WITH`, `MENTIONS`.

### Ownership: 404-not-403 everywhere (no existence leak).

---

## File structure

```
~/sleuthgraph-web/
├── app/cases/[caseId]/page.tsx          # modify: add EntityPanel + RelationshipPanel
├── components/
│   ├── EntityPanel.tsx                  # new
│   ├── EntityTable.tsx                  # new
│   ├── EntityCreateModal.tsx            # new
│   ├── EntityDetailDrawer.tsx           # new
│   ├── EntityTypeBadge.tsx              # new — icon + color per EntityType
│   ├── RelationshipPanel.tsx            # new
│   ├── RelationshipTable.tsx            # new
│   ├── RelationshipCreateModal.tsx      # new
│   └── RelationshipDetailDrawer.tsx     # new (smaller — no update UI)
├── lib/
│   ├── api.ts                           # modify: Entity + Relationship types + helpers
│   ├── format.ts                        # NEW — extract humanBytes/formatTs from Evidence (closes follow-up #13)
│   └── entityTypes.ts                   # new — EntityType enum + icon+color map
└── tests/
    ├── EntityPanel.test.tsx
    ├── EntityTable.test.tsx
    ├── EntityCreateModal.test.tsx
    ├── RelationshipPanel.test.tsx
    ├── RelationshipTable.test.tsx
    └── RelationshipCreateModal.test.tsx
```

---

## Design details

### EntityType Select + icons

Map each `EntityType` to a Tabler icon + Mantine color:

| Type | Icon | Color |
|---|---|---|
| PERSON | IconUser | blue |
| ORGANIZATION | IconBuilding | grape |
| DOMAIN | IconWorld | teal |
| IP_ADDRESS | IconServer | cyan |
| EMAIL | IconMail | yellow |
| PHONE | IconPhone | pink |
| URL | IconLink | indigo |
| CRYPTO_ADDRESS | IconCurrencyBitcoin | orange |

Render via `EntityTypeBadge` component (icon + label + color). Used in:
- Entity table rows
- Entity create modal Select option rendering
- Relationship table (src/dst endpoint rendering shows the endpoint's type badge)

### EntityCreateModal

- `Select` with `data={Object.values(EntityType).map(t => ({value: t, label: t}))}` (use `itemComponent` override to render EntityTypeBadge if supported by Mantine v8 Select, otherwise use a separate `SegmentedControl` for type picking above a plain form)
- `TextInput` label (required, 1-512)
- `NumberInput` confidence (0.0–1.0 step 0.05, default 1.0) + tooltip "How confident are you this entity is real? 1.0 = certain."
- `Textarea` attrs — JSON-validated (reuse the parse-on-submit pattern from Evidence)
- Submit → POST → close + refresh

### EntityTable columns

| Type (badge) | Label | Confidence (as `0.9` in muted text) | Created | Actions (view / delete) |

### EntityDetailDrawer

- Full id, type, label, confidence (big), attrs JSON pretty-printed
- **Edit mode toggle:** `Edit` button → turns label + confidence + attrs into editable inputs, Save / Cancel
- Delete button with confirmation

### RelationshipCreateModal

This is the UX-interesting part. The user has to pick two entities (src, dst) from the current case's entity list.

- Requires the case's entity list to be fetched and passed in as prop `entities: Entity[]` (EntityPanel owns the list; RelationshipPanel gets it passed down from the case-detail page so we don't fetch twice)
- `Select` src_entity_id with search enabled — options are `{value: id, label: `${type}: ${label}`}` with type-color accent
- `Select` dst_entity_id same as src
- `Select` rel_type = 8 values
- `NumberInput` confidence 0–1
- `Textarea` attrs (JSON-validated, optional)
- Submit → POST → close + refresh BOTH relationship list AND entity list (entity may have new derived edges rendered)

**Self-loop allowed**: backend supports src == dst for ASSOCIATED_WITH. Don't block in UI.

### RelationshipTable columns

| SRC (badge) → DST (badge) | rel_type (badge) | confidence | source_plugin | Actions (view / delete) |

Render src + dst as `<EntityTypeBadge type={src.type} label={src.label} />` + arrow + same for dst. Needs access to entities-by-id lookup (passed down).

### RelationshipDetailDrawer

Simpler than entity drawer — no edit. Read-only full record + Delete button (with confirmation).

### Case detail page layout

Stack order (top to bottom):
1. Back link + title
2. Edit form card (existing)
3. Action buttons row (existing)
4. **EntityPanel** (new)
5. **RelationshipPanel** (new — needs entities from above for src/dst pickers)
6. **EvidencePanel** (existing)

---

## Conventions (same as Phase 4.5)

- Mantine v8, dark theme, no Tailwind for components
- `@mantine/form` for forms, `@mantine/notifications` for toasts
- @tabler/icons-react for all iconography
- `credentials: "include"` on every fetch
- Error handling: surface the backend error string; on 413/422/400, show the `detail` field from the JSON error body if available
- useEffect one-shot fetch: `// eslint-disable-next-line react-hooks/set-state-in-effect` with justification comment (established pattern)
- NO Claude attribution in commits (hard rule)

---

## Test plan

Mock fetch via `vi.stubGlobal`. Use `STABLE_USER` via `vi.hoisted` for useAuth mocks (prevents infinite useEffect loops — pattern from Phase 3.5+).

Minimum coverage:
- `EntityTable.test.tsx` — empty state, populated list (2 rows of different types), click view fires callback
- `EntityCreateModal.test.tsx` — form submission with all 8 types, bad JSON in attrs → error notification, confidence bounds validated
- `EntityPanel.test.tsx` — fetches on mount, shows empty state, refresh after create
- `RelationshipTable.test.tsx` — renders with src/dst labels resolved from entities prop, empty state
- `RelationshipCreateModal.test.tsx` — src/dst selects populated from entities prop, rel_type select has 8 options, submit shape correct
- `RelationshipPanel.test.tsx` — fetches on mount, integrates with entities prop
- Update `CaseDetail.test.tsx` to mock the new fetchers so existing tests don't regress

Target: ~18 new tests + existing 34 kept green = ~52/52.

---

## Commits (~8–10)

1. `refactor(ui): extract humanBytes + formatTs to lib/format.ts` (closes web#13)
2. `feat(api): entity + relationship client helpers`
3. `feat(ui): EntityTypeBadge with per-type icons + colors`
4. `feat(ui): EntityTable component`
5. `feat(ui): EntityCreateModal (all 8 types, attrs JSON)`
6. `feat(ui): EntityDetailDrawer with inline edit`
7. `feat(ui): EntityPanel container`
8. `feat(ui): RelationshipTable + RelationshipCreateModal + RelationshipDetailDrawer`
9. `feat(ui): RelationshipPanel container`
10. `feat(ui): wire EntityPanel + RelationshipPanel into case detail page (replaces Entities placeholder)`
11. `test(ui): entity + relationship components`

---

## Out of scope (deferred)

- Cytoscape graph visualization (Phase 9)
- Entity merge / dedupe (Phase 10 polish)
- Bulk entity import (Phase 5 plugin SDK)
- Evidence → entity linking UI (Phase 5 when plugins auto-link)
- Entity search across all cases (Phase 9+)
- Keyboard shortcuts (later)
- Infinite scroll / virtualization for large entity lists (Phase 9 with Cytoscape)
