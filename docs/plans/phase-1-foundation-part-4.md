# Phase 1 — Foundation (Part 4: Web repo + end-to-end wire-up)

Continues from [part 3](phase-1-foundation-part-3.md). Completes Phase 1 so `make up` from the meta repo brings up the full stack with health checks passing.

---

## 3. Web repo — `~/sleuthgraph-web/`

### Task 3.1: Initialize with create-next-app

**Files:**
- Create: `~/sleuthgraph-web/` directory tree (via `create-next-app`)

- [ ] **Step 1: Scaffold via create-next-app**

```bash
cd ~
pnpm create next-app@latest sleuthgraph-web \
  --typescript \
  --tailwind \
  --eslint \
  --app \
  --src-dir=false \
  --import-alias="@/*" \
  --use-pnpm \
  --no-turbopack
```

When prompted about `turbopack`, choose **No** (simpler Docker build).

- [ ] **Step 2: Verify dev server starts**

```bash
cd ~/sleuthgraph-web
pnpm dev &
PID=$!
sleep 5
curl -fsS http://localhost:3000 | head -c 200
kill $PID
```

Expected: HTML with `<title>` appears.

- [ ] **Step 3: Initial commit**

Create-next-app already ran `git init`; add what's there:

```bash
cd ~/sleuthgraph-web
git add -A
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "chore: create-next-app scaffold (TS + Tailwind + App Router)"
```

---

### Task 3.2: Add shadcn/ui

**Files:**
- Modify: `~/sleuthgraph-web/package.json`
- Create: `~/sleuthgraph-web/components.json`
- Create: `~/sleuthgraph-web/components/ui/` (generated)

- [ ] **Step 1: Init shadcn**

```bash
cd ~/sleuthgraph-web
pnpm dlx shadcn@latest init -d
```

Accept defaults. This creates `components.json` and installs peer deps.

- [ ] **Step 2: Add a couple of baseline components we'll use in Phase 8**

```bash
pnpm dlx shadcn@latest add button card input label
```

- [ ] **Step 3: Commit**

```bash
cd ~/sleuthgraph-web
git add -A
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "feat: shadcn/ui initialized with Button, Card, Input, Label"
```

---

### Task 3.3: Install test + lint tooling

- [ ] **Step 1: Install vitest + testing-library + prettier**

```bash
cd ~/sleuthgraph-web
pnpm add -D vitest @vitejs/plugin-react @testing-library/react @testing-library/jest-dom jsdom prettier
```

- [ ] **Step 2: Write vitest.config.ts**

Path: `~/sleuthgraph-web/vitest.config.ts`
```typescript
import path from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { "@": path.resolve(__dirname, "./") },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./tests/setup.ts"],
  },
});
```

- [ ] **Step 3: Write tests/setup.ts**

Path: `~/sleuthgraph-web/tests/setup.ts`
```typescript
import "@testing-library/jest-dom/vitest";
```

- [ ] **Step 4: Write .prettierrc**

Path: `~/sleuthgraph-web/.prettierrc`
```json
{
  "semi": true,
  "singleQuote": false,
  "tabWidth": 2,
  "trailingComma": "all",
  "printWidth": 100
}
```

- [ ] **Step 5: Add package.json scripts**

Edit `~/sleuthgraph-web/package.json`. Replace the `scripts` object with:
```json
"scripts": {
  "dev": "next dev",
  "build": "next build",
  "start": "next start",
  "lint": "next lint",
  "format": "prettier --write .",
  "format:check": "prettier --check .",
  "test": "vitest run",
  "test:watch": "vitest"
},
```

- [ ] **Step 6: Commit**

```bash
cd ~/sleuthgraph-web
git add -A
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "chore: vitest + testing-library + prettier config"
```

---

### Task 3.4: API client module (lib/api.ts) + first test

**Files:**
- Create: `~/sleuthgraph-web/lib/api.ts`
- Create: `~/sleuthgraph-web/tests/api.test.ts`

- [ ] **Step 1: Write failing test**

