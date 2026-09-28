# Changelog

## 1.1.0 — 2026-09-28

Bluetooth printing.

- New queue `XMDY_A4_BT` and PPD "XMDY A4RJ Bluetooth": the filter sends one raw-DEFLATE
  block per page, the format the printer expects over Bluetooth (see PROTOCOL.md).
- "XMDY Bluetooth" (`xmdy-btd`): bridge on 127.0.0.1:9101, started by a launchd agent in the
  user's session. It is a background app because macOS grants Bluetooth access (TCC) only to
  user-approved apps. It opens RFCOMM directly (the `/dev/cu.*` port does not reconnect after the
  printer sleeps), waits for the printer to confirm each page, and retries while the printer is off.
  Retries back off from 10 s to 2 minutes; waiting for the printer is event-driven; no process
  runs between jobs.
- `xmdy-btpair`: pairs the printer, which System Settings cannot do (no Connect button).
- `setup-queue.sh --bluetooth` saves the printer address, loads the agent and triggers the
  Bluetooth permission prompt. The installer does this when the printer is already paired.
  Uninstall removes the bridge too.
- `xmdy_dump.py` decodes Bluetooth streams.

## 1.0.0 — 2026-09-28

First release.

- CUPS raster filter `rastertoxmdy` for XMDY / HZTZ A4RJ (universal binary, macOS 11+).
- PPD with A4/A5/B5/Letter/Legal, density, threshold, halftone, negative, mirror, paper type,
  blank trimming, horizontal offset and feed options; Russian localization.
- Installer package that creates a queue automatically when the printer is connected.
- The vendor end-of-job command `10 FF F1 45` is not sent, so the next USB job no longer fails.
