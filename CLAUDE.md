# HMG Leafia Plus: notes for Claude

Community tooling for Hyundai/Kia/Genesis **Gen5W** head units (Telechips TCC803x/TCC897x, Android 4.4.2, Dalvik), installed through **NEMESIS** (xwtk/hmg_nemesis, AGPL-3.0). Maintainer: VysseCodes (Ko-fi vyssecodes). Reference car: 2023 Kia EV6 (CVEV.USA, firmware 260507, with HUD).

## Working conventions

- Root commands on a head unit go through NEMESIS: `adb shell "nemesis root -c '...'"`. `nemesis root <uid> -c` runs as another uid (1000 = system).
- Anything that writes to `/system` ships as a NEMESIS package with a stock checksum gate, a backup, and an uninstall that restores the exact stock bytes.
- Test packages on the mock head unit (below) before anyone runs them on a car, and say which cars a change was tested on.
- Commits: describe the change in plain words. Don't rewrite or force-push shared history without the maintainer's OK.
- No links to Claude chats or sessions in commits, PR descriptions or comments: no `Claude-Session:` trailers and no claude.ai session URLs. A `Co-Authored-By: Claude` line is fine.

## Hard rules

- Gen5W is only in navigation trims; non-navigation trims have a "Display Audio" head unit (e.g. Display Audio Gen2V on the Tucson), unsupported and absent from the update catalogue.
- Only each car's newest firmware for its region is supported (US 260507, Canada 260206; each region has its own builds, so `patches/cars` and `compat.json` match the full region, e.g. `CVEV.USA.`). Korea: no Korean car confirmed working (every unit checked had no Wi-Fi hardware), so Korean cars are on no list; reports are still welcome. Don't port older firmware; ask the owner to update the head unit. On a known car with other firmware the installer falls back to basic mode and says to update (`MODE_UPDATE`).

- Never flash MICOM, the bootloader, or modem firmware. Never flash firmware meant for another car.
- No sending our own CAN frames without a separate review. Vehicle commands only through the stock services (BCMManager etc.), and each new one gets its own review.
- Never collect or publish per-car secrets: `/data` contents, the telesecurity partition, certificates/keys, account tokens, VIN, serials, SIM/IMEI/phone numbers. Model-level firmware keys only privately, with consent.
- The repo holds **no full manufacturer apps or libraries**. Allowed: hash-only recipes, delta patch sets (`patches/`), checksums, our own code.

## Layout

| Path | What |
|---|---|
| `tools/lpatch/` | Freestanding static ARM tool (no libc). `check`/`apply` (hash-gated recipes), `delta` (rebuild a file from `.lpd`, only from the exact stock original), `zipadd` (add classes.dex to a stock APK, deterministic), `md5`. Build: `tools/lpatch/build.sh` (also builds `lpatch-host`). Test: `tools/lpatch/test.sh` (fresh build vs committed binary under qemu, plus EV6 manifest rebuild if `~/hmg-private/stock/ev6` exists). |
| `recipes/` | Hash-only native-library patches (libCarPlayCore Wi-Fi sessions, libCarPlayAudio formats, libCarPlayUtils converter). Make with `tools/mkrecipe.py`. |
| `patches/` | Per-car delta sets for the projection apps + `cars` table + `<car>/stock` checksums + `<car>/manifest` expected results. See `patches/README.md`. |
| `packages/wireless-carplay-aa/` | NEMESIS package source: parts `1_projection` (feature flags, hotspot only), `2_tbt` (turn-by-turn), `3_bridge` (CarPlay Bluetooth bridge), `4_audio`. `scripts/build.sh` rebuilds the apps on the unit from stock files before any part runs. |
| `kits/leafia` | The one read-only USB kit, in four sizes set by a `LEAFIA-LEVEL` file (`tools/build-kit.sh [quick|standard|port|full]`): `leafia-kit-quick.zip` (public only), `leafia-kit.zip` (standard: + private logs with the latest crash records, + keys), `leafia-kit-port.zip` (+ stock files), `leafia-kit-full.zip` (+ every crash record). The old fingerprint/support/deep zip names stay as copies of quick/standard/port; `tools/check-downloads.sh [--fix]` checks/rebuilds them all. Writes `LEAFIA/public/` (LEAFIA-REPORT.txt for the compatibility page, summary.txt, our install logs: safe to post) and `LEAFIA/private/` (`logs/`, `stock/` for porting, `keys/` firmware key files: only privately, when a maintainer asks). Packages carry a `BUILD` stamp (commit + date) that the install log and the kit show. |
| `docs/` | GitHub Pages compatibility checker (`docs/data/compat.json`; its `built` lists, the md5 of every file our package installs per car, come from the manifests via `tools/compat-built.py` and CI checks them; status `supported`/`testing`/`in-progress`/`no-wifi`; `product_prefix` may be a list). |
| `tools/build-package.sh` | Builds `dist/HMG_Leafia_Plus_Wireless_CarPlay_AA.zip` from the repo alone. |
| `tools/port.py` | Ports the app changes to a new car from its deep-kit collection (class-by-class compare, auto-merge, reference/framework checks, writes the patch set and `cars` line). |
| `tools/mkmenu.py` | Makes the `5_menu` fix (`HKMC_BtSettings`) for one stock tree and adds its line to `patches/common/optional`; finds the code by structure and refuses unknown shapes. |
| `tools/mkpatches.py`, `tools/mkdelta.py` | Patch-set and single-delta makers (need `pip install --require-hashes -r tools/requirements.txt`). |