Path: `~/sleuthgraph-web/tests/api.test.ts`
```typescript
import { describe, expect, it, vi } from "vitest";

import { apiClient, getApiBaseUrl } from "@/lib/api";

describe("getApiBaseUrl", () => {
  it("returns NEXT_PUBLIC_API_URL when set", () => {
    vi.stubEnv("NEXT_PUBLIC_API_URL", "https://api.example.com");
    expect(getApiBaseUrl()).toBe("https://api.example.com");
    vi.unstubAllEnvs();
  });

  it("defaults to localhost:8000 when unset", () => {
    vi.stubEnv("NEXT_PUBLIC_API_URL", "");
    expect(getApiBaseUrl()).toBe("http://localhost:8000");
    vi.unstubAllEnvs();
  });
});

describe("apiClient.health", () => {
  it("GETs /health and returns ok payload", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ status: "ok", service: "sleuthgraph-api" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await apiClient.health();
    expect(result.status).toBe("ok");
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining("/health"), expect.any(Object));
    vi.unstubAllGlobals();
  });
});
```

- [ ] **Step 2: Write api.ts**

Path: `~/sleuthgraph-web/lib/api.ts`
```typescript
/**
 * API client for sleuthgraph-api.
 *
 * MVP is pragmatic: hand-rolled fetch wrapper. Phase 8 will switch to
 * openapi-typescript-generated types for type safety.
 */

export function getApiBaseUrl(): string {
  const url = process.env.NEXT_PUBLIC_API_URL;
  return url && url.length > 0 ? url : "http://localhost:8000";
}

type HealthResponse = { status: string; service: string };

type ReadinessResponse = {
  status: "ready" | "degraded";
  checks: Record<string, string>;
};

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${getApiBaseUrl()}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`API ${res.status}: ${body.slice(0, 200)}`);
  }
  return (await res.json()) as T;
}

export const apiClient = {
  health: () => request<HealthResponse>("/health"),
  readiness: () => request<ReadinessResponse>("/readiness"),
};
```

- [ ] **Step 3: Run tests**

```bash
cd ~/sleuthgraph-web
pnpm test
```

Expected: 3 tests pass.

- [ ] **Step 4: Commit**

```bash
cd ~/sleuthgraph-web
git add -A
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "feat: API client with /health, /readiness + tests"
```

---

### Task 3.5: Replace landing page with API health ping

**Files:**
- Modify: `~/sleuthgraph-web/app/page.tsx`
- Create: `~/sleuthgraph-web/components/HealthBadge.tsx`
- Create: `~/sleuthgraph-web/tests/HealthBadge.test.tsx`

- [ ] **Step 1: Write HealthBadge test**

Path: `~/sleuthgraph-web/tests/HealthBadge.test.tsx`
```typescript
import { render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import HealthBadge from "@/components/HealthBadge";

describe("HealthBadge", () => {
  it("shows 'Checking...' initially then 'API healthy' on ok response", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ status: "ok", service: "sleuthgraph-api" }), { status: 200 }),
    );
    vi.stubGlobal("fetch", fetchMock);

    render(<HealthBadge />);
    expect(screen.getByText(/checking/i)).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.getByText(/api healthy/i)).toBeInTheDocument();
    });

    vi.unstubAllGlobals();
  });

  it("shows 'API unreachable' on error", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("net")));
    render(<HealthBadge />);
    await waitFor(() => {
      expect(screen.getByText(/api unreachable/i)).toBeInTheDocument();
    });
    vi.unstubAllGlobals();
  });
});
```

- [ ] **Step 2: Write HealthBadge component**

