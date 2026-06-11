# Hot Module Cookbook

Minimal example of [stdx `HotModule`](../../../src/hot_module.zig): load plugin logic from a DLL in Debug, link it directly in Release.

## Architecture

```
src/
├── interface.zig          # Shared extern struct (host ↔ DLL contract)
├── main.zig               # Host executable
└── plugin/
    ├── root.zig           # Plugin logic (init, deinit, transform)
    ├── +hot_module.zig    # Hot-reload wrapper (Debug only)
    └── +dll.zig           # DLL entry + exported interface (Debug only)
```

| File | Role |
|------|------|
| `root.zig` | Real plugin code. Same API whether hot-reloaded or statically linked. |
| `+hot_module.zig` | Loads the DLL beside the exe, calls `reload()` each frame, forwards to the exported interface. |
| `+dll.zig` | Builds as `plugin.dll` / `libplugin.so`; exports `dll_interface` matching `interface.zig`. |
| `interface.zig` | `extern struct` of `callconv(.c)` function pointers — identical layout in exe and DLL. |

### Why the `+` prefix?

Just for convenience to say "those files are just for wiring the dll in dev mode"

In the `build.zig` file, you can see what does `@import("plugin")` in `main.zig` resolves to:

In Debug, it resolves to a module that merges:
- `root.zig` — always present (the real implementation)
- `+hot_module.zig` — included when `build.zig` sets that file as the module root in Debug

In **Release**, `build.zig` points the `plugin` import straight at `root.zig`. No `HotModule`, no DLL, no extra indirection — the overlay files are never compiled.

the `+dll.zig` file is used to build the dll itself.

so we have in hot module mode:
```
main --imports--> hot_module --loads--> dll + plugin (module)
```
and release:
```
main --imports--> plugin (module)
```

## Debug vs Release

| | Debug (default) | Release (`-Doptimize=ReleaseFast`) |
|---|---|---|
| Hot reload | Yes (`-Dhotreload=true`, default in Debug) | No (`-Dhotreload=false`, default in Release) |
| `plugin` module root | `+hot_module.zig` | `root.zig` |
| Plugin artifact | `plugin.dll` installed beside exe | None (logic linked into exe) |
| Edit `root.zig` while running | Yes, after recompiling DLL | N/A — rebuild exe |

Force hot reload off in Debug: `zig build -Dhotreload=false run`

## Run with hot reload (two terminals)

**Terminal 1** — run the host (installs exe + initial DLL):

```sh
zig build run
```

**Terminal 2** — rebuild the DLL on save:

```sh
zig build compile_dll --watch
```

The host checks the DLL mtime each frame; when Terminal 2 produces a new build, you see `Plugin DLL reloaded` in the log.

## Run without hot module (Release)

```sh
zig build -Doptimize=ReleaseFast run
```

Plugin code is compiled into the executable. No DLL, no `stdx.HotModule` dependency in the final binary path.

## Demo: square → cube while running

1. Start both terminals as above.
2. Watch output: `frame 3 -> 9` (square).
3. Edit `src/plugin/root.zig` — change `return frame * frame` to `return frame * frame * frame`.
4. Save; Terminal 2 rebuilds the DLL.
5. On the next frame: `frame N -> N³` and a reload log line.
