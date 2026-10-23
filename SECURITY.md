# Security

HMG Leafia Plus runs as root on car head units, so we take security reports seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through GitHub:
**Security → Report a vulnerability** on this repository
([direct link](https://github.com/VysseCodes/HMG-Leafia-Plus/security/advisories/new)).

Include what's affected (package part, kit, tool or workflow), how to reproduce it, and which cars or
firmware you saw it on. We'll acknowledge it within a few days and agree a disclosure date with you once a
fix is ready.

Vulnerabilities in NEMESIS itself belong to [xwtk/hmg_nemesis](https://github.com/xwtk/hmg_nemesis).

## What counts

- Anything that lets the package or a kit write to a car without its stock-checksum checks, or leaves a
  car unable to return to stock on uninstall.
- A kit collecting more than it says: its `public` output must stay safe to post (see the data policy in the
  [README](README.md#data-policy)).
- Supply-chain issues: tampered binaries, CI workflows, or dependencies.

## How the project protects users

- Nothing modified from Hyundai/Kia is shipped: the projection apps are rebuilt on the head unit from its
  own stock files, and only when those match the expected checksums byte for byte.
- Every write to `/system` keeps a backup, and uninstall restores the exact stock bytes.
- The shipped binaries are checked by CI: `lpatch` is built and tested from `tools/lpatch/lpatch.c`,
  `libev6aac.so` must rebuild byte for byte from `src/ev6aac/`, and the kits on the website must match
  `kits/`.
- CI actions and Python packages are pinned to exact commits and hashes; workflow runs from outside
  contributors need maintainer approval, and pull-request builds are never published as downloads.
- No vehicle commands are sent except through the stock services, each with its own review; no raw CAN.

## Sensitive data

Never post firmware key files, deep-kit output, a support kit's `private` folder, VINs, serial numbers or
phone details in an issue. Maintainers will ask for them privately when they're needed.
