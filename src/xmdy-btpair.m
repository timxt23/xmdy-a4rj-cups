/*
 * xmdy-btpair - pair an XMDY A4RJ printer over Bluetooth.
 *
 * Copyright (c) 2026 timxt23
 * SPDX-License-Identifier: MIT
 *
 * macOS System Settings lists the printer under "Nearby Devices" but shows no
 * Connect button for devices of the Printer class. This tool pairs it through
 * IOBluetooth, after which macOS creates the serial port /dev/cu.<name>.
 *
 * Usage:
 *   xmdy-btpair                  find a printer named A4RJ* nearby and pair it
 *   xmdy-btpair aa-bb-cc-dd-ee-ff [PIN]
 *   xmdy-btpair --prefix NAME    other name prefix (default A4RJ)
 *
 * Run it as the logged-in user (not with sudo): macOS may ask to allow
 * Bluetooth access for the terminal app.
 */

#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

@interface Pairer : NSObject <IOBluetoothDeviceInquiryDelegate>
@property NSString *pin;
@property NSString *prefix;
@property IOBluetoothDevice *found;
@property BOOL inquiryDone;
@property BOOL pairDone;
@property IOReturn pairResult;
@end

@implementation Pairer
- (void)deviceInquiryDeviceFound:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)device {
  NSString *name = device.name;
  if (name) printf("  found %s (%s)\n", name.UTF8String, device.addressString.UTF8String);
  if (!self.found && [name hasPrefix:self.prefix]) { self.found = device; [sender stop]; }
}
- (void)deviceInquiryDeviceNameUpdated:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)device
                      devicesRemaining:(uint32_t)remaining {
  [self deviceInquiryDeviceFound:sender device:device];
}
- (void)deviceInquiryComplete:(IOBluetoothDeviceInquiry *)sender error:(IOReturn)error aborted:(BOOL)aborted {
  self.inquiryDone = YES;
}
- (void)devicePairingPINCodeRequest:(IOBluetoothDevicePair *)sender {
  printf("  PIN requested, sending %s\n", self.pin.UTF8String);
  BluetoothPINCode code = {0};
  NSUInteger n = MIN(self.pin.length, sizeof code.data);
  memcpy(code.data, self.pin.UTF8String, n);
  [sender replyPINCode:n PINCode:&code];
}
- (void)devicePairingUserConfirmationRequest:(IOBluetoothDevicePair *)sender numericValue:(BluetoothNumericValue)v {
  [sender replyUserConfirmation:YES];
}
- (void)devicePairingFinished:(id)sender error:(IOReturn)error {
  self.pairResult = error;
  self.pairDone = YES;
}
@end

static void spin(BOOL *flag, NSTimeInterval seconds) {
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while (!*flag && until.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
}

int main(int argc, char *argv[]) {
  @autoreleasepool {
    Pairer *p = [Pairer new];
    p.pin = @"0000";
    p.prefix = @"A4RJ";
    NSString *address = nil;
    for (int i = 1; i < argc; i++) {
      NSString *a = @(argv[i]);
      if ([a isEqualToString:@"--prefix"] && i + 1 < argc) p.prefix = @(argv[++i]);
      else if ([a hasPrefix:@"-"]) { fprintf(stderr, "usage: xmdy-btpair [ADDRESS [PIN]] [--prefix NAME]\n"); return 2; }
      else if (!address) address = a;
      else p.pin = a;
    }

    IOBluetoothDevice *dev = nil;
    if (address) {
      dev = [IOBluetoothDevice deviceWithAddressString:address];
    } else {
      for (IOBluetoothDevice *d in IOBluetoothDevice.pairedDevices)
        if ([d.name hasPrefix:p.prefix]) { dev = d; break; }
      if (!dev) {
        printf("Searching for %s* printers (up to 20 s). Turn the printer on...\n", p.prefix.UTF8String);
        IOBluetoothDeviceInquiry *inq = [IOBluetoothDeviceInquiry inquiryWithDelegate:p];
        inq.inquiryLength = 20;
        inq.updateNewDeviceNames = YES;
        if ([inq start] != kIOReturnSuccess) { fprintf(stderr, "Bluetooth inquiry failed. Is Bluetooth on?\n"); return 1; }
        BOOL done = NO;
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:25];
        while (!p.found && !p.inquiryDone && until.timeIntervalSinceNow > 0) spin(&done, 0.3);
        [inq stop];
        dev = p.found;
      }
    }
    if (!dev) { fprintf(stderr, "No %s* printer found. Turn it on and disconnect it from phones.\n", p.prefix.UTF8String); return 1; }

    printf("Printer: %s (%s)\n", (dev.name ?: @"?").UTF8String, dev.addressString.UTF8String);
    if (!dev.isPaired) {
      IOBluetoothDevicePair *pair = [IOBluetoothDevicePair pairWithDevice:dev];
      pair.delegate = p;
      if ([pair start] != kIOReturnSuccess) { fprintf(stderr, "Pairing could not start.\n"); return 1; }
      BOOL done = NO;
      NSDate *until = [NSDate dateWithTimeIntervalSinceNow:45];
      while (!p.pairDone && until.timeIntervalSinceNow > 0) spin(&done, 0.3);
      if (!p.pairDone || p.pairResult != kIOReturnSuccess) {
        fprintf(stderr, "Pairing failed (0x%x). Remove the printer from other devices and retry.\n", p.pairResult);
        return 1;
      }
      printf("Paired.\n");
    } else {
      printf("Already paired.\n");
    }

    NSString *port = [@"/dev/cu." stringByAppendingString:[dev.name stringByReplacingOccurrencesOfString:@" " withString:@"-"]];
    for (int i = 0; i < 20 && ![NSFileManager.defaultManager fileExistsAtPath:port]; i++) usleep(250000);
    if ([NSFileManager.defaultManager fileExistsAtPath:port]) printf("Serial port: %s\n", port.UTF8String);
    else printf("Serial port not found yet (expected %s)\n", port.UTF8String);
    return 0;
  }
}
