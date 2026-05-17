# Sleuthgraph editions

Sleuthgraph ships in two editions so investigators, small firms, and organizations
can use it however fits them best. **The Community Edition is open source and free
forever.** Cloud is a hosted SaaS at sleuthgraph.io that extends Community with
advanced features and managed infrastructure.

This page documents the split transparently so nobody feels bait-and-switched
when a feature announcement says "coming to Cloud."

## Quick matrix

| Feature | Community (OSS) | Cloud (SaaS) |
|---|:---:|:---:|
| **Core** | | |
| Cases, entities, relationships | ✅ | ✅ |
| Evidence chain of custody + MinIO | ✅ | ✅ |
| Cytoscape graph visualization | ✅ | ✅ |
| Plugin SDK | ✅ | ✅ |
| 8 free OSINT plugins (crt.sh, DNS, Wayback, OpenCorporates, GitHub, OpenSanctions, Aleph, URLhaus) | ✅ | ✅ |
| Local email/password auth + OIDC | ✅ | ✅ |
| Docker-compose self-host | ✅ | — |
| **BYOK paid plugins (Phase 7)** | | |
| HIBP, VirusTotal, Shodan (bring-your-own key) | ✅ | ✅ |
| IntelX, Recorded Future, Flashpoint, DarkOwl (premium adapters) | — | ✅ |
| Curated proprietary feeds | — | ✅ |
| **AI + reports (Phase 10)** | | |
| AI pivot-suggestion engine | — | ✅ |
| Cross-case entity resolution | — | ✅ |
| Polished PDF report templates | — | ✅ |
| **Team + governance** | | |
| Role-based access control (RBAC) | — | ✅ |
| SSO group → role auto-provisioning | — | ✅ |
| Audit log export to SIEM | — | ✅ |
| Legal hold + retention policies | — | ✅ |
| **Operations** | | |
| Continuous monitoring + alerts | — | ✅ |
| Shared-infra managed upgrades | — | ✅ |
| SLA + 24/7 support | — | ✅ (paid tiers) |
| SOC 2 report | — | ✅ |

## What Community includes (and always will)

Community is Apache 2.0 licensed and lives at
[`francose/sleuthgraph-api`](https://github.com/francose/sleuthgraph-api) and
[`francose/sleuthgraph-web`](https://github.com/francose/sleuthgraph-web).
Clone the repos, run `docker compose up`, and you have:

- Full case management
- The typed entity graph (8 types) and relationship model
- Complete evidence chain of custody with SHA-256 content-addressed storage
- The interactive Cytoscape graph viz
- All 8 free plugins
- Local and OIDC auth
- The plugin SDK so you can ship your own adapters

**Nothing listed as Community today will ever move behind a paywall.** New
advanced features may land as Cloud-only, but existing Community features keep
shipping in Community forever.

## What Cloud adds (hosted at sleuthgraph.io)

Everything in Community, plus we run the infrastructure. Tiers TBD, but:

- **Free tier** — 1 case, limited entities, community support. Try the product.
- **Team tier** — per-user pricing, real quotas, email support.
- **Business tier** — SSO, SLA, dedicated support, compliance.

The proprietary bits that make Cloud work (tenant provisioning, billing,
usage metering, admin dashboard) live in `francose/sleuthgraph-cloud` and
are never distributed — they run only on our infrastructure.

## Why this split

Sleuthgraph-the-code is open source because that's how you earn trust in the
security / investigations space and grow a plugin ecosystem. Community will
always be capable enough to run real investigations end-to-end.

Sleuthgraph-the-business lives on Cloud. Paying customers subsidize the work
that lets Community keep shipping.

Questions about the split: open an issue on the
[meta repo](https://github.com/francose/sleuthgraph/issues) and tag it
`question`. Commercial inquiries: sales@sleuthgraph.com (placeholder).

## Plugin authors

If you write a plugin and want to ship it in the Community package, set
`premium = False` on your `OSINTPlugin` subclass and open a PR against
`sleuthgraph-api`. If you want to ship a paid adapter that only runs on
Cloud installs, set `premium = True` and contact us about the marketplace
program.