Path: `~/sleuthgraph-web/components/HealthBadge.tsx`
```typescript
"use client";

import { useEffect, useState } from "react";

import { apiClient } from "@/lib/api";

type State = "checking" | "ok" | "error";

export default function HealthBadge() {
  const [state, setState] = useState<State>("checking");

  useEffect(() => {
    apiClient
      .health()
      .then(() => setState("ok"))
      .catch(() => setState("error"));
  }, []);

  const label = state === "checking" ? "Checking..." : state === "ok" ? "API healthy" : "API unreachable";
  const color =
    state === "checking"
      ? "bg-gray-200 text-gray-700"
      : state === "ok"
        ? "bg-green-100 text-green-800"
        : "bg-red-100 text-red-800";

  return (
    <span className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-sm font-medium ${color}`}>
      <span className="h-2 w-2 rounded-full bg-current" />
      {label}
    </span>
  );
}
```

- [ ] **Step 3: Replace app/page.tsx**

Path: `~/sleuthgraph-web/app/page.tsx`
```typescript
import HealthBadge from "@/components/HealthBadge";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-8 space-y-6">
      <h1 className="text-4xl font-bold">Sleuthgraph</h1>
      <p className="text-lg text-gray-600">OSINT investigation workbench · pre-alpha</p>
      <HealthBadge />
      <p className="text-sm text-gray-500">
        See{" "}
        <a className="underline" href="https://github.com/sleuthgraph/sleuthgraph" target="_blank" rel="noopener">
          github.com/sleuthgraph
        </a>{" "}
        for docs.
      </p>
    </main>
  );
}
```

- [ ] **Step 4: Run tests**

```bash
cd ~/sleuthgraph-web
pnpm test
```

Expected: 5 tests pass (3 from api.test.ts, 2 from HealthBadge.test.tsx).

- [ ] **Step 5: Visual smoke-test**

```bash
cd ~/sleuthgraph-web
pnpm dev &
PID=$!
sleep 5
# Open http://localhost:3000 in browser — should see the landing page with
# "API unreachable" badge (since backend isn't running standalone here).
kill $PID
```

- [ ] **Step 6: Commit**

```bash
cd ~/sleuthgraph-web
git add -A
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "feat: landing page with HealthBadge pinging API /health"
```

---

### Task 3.6: Dockerfile + .dockerignore

**Files:**
- Create: `~/sleuthgraph-web/Dockerfile`
- Create: `~/sleuthgraph-web/.dockerignore`

- [ ] **Step 1: Enable Next.js standalone output**

Edit `~/sleuthgraph-web/next.config.ts` — replace contents:

```typescript
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  reactStrictMode: true,
};

export default nextConfig;
```

- [ ] **Step 2: Write Dockerfile**

Path: `~/sleuthgraph-web/Dockerfile`
```dockerfile
# Multi-stage Dockerfile for Sleuthgraph web.

FROM node:22-alpine AS deps
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@9.12.0 --activate
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

FROM node:22-alpine AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@9.12.0 --activate
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1
RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
USER nextjs
EXPOSE 3000
ENV PORT=3000 HOSTNAME=0.0.0.0
CMD ["node", "server.js"]
```

- [ ] **Step 3: Write .dockerignore**

Path: `~/sleuthgraph-web/.dockerignore`
```
node_modules
.next
.git
.env
.env.*
.vscode
.idea
coverage
.nyc_output
*.log
.DS_Store
.github
```

- [ ] **Step 4: Build and smoke-test**

```bash
cd ~/sleuthgraph-web
docker build -t sleuthgraph-web:dev .
docker run --rm -d --name sg-web-smoke -p 3001:3000 \
  -e NEXT_PUBLIC_API_URL=http://host.docker.internal:8000 \
  sleuthgraph-web:dev
sleep 5
curl -fsS http://localhost:3001 | grep -q "Sleuthgraph" && echo "OK" || echo "FAIL"
docker stop sg-web-smoke
```

Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
cd ~/sleuthgraph-web
git add -A
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "chore: multi-stage Dockerfile with standalone Next.js output"
```

---

### Task 3.7: GitHub Actions CI

**Files:**
- Create: `~/sleuthgraph-web/.github/workflows/ci.yml`

- [ ] **Step 1: Write ci.yml**

Path: `~/sleuthgraph-web/.github/workflows/ci.yml`
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9.12.0 }
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm format:check
      - run: pnpm test
      - run: pnpm build

  build-image:
    needs: lint-and-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          tags: sleuthgraph-web:ci
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 2: Commit**

```bash
cd ~/sleuthgraph-web
git add .github/
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "ci: lint + test + build image on push/PR"
```

---

### Task 3.8: README for Web repo

**Files:**
- Create: `~/sleuthgraph-web/README.md`

