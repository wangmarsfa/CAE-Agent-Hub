# AGENTS.md

## Cursor Cloud specific instructions

This repo (CAE Agent Hub) is a multi-product monorepo. Only one product is runnable in a
standard Cloud VM:

### Text to CAE Viewer (`viewer/`) — the only runnable service here
- Stack: Node + Vite 7 + React 18 + Three.js. Package manager is **npm** (`viewer/package-lock.json`).
- All commands run from `viewer/`. Standard scripts live in `viewer/package.json`:
  - Dev server: `npm run dev` (Vite, binds `127.0.0.1:4178`, `strictPort` — port is fixed).
  - Build: `npm run build`. Preview a built bundle: `npm run start`.
  - There is **no lint script and no test suite** in this repo.
- The dev server uses a custom Vite middleware (`viewer/vite.config.mjs`) that serves case data
  from the repo's `models/*` folders via `/__cae/*` endpoints (e.g.
  `/__cae/result-summary?dir=models/text-to-cae-hole-plate`). There is **no database** — data is
  flat JSON (`cae_project.json` / `result_mesh.json`) on disk.
- Load a case in the browser with a `case` query param, e.g.
  `http://127.0.0.1:4178/?case=hole-plate` (other cases: `cantilever`, `hole-plate-modal`,
  `sphere-impact`, `milling-3d`, `gear-mesh`, `bullet-plate`).
- The `/__cae/run` endpoint shells out to a local Abaqus binary (`ABAQUS_COMMAND`, default a
  Windows path). This is **optional and unavailable in the Cloud VM**; the viewer fully works with
  the pre-exported `result_mesh.json` data without it.

### MCP servers (`MCP/Abaqus`, `MCP/Ansys/*`) — NOT runnable here
- Python 3.10+ packages (install per-folder with `pip install -e .`). They bridge to proprietary,
  separately-licensed, Windows-only CAE desktop apps (Abaqus/CAE, ANSYS Fluent, Workbench/Mechanical,
  AEDT/HFSS) which cannot be installed in a Linux sandbox. Treat them as optional / non-blocking.

### Skills (`Skill/`) and models (`models/`)
- `Skill/` is static Markdown instruction packs (no runtime). `models/` holds example case data and
  solver scripts consumed by the viewer.
