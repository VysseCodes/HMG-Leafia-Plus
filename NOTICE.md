# Notices

## NEMESIS

HMG Leafia Plus packages install and run through **NEMESIS** by xwtk:
https://github.com/xwtk/hmg_nemesis. NEMESIS is licensed under the GNU Affero General Public License v3.0.

The Wireless CarPlay/AA package builds on these NEMESIS community packages. Their scripts and builds remain under the AGPL-3.0:

- **Enable Wireless Features** (`wireless.projection`). The HMG Leafia Plus version is a slimmed copy of its scripts: hotspot-only, plus a fix that finds the region folder via `ro.mobis.targetdir`.
- **Turn-by-Turn Guidance for Phone Projection** (`projection.tbt`). Used as-is; its app builds are the base for the CarPlay bridge builds.

## Original HMG Leafia Plus work (GPL-3.0)

`lpatch`, the recipes and recipe tooling, the Leafia kit, the compatibility site, the CarPlay Bluetooth bridge, the CarPlay Wi-Fi/audio patches and the `libleafia.so` audio converter.

## Community contributions

- **CarPlay turn-by-turn maneuver fix** (DiPO route-guidance parser wrote maneuver indexes into a copy of the index array, so every maneuver read as -1 and CarPlay guidance never reached the cluster). Contributed by [Isaac Wisdom](https://github.com/isaacwisdom); applied to the EV6, Ioniq 5 and K5 builds.

## Thanks

- [W-Floyd](https://github.com/W-Floyd), for their help with this project.

## Third-party code used at runtime

The audio converter loads the head unit's own `libstagefright_soft_aacdec.so` (Fraunhofer FDK AAC) and `libopus.so` at runtime. Nothing from them is bundled.
