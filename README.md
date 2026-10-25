# HMG Leafia Plus

[![Sponsor on GitHub](https://img.shields.io/badge/Sponsor_on_GitHub-%E2%9D%A4-bf3989?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/VysseCodes)
[![Buy me a coffee on Ko-fi](https://img.shields.io/badge/Buy_me_a_coffee-Ko--fi-FF5E5B?style=for-the-badge&logo=kofi&logoColor=white)](https://ko-fi.com/vyssecodes)

> **HMG Leafia Plus is free.** If it saved you a dealer visit or made your drives nicer, please consider chipping in through [GitHub Sponsors](https://github.com/sponsors/VysseCodes) or [Ko-fi](https://ko-fi.com/vyssecodes). It keeps the testing and new-car ports going.

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
| Projection settings menu | On US/Canada units, Settings > Phone Projection keeps opening Device Connections (CarPlay split screen, connected phones), as on stock firmware; applied only where the Bluetooth settings app is the stock one the fix was made for | `patches/common/optional` (`HKMC_BtSettings`) |
| CarPlay Bluetooth bridge | Starts wireless CarPlay over Bluetooth/iAP2 | Rebuilt on the unit from its stock apps (`patches/<car>`) |
| Turn-by-turn | Projection navigation on the cluster and HUD | Rebuilt on the unit from its stock apps (`patches/<car>`). Uses only the standard cluster calls, so cars without a HUD are fine. The installer refuses if the firmware lacks any call it needs. |

Cars without a patch set yet get **basic mode**: only the wireless projection part, which gives wireless Android Auto on any Gen5W unit with a Wi-Fi module. The installer also saves a report so a full build can be made for that car.

## Install

1. Install [NEMESIS](https://github.com/xwtk/hmg_nemesis) **1.15 or newer** on the head unit.
2. Check your car on the [compatibility page](https://vyssecodes.github.io/HMG-Leafia-Plus/) with the Leafia kit.
3. Download **HMG_Leafia_Plus_Wireless_CarPlay_AA-<version>.zip** from the [latest release](../../releases/latest) (or build it yourself with `tools/build-package.sh`). Each release lists SHA256 checksums.
4. Unzip it onto the root of an empty exFAT or FAT32 USB drive (`NEMESIS.data` and `packages/`).
5. Car on, plug in the drive and confirm the install. The head unit restarts when it's done; remove the drive. The installer renames `NEMESIS.data` to `NEMESIS.data.installed` so it can't run again by accident.
6. **Uninstall** any time from NEMESIS Manager (Packages → Uninstall), then restart: every file goes back to stock.

**Optional: Wi-Fi client (testing).** By default the head unit's Wi-Fi only runs the hotspot that wireless CarPlay/Android Auto use. To also get the Wi-Fi menu and join a network (for example to reach ADB over your home Wi-Fi), put an empty file named `LEAFIA-WIFI-CLIENT` next to `NEMESIS.data` on the install drive. These units have one Wi-Fi radio, so whether a home network and wireless projection work at the same time is still being tested. Uninstalling turns it off again.

Something wrong? Open an issue with the [problem form](../../issues/new?template=problem.yml); it walks you through the Leafia kit.

## Packages

- **`packages/wireless-carplay-aa`:** the Wireless CarPlay/AA NEMESIS package source. Nothing modified is shipped: native libraries are patched on the head unit with `lpatch` recipes, and the projection apps are rebuilt on the unit from its own stock files with the patch sets in `patches/`.

## Supported head units

See the [compatibility page](https://vyssecodes.github.io/HMG-Leafia-Plus/). The data lives in `docs/data/compat.json` (cars with a build) and `docs/data/wanted.json` (Gen5W cars we'd like to add).

**Newest firmware only.** We support each car's newest head unit software for its region: currently **260507** in the US and **260206** in Canada. On older firmware the package installs wireless Android Auto only (basic mode) and asks you to update; use the free Hyundai, Kia or Genesis Navigation Updater, then install again.

**Navigation trims only.** Gen5W is the head unit in trims with built-in navigation. Trims without navigation have a different head unit ("Display Audio", for example "Display Audio Gen2V" on the Tucson) that NEMESIS and this package don't support.

**Korea:** reports from Korean head units are welcome, but we have yet to confirm a single working Korean car. Every Korean unit checked so far has had no Wi-Fi hardware, which wireless CarPlay and Android Auto need.

## The Leafia kit (run from a USB drive through NEMESIS)

One read-only kit (`kits/leafia`) covers checking a car, reporting a problem and porting to a new car. It comes in four sizes, built from the same source; each download carries a `LEAFIA-LEVEL` file that sets how much it collects:

| Download | Collects | Use it for |
|---|---|---|
| [leafia-kit-quick.zip](https://vyssecodes.github.io/HMG-Leafia-Plus/downloads/leafia-kit-quick.zip) | `public/` only | checking a car (seconds) |
| [leafia-kit.zip](https://vyssecodes.github.io/HMG-Leafia-Plus/downloads/leafia-kit.zip) | + `private/logs` (latest crash records) and `private/keys` | reporting a problem |
| [leafia-kit-port.zip](https://vyssecodes.github.io/HMG-Leafia-Plus/downloads/leafia-kit-port.zip) | + `private/stock` (~90 MB) | adding a new car |
| [leafia-kit-full.zip](https://vyssecodes.github.io/HMG-Leafia-Plus/downloads/leafia-kit-full.zip) | + every crash record | deep debugging, when asked |

It writes `LEAFIA/` on the drive:

| Folder | Contents | Share |
|---|---|---|
| `public/` | `LEAFIA-REPORT.txt` (firmware ids, checksums, patch checks: drop it on the compatibility page), `summary.txt` (NEMESIS and package state, hotspot, crash record names), our install logs | Safe to post on an issue |
| `private/logs/` | Android and kernel logs, NEMESIS logs, crash dumps, network state; can include phone names or Bluetooth addresses | **Privately, only when asked** |
| `private/stock/` | Stock framework, CarPlay/projection apps and libraries (Hyundai/Kia files), used to port the package | **Privately, only when asked** |
| `private/keys/` | Firmware key files | **Privately, only when asked; never posted** |

### Data policy

- **Public** (issues, this repo): the kit's `public/` folder, recipes, checksums, compatibility data.
- **Private only** (never committed here): the kit's `private/` folder (logs, stock firmware files, firmware key files) and full modified app builds. The repo holds only patch sets that rebuild them from a unit's own stock files.
- **Never collected:** anything under `/data` except NEMESIS's own folder, crash logs and the hotspot's address leases — so no accounts, paired phones or Wi-Fi passwords — the vehicle security partition (modem and connected-service certificates), the VIN and serial numbers.

## Contributing

Have an idea for a feature? [Suggest it here](../../issues/new?template=feature.yml), or add a 👍 to the [ideas already suggested](../../issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement).

Reports from new cars, real-car tests and code are all welcome: see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, building, testing on the mock head unit, adding a car, and the project rules. Security issues: [SECURITY.md](SECURITY.md).

## Credits and licences

- HMG Leafia Plus is GPL-3.0 (see `LICENSE`).
- It runs through [NEMESIS](https://github.com/xwtk/hmg_nemesis) by xwtk, which is AGPL-3.0. Parts derived from NEMESIS packages are listed in `NOTICE.md` and stay under their original licence.
- Not affiliated with Hyundai, Kia, Genesis, Apple or Google. Modifying your head unit is at your own risk.
