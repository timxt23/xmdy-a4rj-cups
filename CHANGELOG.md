# Changelog

## 1.0.0 — 2026-09-28

First release.

- CUPS raster filter `rastertoxmdy` for XMDY / HZTZ A4RJ (universal binary, macOS 11+).
- PPD with A4/A5/B5/Letter/Legal, density, threshold, halftone, negative, mirror, paper type,
  blank trimming, horizontal offset and feed options; Russian localization.
- Installer package that creates a queue automatically when the printer is connected.
- The vendor end-of-job command `10 FF F1 45` is not sent, so the next USB job no longer fails.
