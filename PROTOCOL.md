# XMDY A4RJ printer protocol

Notes on the byte stream accepted by XMDY / HZTZ A4RJ portable A4 thermal printers
(vendor driver family "GD-88"). They were collected by observing the output of the vendor's
macOS CUPS filter and by testing on the hardware. No vendor code is included in this repository.

## Device

| | |
|---|---|
| USB | `0FE6:811E`, product string "Virtual PRN" (generic USB–parallel bridge ID) |
| IEEE 1284 ID | `MFG:XMDY ;CMD:XPP,XL;MDL:A4RJ;CLS:PRINTER;` |
| Bluetooth | Classic SPP, name `A4RJ_XXXX` |
| Print head | 203 dpi, 1680 dots across A4 (210 bytes per row), paper up to 218 mm |

The printer answers ESC/POS status requests (`DLE EOT 1` → `0x12`), but it does **not** print
ESC/POS text, and it ignores `GS v 0` raster unless the job preamble below is sent first.

## Job layout

```
10 FF F1 02                 job start
10 40                       job start
1F 80 01 10                 job start
10 FF 10 00 n               print density, n = 0 (light) .. 3; the vendor filter always sends 0
[1F 11 51]                  marked (folded) paper: search for mark
1D 76 30 00 wL wH hL hH     GS v 0 raster band, w = bytes per row (210 for A4), h = rows
<w*h bytes>                 1 bit per dot, MSB = leftmost dot, 1 = black
...                         the vendor sends bands of 24 rows and pads the last band with blank rows
1B 4A n                     ESC J: feed n dots (8 dots = 1 mm); the vendor sends 96 (12 mm)
[1D 0C 1F 11 50]            marked paper: feed to next mark
10 FF F1 45                 vendor job end (see below)
```

A multi-page job keeps one preamble. Pages are simply concatenated as raster bands.

### Paper types (vendor driver behaviour)

| Type | After preamble | At end of job |
|---|---|---|
| Continuous roll | – | `1B 4A 60` |
| Label / folded paper with marks | `1F 11 51` | `1D 0C 1F 11 50` |
| Tattoo paper | – | – |

### The `10 FF F1 45` problem

The vendor filter ends every job with `10 FF F1 45`. Over USB, the **first write of the next job**
after this command fails. CUPS reports "Unable to send data to printer" and stops the queue.
A retry succeeds. Without the command, the page prints completely and the next job works,
so `rastertoxmdy` does not send it.

### Density

`10 FF 10 00 n` is the "set density" command used by this printer family's Android SDK in ESC mode.
The vendor macOS driver shows a Darkness option but always sends `n = 0`.

## Not supported / unknown

- Print speed: no ESC-mode speed command is known.
- 300 dpi: some A4RJ units are sold as 300 dpi. The vendor macOS driver uses 203 dpi only.
- Bluetooth printing: the same stream probably works over SPP, but it has not been tested.
  macOS has no CUPS Bluetooth backend.
