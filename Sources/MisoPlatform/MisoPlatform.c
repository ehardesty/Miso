#include "MisoPlatform.h"
#include <IOKit/hid/IOHIDUsageTables.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach/mach_time.h>

enum { MTHIDClientPassive = 2 };
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(
    CFAllocatorRef allocator, int type, CFDictionaryRef _Nullable attributes
);

typedef CFTypeRef (*CopyHIDEvent)(CGEventRef);
typedef uint64_t (*GetSender)(CFTypeRef);
typedef uint32_t (*GetEventType)(CFTypeRef);
typedef double (*GetEventFloat)(CFTypeRef, uint32_t);
typedef uint64_t (*GetHIDTimestamp)(CFTypeRef);

static CopyHIDEvent copyHIDEvent;
static GetSender getSender;
static GetEventType getEventType;
static GetEventFloat getEventFloat;
static GetHIDTimestamp getHIDTimestamp;
static double nanosPerTick;

static void resolveSymbols(void *context) {
    (void)context;
    copyHIDEvent = (CopyHIDEvent)dlsym(RTLD_DEFAULT, "CGEventCopyIOHIDEvent");
    getSender = (GetSender)dlsym(RTLD_DEFAULT, "IOHIDEventGetSenderID");
    getEventType = (GetEventType)dlsym(RTLD_DEFAULT, "IOHIDEventGetType");
    getEventFloat = (GetEventFloat)dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
    getHIDTimestamp = (GetHIDTimestamp)dlsym(RTLD_DEFAULT, "IOHIDEventGetTimeStamp");
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) == KERN_SUCCESS) {
        nanosPerTick = (double)timebase.numer / timebase.denom;
    }
}

static void resolveOnce(void) {
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, resolveSymbols);
}

/// Undocumented Quartz field holding the sending device's registry ID. Side
/// buttons on some mice arrive without an attached IOHIDEvent but keep this
/// field. Mac Mouse Fix reads the same field.
static const CGEventField MTSenderField = (CGEventField)87;

uint64_t MTEventSender(CGEventRef event) {
    resolveOnce();
    if (!copyHIDEvent || !getSender) return 0;
    CFTypeRef input = copyHIDEvent(event);
    if (!input) return 0;
    const uint64_t id = getSender(input);
    CFRelease(input);
    return id;
}

uint64_t MTEventFieldSender(CGEventRef event) {
    return (uint64_t)CGEventGetIntegerValueField(event, MTSenderField);
}

uint64_t MTReadScrollDevice(CGEventRef event, double *vertical, double *horizontal, uint64_t *timestampNanoseconds) {
    resolveOnce();
    *vertical = 0;
    *horizontal = 0;
    *timestampNanoseconds = 0;
    if (!copyHIDEvent || !getSender) return 0;
    CFTypeRef input = copyHIDEvent(event);
    if (!input) return 0;
    const uint64_t id = getSender(input);
    const uint32_t scroll = 6;
    if (getEventType && getEventFloat && getEventType(input) == scroll) {
        *horizontal = getEventFloat(input, scroll << 16);
        *vertical = getEventFloat(input, (scroll << 16) | 1);
        if (getHIDTimestamp && nanosPerTick > 0) {
            *timestampNanoseconds = (uint64_t)(getHIDTimestamp(input) * nanosPerTick);
        }
    }
    CFRelease(input);
    return id;
}

typedef void (^HIDServiceBlock)(void *, void *, IOHIDServiceClientRef);
typedef void (*RegisterMatching)(IOHIDEventSystemClientRef, HIDServiceBlock, void *, void *);
typedef void (*RegisterRemoval)(IOHIDServiceClientRef, HIDServiceBlock, void *, void *);
typedef void (*SetClientQueue)(IOHIDEventSystemClientRef, dispatch_queue_t);
typedef void (*UnregisterMatching)(IOHIDEventSystemClientRef);

static RegisterRemoval registerRemoval;
static SetClientQueue unscheduleClient;
static UnregisterMatching unregisterMatching;
static MTMouseServicesChanged mouseServicesChanged;
static void *mouseServicesContext;
static CFMutableSetRef observedMouseIDs;
static uint64_t observationGeneration;
static bool mouseRefreshPending;

static IOHIDEventSystemClientRef mouseServiceClient(void) {
    // Passive clients can read and write pointer properties on USB receivers.
    // Keep the connection alive because those writes are scoped to the client.
    static IOHIDEventSystemClientRef client;
    if (!client) client = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, MTHIDClientPassive, NULL);
    return client;
}

static bool isMouseService(IOHIDServiceClientRef service) {
    return IOHIDServiceClientConformsTo(service, kHIDPage_GenericDesktop, kHIDUsage_GD_Mouse);
}

static void queueMouseServiceRefresh(void) {
    if (mouseRefreshPending) return;
    mouseRefreshPending = true;
    const uint64_t generation = observationGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != observationGeneration) return;
        mouseRefreshPending = false;
        mouseServicesChanged(mouseServicesContext);
    });
}

