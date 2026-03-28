# Ghostty Elixir NIF — Implementation Plan

## Decision: Zigler + libghostty-vt C API (direct)

**Skip `libghostty-rs`.** Going through Rust adds a whole extra FFI layer (Elixir → Rust → C → Zig) for no benefit. libghostty-vt exposes a clean C API directly, and Zigler is designed exactly for this: calling C libraries from Elixir NIFs via Zig's `@cImport`.

| Approach | Layers | Verdict |
|---|---|---|
| Zigler → libghostty-vt C API | Elixir → Zig NIF → C API → Zig core | ✅ **Best** |
| Zigler → libghostty-vt Zig API | Elixir → Zig NIF → Zig core | ⚠️ Internal/unstable API |
| Rustler → libghostty-rs | Elixir → Rust NIF → Rust → C API → Zig core | ❌ Unnecessary indirection |

## Architecture

```
Ghostty.Terminal (GenServer) — public API, serializes mutations
  └── Ghostty.Terminal.Nif (Zigler) — thin NIF wrappers, dirty_cpu
        └── libghostty-vt (C API, .dylib/.so)
```

## Implementation Phases

### Phase 1: Core terminal (MVP)
- `new/free/vt_write/resize/reset` NIFs
- `snapshot` with `:plain` and `:vt` formats
- GenServer wrapper
- No callbacks yet

### Phase 2: Effects & input encoding
- PTY write-back callback (`beam.send` from NIF)
- Key encoder NIF + `input_key`
- Mouse encoder NIF + `input_mouse`
- Focus encoding
- Bell/title callbacks as GenServer messages

### Phase 3: Render state
- Expose `RenderState` / row/cell iteration as NIF
- Structured cell data for LiveView/Scenic consumers

### Phase 4: Full PTY integration
- `Ghostty.PTY` module wrapping `forkpty()`
- `Ghostty.Session` combining Terminal + PTY

## Key Design Decisions

1. GenServer wraps NIF resource — all mutations serialized
2. Dirty CPU schedulers — VT parsing can do SIMD work
3. Zigler resource type — terminal + encoders bundled, destructor prevents leaks
4. Binary in, binary out — write accepts iodata, snapshot returns binary
5. Callbacks via beam.send — NIF sends messages to owning process
6. Pin to specific libghostty-vt commit — API still in flux
