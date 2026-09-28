/*
 * xmdy-btd - Bluetooth bridge for XMDY A4RJ printers.
 *
 * Copyright (c) 2026 timxt23
 * SPDX-License-Identifier: MIT
 *
 * macOS has no CUPS Bluetooth backend, and backends cannot be added
 * (/usr/libexec/cups/backend is protected by SIP). The Bluetooth queue
 * therefore prints to socket://127.0.0.1:9101; a launchd agent accepts the
 * connection and starts this program with the socket on stdin/stdout
 * (inetd mode).
 *
 * It runs as an app bundle ("XMDY Bluetooth.app") in the user's session:
 * macOS grants Bluetooth access (TCC) only to apps the user approves, never
 * to system daemons. An empty connection only touches Bluetooth, so setup can
 * show the permission prompt before the first print. The program:
 *
 *   1. reads the whole job (Bluetooth format made by rastertoxmdy),
 *   2. opens an RFCOMM channel to the paired printer (SPP, via IOBluetooth),
 *   3. sends the status query 10 FF 40 and expects 00 (ready),
 *   4. sends the job in MTU-sized writes (RFCOMM flow control paces them),
 *   5. waits for AA (printing done) once per page (10 FF FE 45 in the job),
 *   6. closes the channel and the connection, so CUPS marks the job complete.
 *
 * The serial port /dev/cu.<name> is not used: on recent macOS versions
 * opening it does not bring up the Bluetooth link once the printer has slept.
 *
 * While the printer is off or out of range it retries with a growing delay
 * (RETRY_MIN_S..RETRY_MAX_S) for up to WAIT_MAX_S. When idle no process runs:
 * launchd owns the listening socket. A canceled job closes the socket; the next
 * heartbeat write fails with EPIPE and the program exits.
 *
 * Usage: xmdy-btd [name-prefix | address]
 * Default: the address in /Library/Printers/XMDY-A4/bt-address (written by
 * setup-queue.sh --bluetooth), else the first paired device named A4RJ*.
 * A launchd daemon may not see the paired-device list, so the address is preferred.
 * Logs:  log show --predicate 'subsystem == "io.github.timxt23.xmdy"'
 */

#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#include <errno.h>
#include <os/log.h>
#include <signal.h>
#include <unistd.h>

#define MAX_JOB (64u << 20)
#define RETRY_MIN_S 10    /* first retry while the printer is off */
#define RETRY_MAX_S 120   /* retries back off 10, 20, 40, 80, 120, 120... s: each try pages the radio */
#define WAIT_MAX_S (30 * 60)
#define PAGE_TIMEOUT_S 180

static os_log_t xlog;
#define LOG(fmt, ...) os_log(xlog, fmt, ##__VA_ARGS__)
#define LOGERR(fmt, ...) os_log_error(xlog, fmt, ##__VA_ARGS__)

@interface Link : NSObject <IOBluetoothRFCOMMChannelDelegate>
@property(strong) IOBluetoothDevice *device;
@property(strong) IOBluetoothRFCOMMChannel *channel;
@property(strong) NSMutableData *rx;
@property BOOL closed;
@end

@implementation Link
- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)c data:(void *)p length:(size_t)n {
  [self.rx appendBytes:p length:n];
}
- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)c {
  self.closed = YES;
}

- (BOOL)open {
  self.rx = [NSMutableData data];
  self.closed = NO;
  BluetoothRFCOMMChannelID ch = 0;
  IOBluetoothSDPServiceRecord *rec =
      [self.device getServiceRecordForUUID:[IOBluetoothSDPUUID uuid16:kBluetoothSDPUUID16ServiceClassSerialPort]];
  if (!rec) {  /* no cached SDP record yet: query it (needs the printer on) */
    [self.device performSDPQuery:nil];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
    rec = [self.device getServiceRecordForUUID:[IOBluetoothSDPUUID uuid16:kBluetoothSDPUUID16ServiceClassSerialPort]];
  }
  if (!rec || [rec getRFCOMMChannelID:&ch] != kIOReturnSuccess) ch = 1;  /* A4RJ uses channel 1 */

  IOBluetoothRFCOMMChannel *c = nil;
  IOReturn r = [self.device openRFCOMMChannelSync:&c withChannelID:ch delegate:self];
  if (r != kIOReturnSuccess || !c) {
    LOG("%{public}@ not reachable (off, asleep or connected to a phone), error 0x%x; retrying",
        self.device.name.length ? self.device.name : self.device.addressString, r);
    [self.device closeConnection];
    return NO;
  }
  self.channel = c;
  return YES;
}

