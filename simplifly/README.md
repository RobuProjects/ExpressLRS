# SimpliFly ExpressLRS firmware

This branch (`simplifly-config`) is the source of the ExpressLRS firmware that
runs in SimpliFly products:

- **SimpliFly 2G4** — 2.4 GHz TX module (ESP32-S3 + Ebyte E28-2G4M27SX) and receiver

ExpressLRS is licensed under the **GNU General Public License v3.0** (see
[`../LICENSE`](../LICENSE)). This is the complete corresponding source of the
SimpliFly binaries, made available under that licence.

## What is in this fork

The upstream ExpressLRS sources, plus the SimpliFly changes on this branch
(see `git log`), and:

| Path | What |
|---|---|
| `src/platformio.ini` | `SimpliFly_*` build environments |
| `simplifly/build_simplifly_release.sh` | builds and packages the release images |

The board layouts (pins, power levels) are in the SimpliFly targets fork:
https://github.com/RobuProjects/Targets, branch `simplifly-target`. The build
script clones it into `src/hardware` automatically.

## Building

Requirements: Linux or macOS, Python 3, git, and
[PlatformIO](https://platformio.org/install/cli).

```bash
git clone --branch simplifly-config https://github.com/RobuProjects/ExpressLRS.git
cd ExpressLRS
simplifly/build_simplifly_release.sh
```

The images are written to `release/<family>/<environment>/`. Each folder has
the separate parts (`bootloader.bin`, `partitions.bin`, `boot_app0.bin`,
`firmware.bin`) and a merged `<env>_full_flash.bin`.

Releases are tagged `<ExpressLRS base>-SF<SimpliFly version>`, for example
`4.0.0-SF1.0.0` = ExpressLRS 4.0.0 with the SimpliFly 1.0.0 changes.
The build embeds the tag as the firmware version, shown on the device's WiFi
page and in the ELRS Lua / handset ELRS Config, so a user can always see
which ExpressLRS release their radio is based on. Keep tags within 20
characters: ELRS shortens longer versions in the Lua menu.

To build the exact firmware of a shipped release, check out its tag first
(for example `git checkout 4.0.0-SF1.0.0`); the targets repository
carries the same tag.

## Installing your own build

SimpliFly radios do not use secure boot or flash encryption, so any build can
be installed:

- **TX module and receiver over WiFi:** start the device's WiFi mode, connect
  to its access point and upload `firmware.bin` in the web page
  (`*_via_WIFI` environments).
- **Internal TX module through the handset:** ELRS Config → Flash ELRS turns
  the handset into a USB-serial bridge; then flash with
  `pio run -e SimpliFly_2G4_TX_via_UART -t upload` or esptool.
- **Receiver over UART:** connect a USB-serial adapter to the receiver's
  RX/TX pads, hold the boot button while powering it, and flash the
  `*_via_UART` environment.

## Source requests

Questions or source requests: open an issue on this repository.
