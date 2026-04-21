# Phase 5.5 — Plugin Run UI Implementation Plan

**Goal:** Make the Phase 5 plugin system usable from the browser. Investigator opens a case, picks an entity, clicks "Run plugin" → crt.sh discovers subdomains → new entities, relationships, and evidence appear in the existing panels without a page refresh. Run history visible per case.

**Architecture:** Pure frontend. No backend changes. Extends the existing Mantine v8 + Next.js 16 codebase, mirrors EvidencePanel / EntityPanel patterns.

**Scope:**
- Plugin API client helpers
- `RunPluginModal` — launched from EntityDetailDrawer; picks an applicable plugin, shows loading state during sync-in-request, handles success + error paths
- `PluginRunsPanel` on case detail — paginated run history table
- `PluginRunDetailDrawer` — read-only record view with taxonomy error, counts, duration, reproducibility notes
- Refresh pattern: successful run emits an event; EntityPanel + RelationshipPanel + EvidencePanel all bump their refresh counters

**Repo:** `~/sleuthgraph-web/` only.

---

## Key UX decisions

### Where does "Run plugin" live?

**EntityDetailDrawer** (existing component). When a user opens an entity's drawer:
- Compute applicable plugins by filtering `plugins.entity_types_accepted ∋ entity.type`
- If ≥1 applicable, show a "Run plugin" section with a Button per applicable plugin
- Click → opens `RunPluginModal` prefilled with entity + plugin
- Rejected (no applicable plugins) → section hidden

This keeps the discovery flow intuitive: analyst picks entity → sees what data sources can act on it.

### Loading state during sync-in-request