- (void)close {
  if (self.channel) [self.channel closeChannel];
  self.channel = nil;
  [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
  [self.device closeConnection];
}

/* first received byte within timeout, -1 if none. Sleeps in the run loop until
 * IOBluetooth delivers data or the channel closes: no polling. */
- (int)readByte:(NSTimeInterval)timeout {
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (self.rx.length == 0 && !self.closed && until.timeIntervalSinceNow > 0)
    if (![NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:until])
      usleep(100000);  /* no input sources attached: avoid a busy loop */
  if (self.rx.length == 0) return -1;
  int b = ((const uint8_t *)self.rx.bytes)[0];
  [self.rx replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
  return b;
}

- (BOOL)send:(const uint8_t *)p count:(size_t)n {
  size_t mtu = self.channel.getMTU ?: 127;
  for (size_t off = 0; off < n;) {
    UInt16 chunk = (UInt16)MIN(mtu, n - off);
    IOReturn r = [self.channel writeSync:(void *)(uintptr_t)(p + off) length:chunk];
    if (r != kIOReturnSuccess) { LOGERR("write failed 0x%x after %zu bytes", r, off); return NO; }
    off += chunk;
  }
  return YES;
}
@end

static NSData *read_job(void) {
  NSMutableData *d = [NSMutableData data];
  uint8_t buf[65536];
  for (;;) {
    ssize_t r = read(0, buf, sizeof buf);
    if (r < 0 && errno == EINTR) continue;
    if (r <= 0) break;
    [d appendBytes:buf length:(NSUInteger)r];
    if (d.length > MAX_JOB) return nil;
  }
  return d;
}

static int count_pages(NSData *job) {
  const uint8_t *d = job.bytes;
  int pages = 0;
  for (NSUInteger i = 0; i + 4 <= job.length; i++)
    if (d[i] == 0x10 && d[i + 1] == 0xFF && d[i + 2] == 0xFE && d[i + 3] == 0x45) pages++;
  return pages;
}

static IOBluetoothDevice *find_printer(NSString *key) {
  if ([key containsString:@"-"] || [key containsString:@":"])
    return [IOBluetoothDevice deviceWithAddressString:key];
  for (IOBluetoothDevice *d in IOBluetoothDevice.pairedDevices)
    if ([d.name hasPrefix:key]) return d;
  return nil;
}

/* heartbeat on the back channel: fails with EPIPE when CUPS canceled the job */
static BOOL job_canceled(void) {
  return write(1, "", 1) < 0 && errno == EPIPE;
}

int main(int argc, char *argv[]) {
  @autoreleasepool {
    xlog = os_log_create("io.github.timxt23.xmdy", "btd");
    signal(SIGPIPE, SIG_IGN);
    NSString *key = argc > 1 ? @(argv[1]) : nil;
    if (!key) {
      NSString *saved = [NSString stringWithContentsOfFile:@"/Library/Printers/XMDY-A4/bt-address"
                                                  encoding:NSUTF8StringEncoding error:nil];
      saved = [saved stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      key = saved.length ? saved : @"A4RJ";
    }

    NSData *job = read_job();
    if (!job) { LOGERR("oversized job"); return 1; }
    if (job.length == 0) {  /* setup ping: trigger the Bluetooth permission prompt */
      LOG("ping, %lu paired device(s) visible", (unsigned long)IOBluetoothDevice.pairedDevices.count);
      return 0;
    }
    int pages = count_pages(job);
    LOG("job %lu bytes, %d page(s)", (unsigned long)job.length, pages);

    Link *link = [Link new];
    NSDate *start = [NSDate date];
    unsigned delay = RETRY_MIN_S;
    for (;;) {
      link.device = find_printer(key);
      if (!link.device) {
        LOGERR("no paired printer %{public}@ - run xmdy-btpair", key);
      } else if ([link open]) {
        static const uint8_t status[] = {0x10, 0xFF, 0x40};
        int st = [link send:status count:3] ? [link readByte:4] : -1;
        if (st == 0x00) break;
        LOG("%{public}@: printer not ready (status %d)", link.device.name, st);
        [link close];
      }
      if (-start.timeIntervalSinceNow > WAIT_MAX_S) { LOGERR("giving up after %d s", WAIT_MAX_S); return 1; }
      LOG("next try in %u s", delay);
      sleep(delay);
      delay = delay * 2 > RETRY_MAX_S ? RETRY_MAX_S : delay * 2;
      if (job_canceled()) { LOG("job canceled"); return 1; }
    }

    LOG("%{public}@ ready, sending", link.device.name);
    NSDate *t0 = [NSDate date];
    if (![link send:job.bytes count:job.length]) { [link close]; return 1; }
    LOG("sent %lu bytes in %.1f s, waiting for %d page(s)", (unsigned long)job.length, -t0.timeIntervalSinceNow, pages);

    int done = 0;
    NSDate *last = [NSDate date];
    while (done < pages && !link.closed && -last.timeIntervalSinceNow < PAGE_TIMEOUT_S) {
      int b = [link readByte:5];  /* wakes on data; every 5 s checks for a canceled job */
      if (b == 0xAA) { done++; last = [NSDate date]; }
      else if (b < 0 && job_canceled()) { LOG("job canceled while printing"); break; }
    }
    if (done < pages) LOGERR("only %d of %d page(s) confirmed", done, pages);
    else LOG("printed %d page(s) in %.1f s", done, -t0.timeIntervalSinceNow);

    [link close];
    return 0;
  }
}
