# XMDY A4RJ CUPS driver for macOS

Open-source CUPS driver for **XMDY / HZTZ A4RJ** portable A4 thermal printers
(sold under several brand names; vendor driver family "GD-88"). Print from any macOS app
with ⌘P over **USB or Bluetooth**.

[Русская версия](README.ru.md) · [Protocol notes](PROTOCOL.md)

- Native universal binary (Apple Silicon and Intel). No Rosetta needed, unlike the vendor driver.
- Real print density control. The vendor driver shows the option but ignores it.
- Fixes the vendor driver bug that stops the queue after every job ("Unable to send data to printer").
- Bluetooth printing, which the vendor has no macOS support for. Includes a pairing tool, because
  System Settings shows no Connect button for this printer.
- Photo mode (error diffusion), negative and mirror printing, blank-space trimming for rolls,
  marked/folded paper, configurable feeds.
- Russian UI strings in the print dialog.

## Supported printers

| Printer | USB ID | 1284 ID | Status |
|---|---|---|---|
| XMDY A4RJ | `0FE6:811E` | `MFG:XMDY;MDL:A4RJ` | tested, macOS 27, Apple Silicon |

Other GD-88 family printers (XMDY GD-88, HZTZ A4DY, …) probably use the same protocol.
Reports are welcome.

## Install

1. Download `XMDY-A4RJ-<version>.pkg` from [Releases](../../releases) or build it (see below).
2. The package is **not signed**, so macOS blocks it the first time. Open it, click **Done**, then go to
   **System Settings → Privacy & Security** and click **Open Anyway**.
3. Connect the printer over USB and turn it on before installing. The installer then creates a queue
   named **XMDY_A4**.
   If the printer was not connected, add it later in **System Settings → Printers & Scanners** (the driver
   "XMDY A4RJ" is selected automatically) or run:

   ```sh
   sudo /Library/Printers/XMDY-A4/setup-queue.sh
   ```

Installed files:

```
/Library/Printers/XMDY-A4/Filter/rastertoxmdy          CUPS filter
/Library/Printers/XMDY-A4/XMDY Bluetooth.app          Bluetooth bridge (background app, no window)
/Library/Printers/XMDY-A4/xmdy-btpair                  Bluetooth pairing tool
/Library/Printers/XMDY-A4/setup-queue.sh, uninstall.sh
/Library/Printers/PPDs/Contents/Resources/XMDY A4RJ.ppd
/Library/Printers/PPDs/Contents/Resources/XMDY A4RJ Bluetooth.ppd
/Library/LaunchAgents/io.github.timxt23.xmdy-btd.plist
```

## Bluetooth

1. Turn the printer on and disconnect it from phones. The printer accepts one Bluetooth
   connection at a time.
2. Pair it as your user, without sudo. macOS may ask to allow Bluetooth access for Terminal.

   ```sh
   /Library/Printers/XMDY-A4/xmdy-btpair
   ```

   System Settings lists the printer under Nearby Devices but offers no Connect button, which is
   why this tool exists.
3. Create the queue **XMDY_A4_BT**:

   ```sh
   sudo /Library/Printers/XMDY-A4/setup-queue.sh --bluetooth
   ```

   macOS then asks whether **"XMDY Bluetooth"** may use Bluetooth. Click **Allow**. You can
   check or change this later in System Settings → Privacy & Security → Bluetooth.

You never need to connect the printer by hand. The queue prints to a local bridge
(`socket://127.0.0.1:9101`, only reachable from this Mac). The bridge is the background app
"XMDY Bluetooth", started on demand by a launchd agent in your session. It runs as an app
because macOS grants Bluetooth access only to apps the user has approved, never to system
services. For each job, the bridge opens the Bluetooth link, waits until the printer confirms
every page, then closes the link. If the
printer is off, the job waits up to 30 minutes and prints when the printer comes back. Retries
back off from 10 s to 2 minutes to spare the battery. When no job is printing, no bridge
process runs at all.
A page takes about 26 s, the same as with the vendor's phone app.

## Uninstall

```sh
sudo /Library/Printers/XMDY-A4/uninstall.sh
```

This removes every queue that uses the driver, the Bluetooth bridge, all installed files and the
package receipt. The Bluetooth pairing stays; remove it in System Settings → Bluetooth.

## Print options

In the print dialog, open the printer options section. On the command line use `lp -o`,
and `lpoptions -p XMDY_A4 -o …` to change queue defaults.

| Option | Values | Default |
|---|---|---|
| `XmdyDensity` Print Density | `0` Light, `1` Normal, `2` Dark, `3` Extra Dark | `1` |
| `XmdyThreshold` Black Threshold | `96` `128` `160` `192` (higher = bolder) | `128` |
| `XmdyDither` Halftone | `Threshold` text and graphics, `Diffusion` photo | `Threshold` |
| `XmdyNegative` / `XmdyMirror` | `True` `False` | `False` |
| `XmdyMediaType` Paper Type | `Continuous`, `Marks` (folded, with marks), `Tattoo` | `Continuous` |
| `XmdyTrim` Skip blank space at page end | `True` `False` | `False` |
| `XmdyOffsetX` Horizontal offset, mm | `-5` `-3` `-1` `0` `1` `3` `5` | `0` |
| `XmdyFeedBefore` / `XmdyPageFeed` / `XmdyFeedAfter`, mm | see PPD | `0` / `0` / `12` |
| `PageSize` | `A4` `A5` `B5` `Letter` `Legal` | `A4` |

```sh
lp -d XMDY_A4 -o XmdyDensity=2 -o XmdyDither=Diffusion photo.jpg
```

## Build

Requirements: macOS 11+ and Xcode or the Command Line Tools.

```sh
make            # build/: filter, bridge, pairing tool (universal), PPDs
make test       # filter tests + cupstestppd
make pkg        # build/XMDY-A4RJ-<version>.pkg
make install    # install the package (sudo)
```

`tools/make_testpage.py` generates an A4 test page: a frame 5 mm from the edges, a 100 mm bar
and a 170 mm ruler.
`tools/xmdy_dump.py job.bin` decodes a printer byte stream. To capture one, run the filter by hand:

```sh
cupsfilter -p ppd/xmdy-a4rj.ppd -m application/vnd.cups-raster page.pdf > page.ras
PPD=ppd/xmdy-a4rj.ppd build/rastertoxmdy 1 me title 1 "" page.ras > job.bin
tools/xmdy_dump.py job.bin
```

## Troubleshooting

- **Queue stopped, "Unable to send data to printer"**: the printer was off or asleep. The queue uses
  `printer-error-policy=retry-job`, so jobs are retried. To restart the queue right away, run
  `cupsenable XMDY_A4`.
- **Debug log**: run `sudo cupsctl --debug-logging`, print, then check `/var/log/cups/error_log`
  (look for `rastertoxmdy`).
- **Bluetooth log**:
  `/usr/bin/log show --last 1h --predicate 'subsystem == "io.github.timxt23.xmdy"'`.
  Use the full path: in zsh, `log` is a shell builtin.
- **Bluetooth job waits forever**: make sure the printer is on and not connected to a phone,
  and that "XMDY Bluetooth" is allowed in Privacy & Security → Bluetooth. Then run
  `xmdy-btpair` again. Bluetooth printing needs a logged-in user.

## Disclaimer

Not affiliated with XMDY, HZTZ or Haoyin. Trademarks belong to their owners.
The protocol was documented for interoperability. No vendor code or binaries are included.

## License

[MIT](LICENSE)