- [ ] **Step 1: Write README**

Path: `~/sleuthgraph-web/README.md`
```markdown
# sleuthgraph-web

Frontend for [Sleuthgraph](https://github.com/sleuthgraph/sleuthgraph) — Next.js + TypeScript + Tailwind + shadcn/ui.

## Local development

Requires Node.js 22+, pnpm 9+.

```bash
pnpm install

# Point at local API (started via meta repo's docker-compose)
cp .env.example .env.local 2>/dev/null || echo 'NEXT_PUBLIC_API_URL=http://localhost:8000' > .env.local

pnpm dev
```

Open http://localhost:3000.

## Tests

```bash
pnpm test          # one-shot
pnpm test:watch    # watch mode
```

## Lint + format

```bash
pnpm lint
pnpm format
```

## Build

```bash
pnpm build
pnpm start
```

## License

Apache 2.0 — see [LICENSE](../sleuthgraph/LICENSE).
```

- [ ] **Step 2: Commit**

```bash
cd ~/sleuthgraph-web
git add README.md
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "docs: README with dev quickstart"
```

---

### Task 3.9: Push Web repo to GitHub

- [ ] **Step 1: Create repo on GitHub** (web UI)

In the `sleuthgraph` org, create `sleuthgraph-web` (Public, Apache-2.0, no autogen files).

- [ ] **Step 2: Add remote and push**

```bash
cd ~/sleuthgraph-web
git remote add origin git@github.com:sleuthgraph/sleuthgraph-web.git
git branch -M main
git push -u origin main
```

- [ ] **Step 3: Verify CI passes**

https://github.com/sleuthgraph/sleuthgraph-web/actions — both jobs should go green.

**Milestone:** Web repo is public on GitHub, CI passes, Docker image builds.

---

## 4. Wire-up — meta repo brings up the full stack

### Task 4.1: Enable api + web in compose (remove profile gate)

- [ ] **Step 1: Remove `profiles: ["app"]` from api and web**

Edit `~/sleuthgraph/deploy/docker-compose.yml` — remove the `profiles: ["app"]` lines from both `api:` and `web:` service blocks.

- [ ] **Step 2: Commit the change**

```bash
cd ~/sleuthgraph
git add deploy/docker-compose.yml
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "deploy: remove 'app' profile gate — full stack now runs by default"
```

---

### Task 4.2: Bring up the full stack

- [ ] **Step 1: Clean slate**

```bash
cd ~/sleuthgraph/deploy
docker compose --env-file .env down -v 2>/dev/null || true
```

- [ ] **Step 2: Run make up**

```bash
cd ~/sleuthgraph/deploy
make up
```

Expected output includes the API/Web/MinIO URLs.

- [ ] **Step 3: Wait for health**

```bash
sleep 30
cd ~/sleuthgraph/deploy
make ps
```

All of: `db`, `redis`, `minio`, `api`, `web` should show `healthy`. `minio-bootstrap` is `Exit 0`.

---

### Task 4.3: End-to-end health verification

- [ ] **Step 1: API /health**

```bash
curl -fsS http://localhost:8000/health | python3 -m json.tool
```

Expected:
```json
{"status": "ok", "service": "sleuthgraph-api"}
```

- [ ] **Step 2: API /readiness**

```bash
curl -fsS http://localhost:8000/readiness | python3 -m json.tool
```

Expected: `status: "ready"`, `checks.db: "ok"`.

- [ ] **Step 3: API /docs loads**

```bash
curl -fsSI http://localhost:8000/docs | head -1
```

Expected: `HTTP/1.1 200 OK`.

- [ ] **Step 4: Web loads and pings API**

```bash
curl -fsS http://localhost:3000 | grep -q "Sleuthgraph" && echo "Web loads" || echo "Web FAIL"
```

Open http://localhost:3000 in a browser — you should see the landing page with a green **"API healthy"** badge.

- [ ] **Step 5: MinIO console loads**

```bash
curl -fsSI http://localhost:9001 | head -1
```

Expected: `200 OK` (MinIO console).

---

### Task 4.4: Run both test suites inside containers