crt.sh takes 5–30 seconds. The modal cannot just show a spinner and call it done — the user needs reassurance. Pattern:
1. Click "Run" → modal enters "running" state with a Mantine `Loader` + progress hint ("Contacting crt.sh — this typically takes 5–30s")
2. Disable Close button while running (prevent accidental cancel; there's no server-side cancel for MVP)
3. On success: swap to "success" state with a green check + counts ("4 entities, 4 relationships, 1 evidence record"); auto-close after 2s OR keep open with a "Close" button
4. On 422/500: red error state with the error detail from the backend (which is now a safe taxonomy string, not raw exception — MEDIUM-1 fixed)

### Refresh pattern

Successful run → parent case-detail page bumps a `refreshToken` state var. EntityPanel, RelationshipPanel, EvidencePanel each pass it as a dep to their fetch `useEffect` (already architected this way in Phase 4.5). Adding PluginRunsPanel to the list.

### Plugin runs panel placement

Below EvidencePanel on case detail. Reads from `GET /cases/{id}/plugins/runs`. Columns:

| Plugin | Status | Duration | Created | Counts (E/R/Ev) | Actions |

Status shown as colored badge (succeeded=green, failed=red, running=yellow). Row click opens detail drawer.

---

## File structure

```
~/sleuthgraph-web/
├── app/cases/[caseId]/page.tsx                  # add PluginRunsPanel + refresh token wiring
├── components/
│   ├── PluginRunsPanel.tsx                      # run history table + create from EntityDetailDrawer
│   ├── PluginRunsTable.tsx
│   ├── PluginRunDetailDrawer.tsx                # read-only full audit row
│   ├── RunPluginModal.tsx                       # loading + success + error states
│   └── EntityDetailDrawer.tsx                   # MODIFY — add applicable plugins section
├── lib/
│   ├── api.ts                                   # add plugin types + helpers
│   └── pluginStatus.ts                          # NEW — status → color/icon/label mapping
└── tests/
    ├── RunPluginModal.test.tsx
    ├── PluginRunsPanel.test.tsx
    └── PluginRunsTable.test.tsx
```

---

## API contract (Phase 5 backend live on main)

| Method | Path | Returns |
|---|---|---|
| GET | `/plugins` | `PluginInfo[]` |
| GET | `/plugins/{name}` | `PluginInfo` or 404 |
| POST | `/cases/{id}/plugins/{name}/run` | `{run, entities, relationships, evidence}` on 201. 404 on case/plugin not found, 422 on type mismatch, 500 on upstream failure |
| GET | `/cases/{id}/plugins/runs` | `PluginRunList {items, total, limit, offset}` |
| GET | `/cases/{id}/plugins/runs/{run_id}` | `PluginRunRead` or 404 |

**PluginInfo shape:**
```ts
{
  name: "crtsh",
  version: "0.1.0",
  entity_types_accepted: ["DOMAIN"],
  entity_types_produced: ["DOMAIN"],
  requires_credentials: false
}
```

**PluginRunRead shape:**
```ts
{
  id: string,
  case_id: string,
  input_entity_id: string | null,
  plugin_name: string,
  plugin_version: string,
  started_at: string (ISO),
  finished_at: string | null,
  status: "running" | "succeeded" | "failed",
  error_message: string | null,  // Taxonomy label after MEDIUM-1 fix (e.g. "upstream_http_error:HTTPStatusError")
  entities_created_count: number,
  relationships_created_count: number,
  evidence_count: number,
  created_by: string | null
}
```

---

## Design details

### Run plugin modal states

```
IDLE (modal opens)
├── Entity: {type badge} {label}
├── Plugin: crtsh@0.1.0
├── Description: "Discover subdomains via Certificate Transparency (5–30s)"
└── [Cancel] [Run]

↓ click Run ↓

RUNNING
├── Loader
├── "Contacting crtsh@0.1.0..."
├── Elapsed: 00:07
└── Close button disabled

↓ HTTP 201 ↓

SUCCESS
├── ✓ Green check
├── "Plugin succeeded in 27.6s"
├── "+ 4 entities, + 4 relationships, + 1 evidence record"
└── [Close]

↓ HTTP 422/500 ↓

ERROR
├── ✗ Red X
├── "Plugin failed: <error_message from backend>"
├── Possible causes hint (based on taxonomy prefix)
└── [Close] [Retry]
```

### Applicable plugins on EntityDetailDrawer

```tsx
// Pseudocode
const applicablePlugins = plugins.filter(p =>
  p.entity_types_accepted.includes(entity.type)
);

{applicablePlugins.length > 0 && (
  <Card withBorder>
    <Title order={6}>Run plugin</Title>
    <Stack gap="xs">
      {applicablePlugins.map(p => (
        <Button
          key={p.name}
          variant="light"
          leftSection={<IconPlayerPlay />}
          onClick={() => setRunModalPlugin(p)}
        >
          {p.name}@{p.version}
        </Button>
      ))}
    </Stack>
  </Card>
)}
```

Fetch `GET /plugins` once at the case-detail level, pass down through EntityPanel → EntityDetailDrawer.

### PluginRunsPanel columns

| Column | Format |
|---|---|
| Plugin | Badge with name@version |
| Status | Colored Badge (green/red/yellow) |
| Duration | `27.6s` or `—` for still-running |
| Created | Relative time tooltip with absolute |
| Counts | `4E · 4R · 1Ev` (monospace) |
| Actions | View detail drawer |

Empty state: "No plugin runs yet. Open an entity and click Run plugin to capture your first run."

### PluginRunDetailDrawer

Shows:
- Plugin + version
- Status badge
- Input entity ID (with link to open the entity)
- Timestamps (started / finished) + duration
- Counts breakdown
- If status=failed: error_message displayed as code (taxonomy label)
- If status=succeeded: possibly a "View created entities" link that filters the entity panel

---

## Tests

Follow existing patterns:
- Mock fetch via `vi.stubGlobal`
- `vi.hoisted` + `STABLE_USER` for useAuth
- Skip tests that would require real HTTP timing (the sync-in-request 30s)

Minimum coverage:
- `RunPluginModal.test.tsx` — idle renders plugin info, click Run → fetch called, 201 → success state with counts, 422 → error state with detail, 500 → error state
- `PluginRunsPanel.test.tsx` — empty state, populated list, row click → drawer opens
- `PluginRunsTable.test.tsx` — status badge colors, duration calc, empty state

~12 new tests.

---

## Conventions

- Mantine v8 dark theme, no Tailwind for components
- `credentials: "include"` on all fetches
- 404 from backend → neutral "not found" (no existence leak)
- NEVER Claude attribution in commits

---

## Commits (~7)

1. `feat(api): plugin client helpers (list / run / runs)`
2. `feat(ui): pluginStatus mapping helpers`
3. `feat(ui): RunPluginModal with idle/running/success/error states`
4. `feat(ui): add applicable-plugins section to EntityDetailDrawer`
5. `feat(ui): PluginRunsTable + PluginRunDetailDrawer`
6. `feat(ui): PluginRunsPanel container + case-detail integration`
7. `test(ui): plugin run flow + panel`

---

## Out of scope / follow-ups

- Live progress streaming (WebSocket) — Phase 9+
- Scheduled plugin runs (cron) — later
- Bulk plugin runs across multiple entities — later
- Server-side cancel of a running plugin — needs async queue (Phase 6)
- Plugin config UI (API keys for BYOK) — Phase 7.5
- Last-run-for-entity badge on EntityTable — nice-to-have follow-up

## Test plan (after merge)

- [ ] Open a case with a DOMAIN entity
- [ ] Click view on the entity → drawer shows "Run plugin" section with crtsh button
- [ ] Click crtsh → modal opens with plugin info + Run button
- [ ] Click Run → loader spinner appears, counter ticks up
- [ ] After ~10–30s: success state with counts
- [ ] Close modal → EntityPanel, RelationshipPanel, EvidencePanel, PluginRunsPanel all refresh with new rows
- [ ] PluginRunsPanel shows new succeeded row
- [ ] Click the run → drawer shows full audit details
