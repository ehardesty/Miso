#ifndef MisoPlatform_h
#define MisoPlatform_h

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

CF_ASSUME_NONNULL_BEGIN

uint64_t MTEventSender(CGEventRef event);
uint64_t MTReadScrollDevice(CGEventRef event, double *vertical, double *horizontal, uint64_t *timestampNanoseconds);
CFArrayRef _Nullable MTCopyMouseServices(void) CF_RETURNS_RETAINED;
uint64_t MTServiceRegistryID(CFTypeRef service);
CFTypeRef _Nullable MTCopyServiceProperty(CFTypeRef service, CFStringRef key) CF_RETURNS_RETAINED;
bool MTSetServiceProperty(CFTypeRef service, CFStringRef key, CFTypeRef value);

bool MTSymbolicHotKey(uint32_t identifier, uint16_t *keyCode, uint32_t *modifiers);
bool MTDockCommand(CFStringRef notification);

CF_ASSUME_NONNULL_END
#endif