- [ ] **Step 1: API tests**

```bash
cd ~/sleuthgraph/deploy
docker compose --env-file .env exec api pytest -v
```

Expected: All tests pass.

- [ ] **Step 2: Web tests**

```bash
docker compose --env-file .env exec web pnpm test
```

Expected: All tests pass.

---

### Task 4.5: Document phase-1 completion

**Files:**
- Modify: `~/sleuthgraph/README.md`

- [ ] **Step 1: Add status badge section to README**

Append to `~/sleuthgraph/README.md`:
```markdown

## Status

| Phase | Status |
|---|---|
| 1. Foundation | ✅ Complete (2026-04-17) |
| 2. Auth | ⏳ Pending |
| 3. Core API | ⏳ Pending |
| 4. Evidence | ⏳ Pending |
| 5. Plugin SDK | ⏳ Pending |
| 6. Free plugins | ⏳ Pending |
| 7. BYOK plugins | ⏳ Pending |
| 8. Frontend shell | ⏳ Pending |
| 9. Graph viz | ⏳ Pending |
| 10. AI + Reports + polish | ⏳ Pending |
```

- [ ] **Step 2: Commit**

```bash
cd ~/sleuthgraph
git add README.md
git -c user.email="sadik@local" -c user.name="Sadik" commit -m "docs: mark Phase 1 complete in status table"
```

---

### Task 4.6: Push meta repo to GitHub

- [ ] **Step 1: Create repo on GitHub**

In `sleuthgraph` org, create `sleuthgraph` (Public, Apache-2.0).

- [ ] **Step 2: Push**

```bash
cd ~/sleuthgraph
git remote add origin git@github.com:sleuthgraph/sleuthgraph.git
git branch -M main
git push -u origin main
```

---

## 🏁 Phase 1 exit criteria

- [x] All three repos exist on GitHub (public, Apache 2.0)
- [x] `make up` from `~/sleuthgraph/deploy/` starts full stack
- [x] All health checks green within 60 seconds of startup
- [x] `/health`, `/readiness`, `/docs` respond 200
- [x] Web landing page shows green "API healthy" badge
- [x] API test suite passes inside container
- [x] Web test suite passes inside container
- [x] API CI pipeline green on GitHub
- [x] Web CI pipeline green on GitHub
- [x] README status table updated

**If all boxes are checked, Phase 1 is done.** Move on to [Phase 2 (Auth)](./) — plan to be written next.

---

## Self-review checklist

- [ ] **Spec coverage** — This plan delivers feature #10 (Docker Compose deploy) from spec section 6.1. Features 1-9 and 11 come in later phases per the index.
- [ ] **No placeholders** — Every step shows complete file contents, exact commands, exact expected outputs.
- [ ] **Type consistency** — `apiClient`, `HealthBadge`, `getApiBaseUrl`, `Settings` names are consistent across tests and implementation.
- [ ] **Engineer assumptions documented** — Python 3.12, Node 22, Docker 24+, pnpm 9 stated in prerequisites.
- [ ] **Every task ends with a commit** — yes.
- [ ] **Every task has a test or verification step** — yes.
- [ ] **File paths are absolute** — yes (`~/sleuthgraph/...`).

---

## Status tracker — full Phase 1

Section 1 (meta repo):
- [ ] 1.1 LICENSE + .gitignore
- [ ] 1.2 README
- [ ] 1.3 deploy dir skeleton
- [ ] 1.4 Makefile
- [ ] 1.5 docker-compose files
- [ ] 1.6 Verify services-only

Section 2 (API repo):
- [ ] 2.1 – 2.12 (all 12 tasks)

Section 3 (Web repo):
- [ ] 3.1 – 3.9 (all 9 tasks)

Section 4 (wire-up):
- [ ] 4.1 Remove app profile gate
- [ ] 4.2 Bring up full stack
- [ ] 4.3 End-to-end health verification
- [ ] 4.4 Test suites in containers
- [ ] 4.5 Document phase-1 done
- [ ] 4.6 Push meta repo

**Total: 33 tasks. Each task = one commit. Expected Phase 1 commit count: ~33.**
