# HMG Leafia Plus

Community tooling to improve Hyundai, Kia and Genesis **Gen5W** head units through [NEMESIS](https://github.com/xwtk/hmg_nemesis) packages. The first goal is wireless CarPlay and Android Auto on as many head units as possible.

**Compatibility checker:** https://vyssecodes.github.io/HMG-Leafia-Plus/

## How it works

Firmware differs between models, regions and versions, so whole-file checksums rarely match across cars. HMG Leafia Plus checks **only the bytes it changes**:

- **Recipes** (`recipes/*.recipe`) list the new bytes for each patch together with hashes of the region around it. They contain no bytes from Kia/Hyundai files.
- **`lpatch`** (`tools/lpatch/`) is a small static ARM tool that runs on the head unit. It patches only when every checked region matches its stock hash. A recipe therefore works on any firmware whose patched spots are identical, even when the rest of the file differs.
- **Native support is recognised:** some firmware already has a feature built in. For example, Korea's V039 build already accepts Wi-Fi CarPlay sessions and ships real AAC/Opus converters. Recipes record these files as `native`, so nothing is patched there.

| Part | What it does | How it is applied |
|---|---|---|
| Wireless projection | Enables the wireless CarPlay/AA feature flags for the unit's own region folder. Hotspot only: no Wi-Fi client, no extra Wi-Fi menu. | Feature files + config edits, all restored on uninstall |
| CarPlay Wi-Fi sessions | Lets `libCarPlayCore` accept Wi-Fi sessions | `carplay-core-wifi.recipe` |
| CarPlay wireless audio | Offers AAC (music) and Opus (Siri, calls, mic) over Wi-Fi, decoded with the unit's own codecs | `carplay-audio-formats.recipe`, `carplay-utils-converter.recipe` + `libev6aac.so` |
| CarPlay Bluetooth bridge | Starts wireless CarPlay over Bluetooth/iAP2 | Rebuilt on the unit from its stock apps (`patches/<car>`) |
| Turn-by-turn | Projection navigation on the cluster and HUD | Rebuilt on the unit from its stock apps (`patches/<car>`). Uses only the standard cluster calls, so cars without a HUD are fine. The installer refuses if the firmware lacks any call it needs. |

## Packages

- **`packages/wireless-carplay-aa`:** the Wireless CarPlay/AA NEMESIS package source. Nothing modified is shipped: native libraries are patched on the head unit with `lpatch` recipes, and the projection apps are rebuilt on the unit from its own stock files with the patch sets in `patches/`.

## Supported head units

See the [compatibility page](https://vyssecodes.github.io/HMG-Leafia-Plus/). The data lives in `docs/data/compat.json`.

## Kits (run from a USB drive through NEMESIS)

| Kit | Use | Output |
|---|---|---|
| `kits/fingerprint` | Anyone: check compatibility | `LEAFIA-REPORT.txt`. No personal data and no OEM code, safe to post. |
| `kits/deep` | Only when a maintainer asks, to port a new head unit | `NEMESIS-deep/`. `share/` holds stock system files; `PRIVATE/` holds firmware key files. **Send privately.** |

Both kits are read-only.

### Data policy

- **Public** (issues, this repo): fingerprint reports, recipes, checksums, compatibility data.
- **Private only** (never committed here): stock firmware files, firmware key files from deep collections, and full modified app builds. The repo holds only patch sets that rebuild them from a unit's own stock files.
- **Never collected:** anything under `/data` (accounts, paired phones, Wi-Fi passwords), the vehicle security partition (modem and connected-service certificates), the VIN and serial numbers.

## Building

```
tools/lpatch/build.sh
```

```
tools/build-kit.sh docs/downloads/leafia-fingerprint-kit.zip
```

```
tools/build-package.sh
```

Make a recipe from a stock/patched pair:

```
tools/mkrecipe.py <id> /system/lib/libX.so stock.so patched.so --desc "what it does"
```

## Support the project

HMG Leafia Plus is free. If it saved you a dealer visit or made your drives nicer, you can chip in through [GitHub Sponsors](https://github.com/sponsors/VysseCodes) or [Ko-fi](https://ko-fi.com/vyssecodes).

## Credits and licences

- HMG Leafia Plus is GPL-3.0 (see `LICENSE`).
- It runs through [NEMESIS](https://github.com/xwtk/hmg_nemesis) by xwtk, which is AGPL-3.0. Parts derived from NEMESIS packages are listed in `NOTICE.md` and stay under their original licence.
- Not affiliated with Hyundai, Kia, Genesis, Apple or Google. Modifying your head unit is at your own risk.
