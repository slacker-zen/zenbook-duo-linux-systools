# Zenbook Duo UI

Active Tauri/Solid tray utility for `zenbook-duo-linux-systools`.

The UI talks to the root-level control layer:

```bash
../control/zenbook-duo-control.sh
```

It should not call `coordinator/`, `sysstates/`, or `fnkeys/` helpers directly. Keep UI behavior here and helper orchestration in `control/`.
