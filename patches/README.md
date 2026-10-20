# Patch sets

One folder per car, plus `common/`. The head unit rebuilds the modified projection apps from its own stock files with these (see `packages/wireless-carplay-aa/scripts/build.sh`), so no modified app is shipped.

| Folder | Car | Firmware |
|---|---|---|
| `ev6/` | Kia EV6 (`CVEV.*`) | 260507 |
| `neev/` | Hyundai Ioniq 5 (`NEEV.*`) | 260507 |
| `dl3hev/` | Kia K5 Hybrid, Korea (`DL3HEV.KOR.*`) | 260902 |
| `common/` | `libautoreceiver_infobank.so`, same on every supported car | |

## Files

- `<App>.tbt.lpd`: rebuilds the turn-by-turn version of the app's code from the stock `<App>.odex`.
- `<App>.bridge.lpd`: rebuilds the CarPlay-bridge version (turn-by-turn included).
- `manifest`: one line per output: `<part> <app|file> <name> <patch> <md5 of the result>`.

An `.lpd` holds the md5 of the exact stock file it needs and of the result. `lpatch delta` writes nothing unless both match.

## Making a set

Needs the car's stock files (`app/<name>.apk`, `app/<name>.odex`, `lib/libautoreceiver_infobank.so`), the modified builds in the `2_tbt/<files>` and `3_bridge/<files>` layout, the host `lpatch` (`tools/lpatch/build.sh`) and `pip install bsdiff4`:

```
tools/mkpatches.py <ev6|neev|dl3hev> <stock dir> <builds dir> patches
```

The installer's stock checksums (`comp/2_tbt`) and expected app checksums (`comp/3_bridge`) must match the new set.