## Supported cars (patches/cars)

The Korean sets (`patches/dl3hev`, `patches/neev_kr`) are kept but not in `cars`: no Korean unit has shown Wi-Fi hardware.

| Prefix | Set | Car | Notes |
|---|---|---|---|
| `CVEV.USA.` | ev6 | Kia EV6 US 260507 | reference car |
| `CVEV.CAN.` | ev6_ca | Kia EV6 Canada 260206 | same projection code (every `.odex`, AA lib, CarPlay libs) as US 260507; only the DiPO/GPM APKs differ, so its manifest points at the `ev6/` patches; not yet tested on a real car |
| `NEEV.USA.` / `NEEV23.USA.` | neev | Hyundai Ioniq 5 US 2022/2023 | app code identical to EV6, different APK wrappers |
| `NEEV.CAN.` | neev_ca | Hyundai Ioniq 5 Canada 260206 | apps ported with `port.py`; its AA library (a0bea1c4) differs from the US one, so the library patch was hand-ported (`neev_ca/libautoreceiver_infobank.tbt.lpd`); not yet tested on a real car |

## Gotchas learned the hard way

- The AA library patch (from NEMESIS `projection.tbt`) moves the program headers to 0x1c4000, adds a 9th PT_LOAD with self-contained code, and hooks `sendVersionRequest`+0x12, `RdsType_IsValid` and `NavigationStatusEndpoint::routeMessage`+0xe8 (`b.w` into the new code). The new code reaches the library only through a 5-entry relative table at 0x1c4160 (two `navigationNextTurn*` thunks, two unnamed STLport string helpers, the return address). For a build with a different stock library, re-point that table and the hook; if the build inlined a helper, carry a copy of it in the new segment. `tools/port.py --lib-build` takes the result. Check the method first by rebuilding the US patched library from US stock byte for byte.
- **Deodex with `baksmali x -a 18`**, against the car's own framework dir with the full BOOTCLASSPATH order (core, conscrypt, okhttp, core-junit, bouncycastle, ext, framework, framework2, telephony-common, voip-common, mms-common, android.policy, services, apache-xml, webviewchromium, automotive) plus every other framework odex. `-a 19` silently mis-maps instance fields (KitKat libcore Object fields) and skips classes.
- Abstract Binder stubs implementing in-app interfaces can still deodex with wrong method names; compare against a known-good build before trusting a class.
- System apps: PackageManager only verifies `AndroidManifest.xml`, so stock APK + injected `classes.dex` installs fine; delete the odex and dexopt (`dexopt --preopt apk odex m=y,u=n`).
- Every outgoing SMS on these units needs `android.permission.TMSC_SEND` (Mobis) as well as `SEND_SMS`. Only system-uid callers pass: `nemesis root 1000 -c 'service call isms 5 s16 android s16 <number> i32 -1 s16 <text> i32 0 i32 0'`.
- CarPlay first-connect notice: DiPO looks it up by the phone's Bluetooth address before iAP2 identification, but saved it under the iPhone serial. The bridge build now saves both (`i/e.ev6LastBtId` + `service/aa`).
- CarPlay turn-by-turn maneuver index fix (Isaac Wisdom): `e/u.d(Object)` wrote into a clone of the index array.
- Cluster navigation mode (`responseNaviAliveStatus`, `updateOperationStatus`): on these newer units the car's own navigation shows turn-by-turn without ever sending either (after boot it sends status 0, then only its "ready"/validity message). Stock US/Canada DiPO never runs its cluster start/stop (`i/e.jw()` needs stepofspec >= 999; the turn-by-turn build sets 0, so `DipoService.cn()` runs them on every navigation-owner change). Once phone guidance sent alive + status 1, nothing sent at the end (0, 1, 2 or nothing) brought the cluster back: it spun until the car's navigation re-sent "ready" on its next route (US and Canadian EV6). Status 2 = no map card on SD-card models (Canadian EV6: "Insert SD card to use navigation"; the US EV6 is eMMC). DiPO and GPM now never send either, only turn data (`~/hmg-private/tools/srcfix/apply4.py` + `apply5.py`).
- Speed limit, cameras and traps while a phone guides: the turn-by-turn build muted the car navigation's trap frame (`updateTBTTrapInfoNew`: speed-limit digits, camera types, curve/merge/zone warnings) and HUD camera distance (`updateNaviWarnDist`) along with the turn display, and stock GPM's `updateTBTTrapInfo()` sent the 17-int clear after every maneuver (wipes the speed-limit byte). Under CarPlay the cluster kept a stale sign; under Android Auto it was wiped. Phones carry none of this data. Now the navigation app's mute (`e/a.sendClusterData`, `message/a.d([BI)`) lets trap/camera codes 1, 4, 0x4B, 0x4F through and GPM's clear does nothing (`~/hmg-private/tools/srcfix/apply6.py`). Driver-assist map data (`updateV2*`/`updateV23*`), `updateSCC_HU_Navi_P` and `updateISLAAdd` were never muted.
- CarPlay turn-by-turn source switch: DiPO keeps each display's guidance state (`e/c`, filled field by field from partial RouteGuidanceUpdates) and the maneuver/lane maps, so after Apple Maps -> Waze the old app's leftovers mixed with the new one. `e/u.leafiaSourceCheck` (called from `c(Object)`) remembers SourceName (item 0x13, string) and, when it changes, runs the disconnect clear (`nT()` + `sendHudBlank()`) before the new update is applied; logs `Leafia: route guidance source changed`. Then `e/LeafiaRgRestart` (own thread; a binder call into the iAP2 service from its own callback could deadlock) runs `b.leafiaRestartRouteGuidance()`: iAP2 Stop then StartRouteGuidanceUpdate for `RouteGuidanceComponent0`, so the phone sends its whole current state at once; the cluster's turn-by-turn mode (`nR`/`nS`) is left alone. `u.leafiaOwner` is set where `b` creates `u`. Off-car: the edit scripts are in `~/hmg-private/tools/srcfix` (`apply.py`, `apply2.py`), run on the original builds. Not verified by Dalvik's verifier off-car (the unit's binaries don't run under qemu-user here).
- DiPO wireless reconnect crash (stock bug): an iAP2 drop clears the phone's iAP2 Bluetooth address (`e/b.aw`, read by `K()`), and a wireless session can restart before iAP2 is back; `service/q.a` (onSessionDetails) called `K().toUpperCase()` unchecked. The bridge build now falls back to the session's own id, or keeps the stored address. Every other `K()` caller already checks for null. Same method on all four sets (K5/Korean Ioniq 5 only rename DipoService accessors).
- The bridge's `EV6CPWL` log lines may not show in logcat even while it runs; don't read their absence as the bridge being dead.
- No `tail` on the unit; use shell loops. Remount only through `nemesis remount rw|ro`: toolbox `mount -o remount` is refused even as root (NEMESIS before 1.15 could also EPERM until reboot; 1.15 fixed it and puts a `mount` wrapper first on hook PATH). Featurexml region comes from `ro.mobis.targetdir`.
- Korean K5 Hybrid (TCC897x) has no Wi-Fi: the kernel sets up only SDHC0/SDHC2, the driver raises WIFI_REG_ON and gives up (`failed to power up DHD generic adapter, max retry reached`). US TCC803x units show `mmc1: new ... SDIO card` and `Firmware up`. The feature file `com.hkmc.software.wifi.module.xml` is present either way; `wifi_hw` in `common.sh` uses the driver's result instead, and preinstall refuses on `no`.
- With the wireless CarPlay/AA features on, `HKMC_BtSettings` (`BluetoothSettings`, pswitch on the menu id) sends Settings > Phone Projection to `wireless.WPPSettingsActivity` (no split-screen option; its device list only holds phones paired by `WirelessPhoneProjectionService`, never ours). Stock US/CA goes to Device Connections. Part `5_menu` (optional, `patches/common/optional`) keeps US/CA on Device Connections. lpatch `MAXOUT` is 12 MB for this 5.6 MB APK.
- Opt-in Wi-Fi client: an empty `LEAFIA-WIFI-CLIENT` next to our `NEMESIS.data` makes part 1 add `android.hardware.wifi.xml` and set `persist.wifi.state=3` (Hyundai's client + wireless mode), as the old full wireless setup did. The kernel reports `op_mode=0x0005` (client + Wi-Fi Direct) and `rsdb_mode` unsupported, so client and hotspot must share one channel; untested together. Mock: `MOCK_WIFI_CLIENT=1`.
- First start after an install was slow because our APKs carry `classes.dex`: for such an APK the boot check (`dvmDexCacheStatus`) looks only in `/data/dalvik-cache`, never at the odex beside it, so the package manager re-optimised every changed app at boot (entries dated with the boot clock, 2015-01-01 04:30). Each part now copies its odex into `/data/dalvik-cache/system@app@<App>.apk@classes.dex` after `wipe_dalvik` (`prefill_dalvik`); confirmed on a US EV6 (entries keep the install time). On these units `BOOTCLASSPATH` is in `/init.environ.rc`, not `/init.rc`.
- With Android up, the install/uninstall swapped files under running apps (DiPO/iAP2 crash loop "is package not installed?", SIGBUS). `apps_hold`/`apps_release` (`scripts/common.sh`) `pm disable` the five apps whose files change (GPM, DiPO, iAP2, navigation, BtSettings) for the swap and enable them on every way out; the list is in `/data/nemesis/wireless.carplay.aa.stopped` until then. An uninstall runs the previously installed package's scripts.
- A USB drive in the port makes GPM start a wired Android Auto attempt (`StartReceiver: USB_DEVICE_ATTACHED`, `isStartConnection, mode: 1`), and `GalConnectionManager` (stock) can stay in "Already AA Starting mode" so wireless attempts are refused ("Already AA connecting, not start connect!") until it times out or the head unit restarts. Switching the car off and on doesn't restart the head unit (it stays on until the driver's door opens or a timeout). The turn-by-turn GPM build (`~/hmg-private/tools/srcfix/apply7.py`) now skips the wired start when every interface of the attached device is mass storage (8) or hub (9) (`StartReceiver.leafiaNotPhone`, logs `Leafia: USB drive or hub, not starting wired Android Auto`); phones and devices with no interfaces start as before.
- Toast: `am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "..." --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true`.

