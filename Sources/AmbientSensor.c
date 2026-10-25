#include "AmbientSensor.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <mach/mach_time.h>

typedef CFTypeRef (*CreateFn)(CFAllocatorRef);
typedef void (*MatchFn)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*ServicesFn)(CFTypeRef);
typedef CFTypeRef (*EventFn)(CFTypeRef, int64_t, int32_t, int64_t);
typedef double (*ValueFn)(CFTypeRef, int32_t);
typedef uint64_t (*TimeFn)(CFTypeRef);

double sunlift_read_lux(void) {
    static void *lib;
    static CFTypeRef client;
    static ServicesFn services;
    static EventFn event;
    static ValueFn value;
    static TimeFn timestamp;
    static int attempted;
    if (!attempted) {
        attempted = 1;
        lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!lib) return NAN;
        CreateFn create = (CreateFn)dlsym(lib, "IOHIDEventSystemClientCreate");
        MatchFn match = (MatchFn)dlsym(lib, "IOHIDEventSystemClientSetMatching");
        services = (ServicesFn)dlsym(lib, "IOHIDEventSystemClientCopyServices");
        event = (EventFn)dlsym(lib, "IOHIDServiceClientCopyEvent");
        value = (ValueFn)dlsym(lib, "IOHIDEventGetFloatValue");
        timestamp = (TimeFn)dlsym(lib, "IOHIDEventGetTimeStamp");
        if (!create || !match || !services || !event || !value || !timestamp) return NAN;
        client = create(kCFAllocatorDefault);
        if (!client) return NAN;
        int page = 0xff00, usage = 4;
        CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
        const void *vals[] = {p, u};
        CFDictionaryRef dict = CFDictionaryCreate(NULL, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        match(client, dict);
        CFRelease(dict); CFRelease(p); CFRelease(u);
    }
    if (!client) return NAN;
    CFArrayRef list = services(client);
    if (!list) return NAN;
    double result = NAN;
    // Refuse ambiguous sensor selection rather than use an external sensor accidentally.
    if (CFArrayGetCount(list) == 1) {
        CFTypeRef sample = event(CFArrayGetValueAtIndex(list, 0), 12, 0, 0);
        if (sample) {
            double lux = value(sample, 12 << 16);
            uint64_t t = timestamp(sample), now = mach_absolute_time();
            mach_timebase_info_data_t base;
            mach_timebase_info(&base);
            double age = t <= now ? (double)(now-t) * base.numer / base.denom / 1e9 : INFINITY;
            if (t && age <= 10 && isfinite(lux) && lux >= 0 && lux <= 200000) result = lux;
            CFRelease(sample);
        }
    }
    CFRelease(list);
    return result;
}
