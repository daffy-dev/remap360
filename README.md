<p align="center"><img src="assets/wordmark-dark.png" width="420" alt="Remap360"></p>

# Remap360

A native macOS visual keymap editor for the **Kinesis Advantage360 Pro** (ZMK firmware).
It edits `config/adv360.keymap` in your Adv360-Pro-ZMK checkout, then builds firmware locally with Docker and flashes it over USB.

## Build & run

```sh
scripts/bundle.sh            # builds build/Remap360.app
scripts/bundle.sh --install  # also copies it to /Applications
swift test                   # keymap parser tests
```

Requires macOS 15+, Xcode 16+ and Docker Desktop (for building firmware).

## How it works

- **Live mode (default)**: plug the left half in with USB and Remap360 connects over ZMK Studio's protocol. The first time, unlock it on the keyboard (hold Mod, press Esc). Every change applies instantly; **Keep Changes** stores them on the keyboard, **Revert** goes back to the last kept layout. Live mode can use any behavior already in the firmware, but can't add new macros.
- **Config file mode**: for new macros, custom behaviors and firmware updates.

- **Editing**: only the `keymap { … }` node is rewritten on save; everything else in the file is preserved. A backup of the previous file goes to `~/Library/Application Support/Remap360/Backups` on every save.
- **Layers**: add, rename, duplicate, reorder and delete. Layer keys (`&mo`, `&lt`, `&tog`, `&to`, `&sl`) are renumbered automatically.
- **Build**: the same Dockerfile and `build.sh` as the official `make left` / `make`. Firmware lands in `firmware/`.
- **Flash**: Remap360 waits for the UF2 bootloader drive and copies the firmware to it. It reads your keymap to show which keys put each half into flash mode.

## Shortcuts

| | |
|---|---|
| Arrows | move between keys |
| Delete | make key pass-through |
| ⌘C / ⌘V | copy / paste a key |
| Tab, ⌘1…⌘9 | switch layers |
| ⌘S | save |
| ⌘B | build & flash |
| ⌘Z / ⇧⌘Z | undo / redo |
