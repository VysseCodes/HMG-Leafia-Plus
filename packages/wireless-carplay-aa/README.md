# Wireless CarPlay/AA package (`wireless.carplay.aa`)

NEMESIS package source. It installs four parts in order, with one reboot at the end:

| Part | Folder | What it changes |
|---|---|---|
| Wireless projection | `comp/1_projection` | Wireless feature flags, region folder from `ro.mobis.targetdir` (hotspot only) |
| Turn-by-turn | `comp/2_tbt` | Projection apps (NEMESIS community package). Refuses unless the firmware has every cluster call it uses. |
| CarPlay bridge | `comp/3_bridge` | Projection apps + `libCarPlayCore` via lpatch (`carplay-core-wifi`) |
| CarPlay audio | `comp/4_audio` | `libCarPlayAudio` / `libCarPlayUtils` via lpatch, plus `libev6aac.so` where needed |

Nothing modified is shipped. The head unit patches its own files:

- **Native libraries:** `lpatch` patches them in place from the hash-only recipes in `/recipes`.
- **Projection apps** (`HKMC_DiPO`, `HKMC_GPM`, `HKMC_Navi_ExSL`, `Iap2ServerApp`) and `libautoreceiver_infobank.so`: `scripts/build.sh` rebuilds them from the unit's stock files with the patch sets in `/patches`, before any part installs. For each app, `lpatch delta` rebuilds the modified code from the stock `.odex` (only if that `.odex` is the exact expected original), and `lpatch zipadd` adds it to the stock APK. Each result must match the md5 in `patches/<car>/manifest`. If the unit's stock files are not the expected ones, nothing is written and the unknown-unit report runs.

It also runs one small service, `hotspot-route` (`svc/hotspot-route.sh`, writes nothing to `/system`). Turning on ADB over network (for example NEMESIS's Enable ADB package) makes the stock firmware give the internal `eth0` link `192.168.0.123/24`, in the hotspot's range, and its route wins over the hotspot's: phones never get an address and wireless projection drops after about a minute. The service removes that one `eth0` route whenever it shows up, so ADB and wireless projection both work. Uninstalling puts the route back.

## Building the zip

```
tools/build-package.sh
```

Everything comes from this repository. To add a car or change an app, see `patches/README.md`.
