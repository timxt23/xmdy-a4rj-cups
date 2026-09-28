/*
 * rastertoxmdy - CUPS raster filter for XMDY / HZTZ A4RJ (GD-88 family)
 * portable A4 thermal printers.
 *
 * Copyright (c) 2026 timxt23
 * SPDX-License-Identifier: MIT
 *
 * Input:  CUPS raster, 8-bit grayscale (or 1-bit), 203 dpi.
 * Output: printer byte stream, see PROTOCOL.md:
 *
 *   10 FF F1 02  10 40  1F 80 01 10      job preamble
 *   10 FF 10 00 n                        print density, n = 0..3
 *   [1F 11 51]                           marked paper: find mark
 *   ESC J n ...                          feed before document
 *   1D 76 30 00 wL wH 18 00 <data> x N   GS v 0 raster, 24-row bands, 1 = black
 *   ESC J n ...                          feed after page / document
 *   [1D 0C 1F 11 50]                     marked paper: advance to next mark
 *
 * The vendor driver ends every job with 10 FF F1 45. After that command the
 * first USB write of the next job fails ("Unable to send data to printer"),
 * so it is intentionally not sent. Printing is complete without it.
 *
 * Options (see ppd/xmdy-a4rj.ppd). Job options override PPD defaults.
 *   XmdyDensity     0..3            printer density command
 *   XmdyThreshold   1..255          black threshold for 8-bit input
 *   XmdyDither      Threshold|Diffusion
 *   XmdyNegative    True|False
 *   XmdyMirror      True|False
 *   XmdyMediaType   Continuous|Marks|Tattoo
 *   XmdyTrim        True|False      skip blank rows at the end of each page
 *   XmdyOffsetX     mm              horizontal shift, may be negative
 *   XmdyFeedBefore  mm              feed before document
 *   XmdyPageFeed    mm              feed after each page
 *   XmdyFeedAfter   mm              feed after document (continuous paper)
 */

#include <cups/cups.h>
#include <cups/ppd.h>
#include <cups/raster.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#ifndef XMDY_VERSION
#define XMDY_VERSION "dev"
#endif

#define BAND_ROWS 24
#define MAX_BYTES 216  /* 1728 dots: widest paper is 218 mm */
#define DOTS_PER_MM 8  /* 203 dpi */

enum media { MEDIA_CONTINUOUS, MEDIA_MARKS, MEDIA_TATTOO };

static volatile sig_atomic_t canceled = 0;
static ppd_file_t *ppd = NULL;

static void on_term(int sig) { (void)sig; canceled = 1; }

static void out(const void *p, size_t n) {
  const unsigned char *b = p;
  while (n > 0) {
    ssize_t w = write(1, b, n);
    if (w < 0) { perror("ERROR: write"); exit(1); }
    b += w;
    n -= (size_t)w;
  }
}

/* Job option, else the queue's PPD default, else def. */
static const char *opt(int n, cups_option_t *o, const char *name, const char *def) {
  const char *v = cupsGetOption(name, n, o);
  if (v) return v;
  if (ppd) {
    ppd_choice_t *c = ppdFindMarkedChoice(ppd, name);
    if (c) return c->choice;
  }
  return def;
}

static int opt_bool(int n, cups_option_t *o, const char *name) {
  const char *v = opt(n, o, name, "False");
  return !strcasecmp(v, "True") || !strcasecmp(v, "yes") || !strcmp(v, "1") || !strcasecmp(v, "on");
}

static void feed_mm(int mm) {
  int dots = mm * DOTS_PER_MM;
  while (dots > 0) {
    int step = dots > 255 ? 255 : dots;
    unsigned char cmd[3] = {0x1B, 0x4A, (unsigned char)step};
    out(cmd, 3);
    dots -= step;
  }
}

