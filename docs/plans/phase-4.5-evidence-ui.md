# Phase 4.5 — Evidence Viewer UI Implementation Plan

**Goal:** Surface the Phase 4 evidence backend (PR #29 merged) in the Sleuthgraph web UI. Investigators can upload a piece of evidence, view the ledger for a case with hash + timestamp + source, preview/download the blob, and export the ledger as CSV for legal handoff.

**Architecture:** Pure frontend work. No backend changes. Extends the existing Mantine v8 + Next.js 16 App Router codebase. Uses the evidence endpoints already live in the API.

**Tech:** Mantine v8 (@mantine/core, @mantine/form, @mantine/notifications, @tabler/icons-react). TypeScript. Vitest + React Testing Library.

**Repo:** `~/sleuthgraph-web/` only.

---

## Scope

1. **Replace the "Entities (0) — coming next" placeholder on `/cases/[caseId]`** with an **Evidence** card (skip entity UI for now — separate phase).
2. **Evidence table** — Mantine Table with: hash (short, monospace, copy-on-click), timestamp, source_plugin (badge), query (truncated), size (human-readable), content_type, actions (download blob, view details).
3. **Upload evidence modal** — Mantine Modal with drag-drop file field (`@mantine/dropzone`), query TextInput, source_plugin TextInput (default "manual"), submit → POST multipart → close modal + refresh list.
4. **Evidence detail drawer** — Mantine Drawer showing full record: id, timestamp, full hash (copyable), entity_id (if any), content_type, byte size, reproducibility_spec pretty-printed as JSON in a monospace block.
5. **Download blob** — open the `/cases/{cid}/evidence/{eid}/blob` URL in a new tab; browser handles the 307 redirect to MinIO.
6. **Export CSV** — button that triggers `GET /cases/{cid}/evidence/export?format=csv`; frontend uses `credentials: "include"` via apiFetch + saves blob to disk via anchor-download trick.
7. **Tests** — vitest tests for EvidenceTable (empty + populated), UploadModal (form submission with mocked fetch), DownloadBlob (opens correct URL).

---

## File structure

```
~/sleuthgraph-web/
├── app/cases/[caseId]/page.tsx          # modify: replace entities placeholder with EvidencePanel
├── components/
│   ├── EvidencePanel.tsx                # new: container — table + upload button + export button
│   ├── EvidenceTable.tsx                # new: Mantine table of rows
│   ├── EvidenceUploadModal.tsx          # new: modal with dropzone + form
│   └── EvidenceDetailDrawer.tsx         # new: drawer with full record
├── lib/
│   ├── api.ts                           # modify: add Evidence types + helpers (list, upload, get, blob URL, export URL)
├── tests/
│   ├── EvidenceTable.test.tsx
│   ├── EvidenceUploadModal.test.tsx
│   └── EvidencePanel.test.tsx
```

---

## Tasks (1 or 2 agent passes)

### Task A — API client extension

Add to `lib/api.ts`:

```ts
export type Evidence = {
  id: string;
  case_id: string;
  entity_id: string | null;
  source_plugin: string;
  query: string;
  response_hash: string;
  response_uri: string;
  response_bytes: number;
  response_content_type: string | null;
  timestamp: string;
  reproducibility_spec: Record<string, unknown>;
  created_by: string | null;
  blob_url: string | null;
};

export type EvidenceList = {
  items: Evidence[];
  total: number;
  limit: number;
  offset: number;
};

export async function listEvidence(
  caseId: string,
  opts: { limit?: number; offset?: number; entity_id?: string; source_plugin?: string } = {}
): Promise<EvidenceList> { ... }

export async function uploadEvidence(
  caseId: string,
  file: File,
  metadata: { query: string; source_plugin?: string; entity_id?: string; reproducibility_spec?: Record<string, unknown> }
): Promise<Evidence> {
  const body = new FormData();
  body.append("file", file);
  body.append("metadata", JSON.stringify(metadata));
  const res = await fetch(`${API_URL}/cases/${caseId}/evidence`, {
    method: "POST",
    credentials: "include",
    body,
  });
  if (!res.ok) throw new Error(await res.text().catch(() => `HTTP ${res.status}`));
  return res.json();
}

export function evidenceBlobUrl(caseId: string, evId: string): string {
  return `${API_URL}/cases/${caseId}/evidence/${evId}/blob`;
}

export function evidenceExportUrl(caseId: string, format: "json" | "csv" = "csv"): string {
  return `${API_URL}/cases/${caseId}/evidence/export?format=${format}`;
}
```

### Task B — Components

1. **EvidencePanel** — container card. Fetches list on mount + case change. Renders table + "Upload evidence" button + "Export CSV" button + empty state. Passes onRowClick to EvidenceTable to open the detail drawer.
2. **EvidenceTable** — columns: hash (short 12 chars + ActionIcon to copy full), timestamp (monospace, relative + full on hover), source_plugin (Badge), query (truncated with tooltip), size (humanized), type, actions (IconDownload → opens blob URL in new tab, IconEye → open drawer).
3. **EvidenceUploadModal** — @mantine/dropzone with accepted types `*/*`, @mantine/form with `query` required + `source_plugin` default "manual" + `reproducibility_spec` as a Textarea that parses JSON on submit (validate — show error notification on parse failure). Submit → uploadEvidence → success notification → close + refresh.
4. **EvidenceDetailDrawer** — opens from EvidenceTable row. Shows full record. reproducibility_spec rendered in a `<Code block>` via `<Prism>` or just `<Box bg>` with `<pre>` for MVP.

### Task C — Case detail page integration

In `app/cases/[caseId]/page.tsx`, replace the "Entities (0) — coming next" Card with `<EvidencePanel caseId={caseId} />`. Keep the card shell + add an "Entities (coming)" smaller placeholder.

### Task D — Tests

- `EvidenceTable.test.tsx` — renders empty state, renders list of 2 evidence rows, click actions fire callbacks.
- `EvidenceUploadModal.test.tsx` — form submission, bad JSON in spec → error notification, successful upload → onSubmit called with the expected shape.
- `EvidencePanel.test.tsx` — fetches on mount (mocked), shows empty state when no items, shows list when items present, click "Upload" opens modal, click "Export CSV" triggers a download.

---

## Integration notes

- **Evidence blob download UX:** the anchor `<a href={blobUrl} target="_blank" rel="noopener">` should trigger a new tab which hits the API, gets a 307, and the browser follows to MinIO. Operators must have MinIO reachable at a browser-resolvable host (documented in Phase 4 README).
- **Export CSV:** anchor with `download` attribute and `credentials: "include"` on the fetch. Browser can't send credentials with a bare anchor, so use a fetch → blob → URL.createObjectURL → anchor.click pattern for authenticated downloads:
  ```ts
  async function exportCsv(caseId: string) {
    const res = await fetch(evidenceExportUrl(caseId, "csv"), { credentials: "include" });
    if (!res.ok) throw new Error("export failed");
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `case-${caseId}-evidence.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }
  ```

---

## Commits (~6–8)

- `feat(api): evidence client helpers (list / upload / blob url / export url)`
- `feat(ui): EvidenceTable component`
- `feat(ui): EvidenceUploadModal with dropzone + form`
- `feat(ui): EvidenceDetailDrawer for full record view`
- `feat(ui): EvidencePanel container + case-detail integration`
- `test(ui): evidence components`
- `refactor(ui): minor polish` (if needed)

---

## Out of scope

- Entity UI (Phase 4.6 or later; evidence panel has a "linked entity" dropdown placeholder only)
- AI pivot suggestions (Phase 10)
- Graph visualization (Phase 9)
- Evidence search/filter UI beyond source_plugin (defer; backend supports it)
- Presign URL rewriting for CORS-restricted MinIO (deferred to ops docs)

---

## Follow-up possibilities

- Entity link dropdown on upload (needs entity UI first)
- Drag-drop multiple files at once
- Inline preview for text/JSON/image blobs
- Hash-copy keyboard shortcut