## Testing without a car

Mock head unit: `tools/mock/install-test.sh <zip> <ro.build.product> <region dir> <stock system dir>` installs and uninstalls the package against a copy of a stock `/system` (a kit's `LEAFIA/private/stock/` works), stubbing `getprop`/`setprop`/`am`/`settings`/`md5`/`chown`/`dexopt` and running `lpatch` under `qemu-arm-static`; it passes only if uninstall leaves `/system` byte-identical. `tools/mock/matrix.sh <zip>` runs every car in the git-ignored `tools/mock/cars.local`. Use `MOCK_SH=mksh` (the unit's shell lacks `printf`, `tail`, ...), `MOCK_NEMESIS=1.15`, `MOCK_ANDROID_DOWN=1` (NEMESIS 1.15 installs without asking while Android is down) and `MOCK_USB_DESCRIPTOR=1`. Stock trees and full builds can't live in this repo; contributors keep their own copies privately.

## Kia Connect (research summary, read-only)

Telematics lives in `HKMC_TAppService` (system uid). Remote commands arrive over MQTT (`mqtt_mosquitto`, a libmosquitto binder wrapper; MQTT 5; topics and host provisioned via the service hub) or a wake-up SMS that makes the unit call back over HTTPS. Commands execute through `BCMManager`/`HEVManager` -> automotive-service -> `micomd` (`/dev/ttyTCC2`) -> MICOM -> CAN. Modem: Qualcomm over USB (`/dev/ttyACM0` AT, `/dev/qcqmi0` data), Verizon (US). Status is reported as VSS paths. Planned direction: a read-only Home Assistant status bridge first, then wake-by-own-SMS testing, then reviewed commands one at a time through the stock services.

## Open threads

- Real-car tests pending: on-unit build package (all cars), CarPlay notice fix, DiPO reconnect null check (all four sets).
- Reassemble deodexed apps with `smali a -j 1 --api 18`: with more threads smali writes a different (equivalent) dex each run.
- Also seen on the US Ioniq 5: Iap2ServerApp `InitSupportLanguage` index out of range on iAP2 disconnect; `/system` left mounted rw after install (`nemesis remount ro` got EBUSY and the parts ignore it).
- NEMESIS 1.15 (2026-10-21): checked against its zip/INI code and hook environment; its `carplay.session` package conflicts with ours (in `LEGACY`).
- Modem test plan for a volunteer (read-only identity/APN/SMS-in/wake tests).
- Possible: install guide on the site; changelog describing fixes in plain words.