int main(int argc, char *argv[]) {
  if (argc < 6 || argc > 7) {
    fputs("Usage: rastertoxmdy job user title copies options [file]\n", stderr);
    return 1;
  }

  int fd = 0;
  if (argc == 7 && (fd = open(argv[6], O_RDONLY)) < 0) {
    perror("ERROR: open");
    return 1;
  }

  signal(SIGTERM, on_term);

  cups_option_t *options = NULL;
  int num_options = cupsParseOptions(argv[5], 0, &options);

  const char *ppd_path = getenv("PPD");
  if (ppd_path && (ppd = ppdOpenFile(ppd_path)) != NULL) ppdMarkDefaults(ppd);

  const char *mt = opt(num_options, options, "XmdyMediaType", "Continuous");
  enum media media = !strcmp(mt, "Marks") ? MEDIA_MARKS
                   : !strcmp(mt, "Tattoo") ? MEDIA_TATTOO : MEDIA_CONTINUOUS;
  int density = atoi(opt(num_options, options, "XmdyDensity", "1"));
  if (density < 0 || density > 15) density = 1;
  int threshold = atoi(opt(num_options, options, "XmdyThreshold", "128"));
  if (threshold < 1 || threshold > 255) threshold = 128;
  int diffusion = !strcmp(opt(num_options, options, "XmdyDither", "Threshold"), "Diffusion");
  int mirror = opt_bool(num_options, options, "XmdyMirror");
  int negative = opt_bool(num_options, options, "XmdyNegative");
  int trim = opt_bool(num_options, options, "XmdyTrim");
  int offset_x = atoi(opt(num_options, options, "XmdyOffsetX", "0")) * DOTS_PER_MM;
  int feed_before = atoi(opt(num_options, options, "XmdyFeedBefore", "0"));
  int page_feed = atoi(opt(num_options, options, "XmdyPageFeed", "0"));
  int feed_after = atoi(opt(num_options, options, "XmdyFeedAfter", "12"));

  fprintf(stderr, "DEBUG: rastertoxmdy %s\n", XMDY_VERSION);
  fprintf(stderr, "DEBUG: density=%d threshold=%d diffusion=%d mirror=%d negative=%d trim=%d "
                  "offset=%d feed=%d/%d/%d media=%s\n", density, threshold, diffusion, mirror,
          negative, trim, offset_x, feed_before, page_feed, feed_after, mt);

  cups_raster_t *ras = cupsRasterOpen(fd, CUPS_RASTER_READ);
  cups_page_header2_t h;
  int page = 0;
  unsigned char *line = NULL, *bits = NULL;
  int *err = NULL;
  size_t line_cap = 0;

  static const unsigned char preamble[] = {0x10, 0xFF, 0xF1, 0x02, 0x10, 0x40,
                                           0x1F, 0x80, 0x01, 0x10};

  while (!canceled && cupsRasterReadHeader2(ras, &h)) {
    page++;
    fprintf(stderr, "INFO: Printing page %d\n", page);
    fprintf(stderr, "DEBUG: %ux%u, %u bpp, cspace %u, %u bpl, %ux%u dpi\n", h.cupsWidth,
            h.cupsHeight, h.cupsBitsPerPixel, h.cupsColorSpace, h.cupsBytesPerLine,
            h.HWResolution[0], h.HWResolution[1]);

    if (h.cupsBitsPerColor != 8 && h.cupsBitsPerColor != 1) {
      fprintf(stderr, "ERROR: Unsupported raster depth %u bits\n", h.cupsBitsPerColor);
      return 1;
    }
    /* W/SW: 0 = black; K: 0 = white */
    int black_is_high = h.cupsColorSpace == CUPS_CSPACE_K;

    if (page == 1) {
      out(preamble, sizeof preamble);
      unsigned char dcmd[5] = {0x10, 0xFF, 0x10, 0x00, (unsigned char)density};
      out(dcmd, sizeof dcmd);
      if (media == MEDIA_MARKS) out("\x1F\x11\x51", 3);
      feed_mm(feed_before);
    }

    int src_w = (int)h.cupsWidth;
    unsigned wb = (h.cupsWidth + 7) / 8;
    if (wb > MAX_BYTES) wb = MAX_BYTES;
    int dst_w = (int)wb * 8;
    unsigned height = h.cupsHeight;

    if (h.cupsBytesPerLine > line_cap) {
      line_cap = h.cupsBytesPerLine;
      line = realloc(line, line_cap);
    }
    /* whole page as 1 bpp, plus room to pad the last band with blank rows */
    size_t rows_alloc = height + BAND_ROWS;
    bits = realloc(bits, rows_alloc * wb);
    free(err);
    err = calloc((size_t)src_w + 2, 2 * sizeof(int));
    if (!line || !bits || !err) {
      fputs("ERROR: Out of memory\n", stderr);
      return 1;
    }
    memset(bits, 0, rows_alloc * wb);

    int *e_cur = err, *e_next = err + src_w + 2;
    unsigned last_ink = 0; /* index of last non-blank row + 1 */
    unsigned y;

    for (y = 0; y < height && !canceled; y++) {
      if (cupsRasterReadPixels(ras, line, h.cupsBytesPerLine) != h.cupsBytesPerLine) break;
      unsigned char *dst = bits + (size_t)y * wb;
      int ink = 0;

      if (h.cupsBitsPerColor == 8 && diffusion)
        memset(e_next, 0, ((size_t)src_w + 2) * sizeof(int));

      for (int x = 0; x < src_w; x++) {
        int black;
        if (h.cupsBitsPerColor == 1) {
          int bit = (line[x >> 3] >> (7 - (x & 7))) & 1;
          black = black_is_high ? bit : !bit;
        } else {
          int v = line[x];
          if (black_is_high) v = 255 - v;
          if (diffusion) { /* Floyd-Steinberg */
            int g = v + e_cur[x + 1] / 16;
            black = g < threshold;
            int e = g - (black ? 0 : 255);
            e_cur[x + 2] += e * 7;
            e_next[x] += e * 3;
            e_next[x + 1] += e * 5;
            e_next[x + 2] += e;
          } else {
            black = v < threshold;
          }
        }
        if (negative) black = !black;
        if (!black) continue;
        int dx = (mirror ? src_w - 1 - x : x) + offset_x;
        if (dx < 0 || dx >= dst_w) continue;
        dst[dx >> 3] |= 0x80 >> (dx & 7);
        ink = 1;
      }
      if (h.cupsBitsPerColor == 8 && diffusion) { int *t = e_cur; e_cur = e_next; e_next = t; }
      if (ink) last_ink = y + 1;
    }

    unsigned rows = trim ? last_ink : y;
    if (trim) fprintf(stderr, "DEBUG: trim %u -> %u rows\n", y, rows);

    for (unsigned r = 0; r < rows; r += BAND_ROWS) {
      /* the last band is padded with blank rows (buffer is zeroed), like the vendor driver */
      unsigned char hdr[8] = {0x1D, 0x76, 0x30, 0x00, (unsigned char)(wb & 0xFF),
                              (unsigned char)(wb >> 8), BAND_ROWS, 0x00};
      out(hdr, sizeof hdr);
      out(bits + (size_t)r * wb, (size_t)wb * BAND_ROWS);
    }

    feed_mm(page_feed);
  }

  if (page > 0) {
    if (media == MEDIA_CONTINUOUS) feed_mm(feed_after);
    if (media == MEDIA_MARKS) out("\x1D\x0C\x1F\x11\x50", 5);
  } else {
    fputs("ERROR: No pages found in job\n", stderr);
  }

  cupsRasterClose(ras);
  cupsFreeOptions(num_options, options);
  if (ppd) ppdClose(ppd);
  if (fd) close(fd);
  free(line); free(bits); free(err);
  return page > 0 ? 0 : 1;
}
