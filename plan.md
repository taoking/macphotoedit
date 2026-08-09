# Mac Photo Studio — Execution Tracker

The authoritative product requirements and acceptance criteria are
`mac_photo_studio_plan.md` and `mac_photo_studio_prompt.md`. This file is the
required, concise execution tracker for the long-running implementation.

- [x] Phase 0 — Foundation
- [x] Phase 1 — Catalog + Folder Indexing
- [x] Phase 2 — Photo Library UX
- [x] Phase 3 — Photo Editing + LUT
- [x] Phase 4 — RAW Editing
- [x] Phase 5 — Presets + Batch + Export
- [x] Phase 6 — Advanced Photo Management
- [x] Phase 7 — Color Management + HDR
- [x] Phase 8 — Video Library
- [x] Phase 9 — Video Editing + LUT
- [x] Phase 10 — Advanced Video
- [x] Phase 11 — Local Masks / Smart Features
- [x] Phase 12.1 — Real Color Space Output
- [x] Phase 12.2 — Photo Color Pipeline
- [x] Phase 12.3 — Technical LUT Correctness
- [x] Phase 12.4 — RAW Color Pipeline
- [x] Phase 12.5 — Video Geometry / Metadata
- [x] Phase 12.6 — Video Preview State
- [x] Phase 12.7 — PlayerItem Observer
- [x] Phase 12.8 — Audio Gain
- [x] Phase 12.9 — Video Export Reliability
- [x] Phase 12.10 — HDR Capability Audit
- [x] Phase 12.11 — ApplicationModel Refactor
- [x] Phase 12.12 — Photo Pipeline Performance
- [x] Phase 12.13 — Local Mask Canvas UX
- [x] Phase 13 — Brush Mask
- [x] Phase 14 — Subject / Sky Mask
- [x] Phase 15 — Similar Photo Detection
- [x] Phase 16 — Editing Correctness & Real Media Validation
  - [x] 16.1 Local Mask Transform Coordinate Correctness
  - [x] 16.2 Technical LUT Strength Correctness
  - [x] 16.3 Subject Mask Stable Source + Cache
  - [x] 16.4 RAW Real-Media Validation Infrastructure
  - [x] 16.5 Still Image Color Real Validation
  - [x] 16.6 Video Real-Media Validation
  - [x] 16.7 External Storage Validation
  - [x] 16.8 Similar Photo Large-Library Benchmark
  - [x] 16.9 Similar Group Review UX
  - [x] 16.10 ApplicationModel Incremental Refactor
  - [x] 16.11 CI / Regression Gate
- [x] Phase 16.12 — Correctness Audit Fix
  - [x] 16.12.1 Preserve local-mask radius at image and crop edges
  - [x] 16.12.2 Remove global Vision generation lock contention
  - [x] 16.12.3 Strengthen non-persistent subject-mask source fingerprint
  - [x] 16.12.4 Pin CI generation dependencies and project drift check
  - [ ] Similar-photo persistent cache resource identifier — DEFERRED: this would
    require a new Catalog migration and migration/invalidity coverage; the
    existing file size + modification-time signature remains intact rather than
    risking persistent-cache compatibility in this correctness round.

## UI/UX Redesign Phase 1

Scope: improve the existing macOS library experience without adding new media
processing, storage, cloud, or AI capabilities. Every item must reuse the
already-tested referenced-folder and Catalog workflows.

- [x] UI-1.1 — Empty-library onboarding
- [x] UI-1.2 — Library toolbar hierarchy
- [x] UI-1.3 — Sidebar information architecture
- [x] UI-1.4 — Inspector states
- [x] UI-1.5 — Native desktop density and responsive layout polish
- [x] UI-1.6 — Add-media / scan flow clarity
- [x] UI-1.7 — Drag-and-drop feasibility decision (DEFERRED: persistent security-scoped access contract)
- [x] UI-1.8 — Accessibility and final regression audit

## UI/UX Redesign Phase 2 — Workspace & Interaction Redesign

Scope: make the existing library workspace behave as a focused native macOS
working environment. Reuse the Catalog, referenced-folder, selection,
preview/editor, scan and batch-operation paths already in the product; do not
add a second media-processing, storage or import architecture.

- [x] UI-2.1 — Full-height native workspace shell
- [x] UI-2.2 — Native sidebar location selection
- [x] UI-2.3 — Content header and loading hierarchy
- [x] UI-2.4 — Toolbar hierarchy and view options
- [x] UI-2.5 — Secondary native inspector
- [x] UI-2.6 — Selection and activation interaction contract
- [x] UI-2.7 — Contextual selection actions
- [ ] UI-2.8 — Grid density and pagination polish
- [ ] UI-2.9 — Drag-and-drop safety re-evaluation (DEFERRED unless a durable
  security-scoped dropped-folder access contract is implemented and verified)