static void observeMouseRemoval(IOHIDServiceClientRef service) {
    if (!observedMouseIDs) return;
    CFTypeRef id = IOHIDServiceClientGetRegistryID(service);
    int64_t value = 0;
    if (!id || CFGetTypeID(id) != CFNumberGetTypeID() ||
        !CFNumberGetValue(id, kCFNumberSInt64Type, &value) || value == 0 ||
        CFSetContainsValue(observedMouseIDs, id)) return;

    CFSetAddValue(observedMouseIDs, id);
    const uint64_t generation = observationGeneration;
    registerRemoval(service, ^(void *target, void *refcon, IOHIDServiceClientRef removed) {
        if (generation != observationGeneration) return;
        CFNumberRef key = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &value);
        CFSetRemoveValue(observedMouseIDs, key);
        CFRelease(key);
        queueMouseServiceRefresh();
    }, NULL, NULL);
}

void MTStartMouseServiceObservation(MTMouseServicesChanged callback, void *context) {
    if (mouseServicesChanged) return;
    RegisterMatching registerMatching = (RegisterMatching)dlsym(
        RTLD_DEFAULT, "IOHIDEventSystemClientRegisterDeviceMatchingBlock");
    registerRemoval = (RegisterRemoval)dlsym(RTLD_DEFAULT, "IOHIDServiceClientRegisterRemovalBlock");
    SetClientQueue scheduleClient = (SetClientQueue)dlsym(
        RTLD_DEFAULT, "IOHIDEventSystemClientScheduleWithDispatchQueue");
    unscheduleClient = (SetClientQueue)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientUnscheduleFromDispatchQueue");
    unregisterMatching = (UnregisterMatching)dlsym(
        RTLD_DEFAULT, "IOHIDEventSystemClientUnregisterDeviceMatchingBlock");
    if (!registerMatching || !registerRemoval || !scheduleClient || !unscheduleClient || !unregisterMatching) return;

    IOHIDEventSystemClientRef client = mouseServiceClient();
    if (!client) return;
    observedMouseIDs = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
    mouseServicesChanged = callback;
    mouseServicesContext = context;
    const uint64_t generation = ++observationGeneration;
    registerMatching(client, ^(void *target, void *refcon, IOHIDServiceClientRef service) {
        if (generation != observationGeneration || !service || !isMouseService(service)) return;
        observeMouseRemoval(service);
        queueMouseServiceRefresh();
    }, NULL, NULL);
    scheduleClient(client, dispatch_get_main_queue());
}

void MTStopMouseServiceObservation(void) {
    if (!mouseServicesChanged) return;
    ++observationGeneration;
    mouseServicesChanged = NULL;
    mouseServicesContext = NULL;
    mouseRefreshPending = false;
    IOHIDEventSystemClientRef client = mouseServiceClient();
    unregisterMatching(client);
    unscheduleClient(client, dispatch_get_main_queue());
    CFRelease(observedMouseIDs);
    observedMouseIDs = NULL;
}

CFArrayRef MTCopyMouseServices(void) {
    IOHIDEventSystemClientRef client = mouseServiceClient();
    if (!client) return NULL;
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) return NULL;
    CFMutableArrayRef mice = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        if (isMouseService(service)) {
            observeMouseRemoval(service);
            CFArrayAppendValue(mice, service);
        }
    }
    CFRelease(services);
    return mice;
}

uint64_t MTServiceRegistryID(CFTypeRef service) {
    CFTypeRef value = IOHIDServiceClientGetRegistryID((IOHIDServiceClientRef)service);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) return 0;
    int64_t id = 0;
    CFNumberGetValue(value, kCFNumberSInt64Type, &id);
    return (uint64_t)id;
}

bool MTRegistryServiceExists(uint64_t id) {
    CFMutableDictionaryRef match = IORegistryEntryIDMatching(id);
    if (!match) return false;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, match);
    if (!service) return false;
    IOObjectRelease(service);
    return true;
}

CFTypeRef MTCopyServiceProperty(CFTypeRef service, CFStringRef key) {
    return IOHIDServiceClientCopyProperty((IOHIDServiceClientRef)service, key);
}

bool MTSetServiceProperty(CFTypeRef service, CFStringRef key, CFTypeRef value) {
    return IOHIDServiceClientSetProperty((IOHIDServiceClientRef)service, key, value);
}

bool MTSymbolicHotKey(uint32_t identifier, uint16_t *keyCode, uint32_t *modifiers) {
    typedef bool (*IsEnabled)(uint32_t);
    typedef int (*GetValue)(uint32_t, uint16_t *, uint16_t *, uint32_t *);
    IsEnabled isEnabled = (IsEnabled)dlsym(RTLD_DEFAULT, "CGSIsSymbolicHotKeyEnabled");
    GetValue getValue = (GetValue)dlsym(RTLD_DEFAULT, "CGSGetSymbolicHotKeyValue");
    uint16_t character = 0;
    return isEnabled && getValue && isEnabled(identifier)
        && getValue(identifier, &character, keyCode, modifiers) == 0
        && *keyCode != UINT16_MAX && (*keyCode != 0 || character != UINT16_MAX);
}

bool MTDockCommand(CFStringRef notification) {
    typedef int (*SendNotification)(CFStringRef, int);
    SendNotification send = (SendNotification)dlsym(RTLD_DEFAULT, "CoreDockSendNotification");
    return send && send(notification, 0) == 0;
}
