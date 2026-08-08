# Application architecture

`ApplicationModel` is the SwiftUI-facing observable model. It owns published
UI snapshots, error presentation, and orchestration between domains; it does
not directly construct or call photo/RAW/LUT or video/proxy services, and it
does not own background-worker bookkeeping.

## Current coordinator boundary

```text
ApplicationModel
├── PhotoEditingCoordinator
│   ├── PhotoEditingService
│   ├── PresetRepository
│   └── photo edit state, RAW state, preview/render, LUT and batch-export work
├── VideoEditingCoordinator
│   ├── VideoEditingService
│   ├── VideoProxyService
│   └── media-root resolution and source-path validation
└── TaskCoordinator
    ├── BackgroundTaskCenter lifecycle
    └── cancellation handles for active workers
```

`VideoEditingCoordinator` composes the real video services and is the single
path for playback source resolution, edit-state persistence, preview payloads,
LUT lookup, export and proxy generation/removal. It validates that a referenced
video remains inside its security-scoped media root before it returns a source
URL. It does not publish SwiftUI state or create dialogs.

`PhotoEditingCoordinator` composes the real `PhotoEditingService` and
`PresetRepository`. It is the single path for photo and RAW edit-state
persistence, preset CRUD/import/export, preview rendering, LUT operations,
RAW export, preset application and the actual photo batch-export work. The
coordinator never publishes UI state or resolves a collision dialog; those
presentation concerns remain in `ApplicationModel` and its existing forwarding
methods keep SwiftUI call sites stable.

`TaskCoordinator` owns task state transitions and the cancellation handle for
each worker. `ApplicationModel` receives reports and refreshes its published
task snapshot after workflows complete, keeping SwiftUI-facing state separate
from worker lifecycle bookkeeping.

## Deliberately incremental migration

This remains an incremental decomposition. Library root/scan/catalog refresh
operations and photo-export task/collision orchestration still reside in
`ApplicationModel` behind their existing tested interfaces. A future
`LibraryCoordinator` or `ExportCoordinator` may own those concrete slices
without changing the UI-facing public methods.
