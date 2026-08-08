# Application architecture

`ApplicationModel` is the SwiftUI-facing observable model. It owns published
UI snapshots, error presentation, and orchestration between domains; it does
not directly construct or call video editing and proxy services, and it does
not own background-worker bookkeeping.

## Current coordinator boundary

```text
ApplicationModel
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

`TaskCoordinator` owns task state transitions and the cancellation handle for
each worker. `ApplicationModel` receives reports and refreshes its published
task snapshot after workflows complete, keeping SwiftUI-facing state separate
from worker lifecycle bookkeeping.

## Deliberately incremental migration

This is the first vertical slice of the planned decomposition. Library root and
scan operations, photo editing/presets, and photo export/batch operations still
reside in `ApplicationModel` behind their existing tested interfaces. They are
not represented as completed coordinators. Future changes may move those
operations into `LibraryCoordinator`, `PhotoEditingCoordinator`, and
`ExportCoordinator` without changing the UI-facing public methods.
