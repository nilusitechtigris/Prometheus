#include "SensorsC.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <string.h>

// MARK: - SMC

typedef struct { char major, minor, build, reserved[1]; UInt16 release; } SMCVersion;
typedef struct { UInt16 version, length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { UInt32 dataSize; UInt32 dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    UInt32 key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    char result, status, data8;
    UInt32 data32;
    unsigned char bytes[32];
} SMCKeyData;

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCGetKeyFromIndex = 8, kSMCGetKeyInfo = 9 };

static io_connect_t gConnection = 0;

static UInt32 fourCC(const char *s) {
    return ((UInt32)(unsigned char)s[0] << 24) | ((UInt32)(unsigned char)s[1] << 16) |
           ((UInt32)(unsigned char)s[2] << 8) | (UInt32)(unsigned char)s[3];
}

static void fourCCString(UInt32 v, char *out) {
    out[0] = (char)(v >> 24); out[1] = (char)(v >> 16); out[2] = (char)(v >> 8); out[3] = (char)v; out[4] = 0;
}

static kern_return_t smcCall(SMCKeyData *input, SMCKeyData *output) {
    size_t outSize = sizeof(SMCKeyData);
    return IOConnectCallStructMethod(gConnection, kSMCHandleYPCEvent, input, sizeof(SMCKeyData), output, &outSize);
}

static int smcKeyInfo(UInt32 key, SMCKeyInfo *info) {
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key; in.data8 = kSMCGetKeyInfo;
    if (smcCall(&in, &out) != KERN_SUCCESS || out.result != 0) return -1;
    *info = out.keyInfo;
    return 0;
}

static int smcReadBytes(UInt32 key, SMCKeyInfo *info, unsigned char *bytes) {
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key; in.keyInfo = *info; in.data8 = kSMCReadKey;
    if (smcCall(&in, &out) != KERN_SUCCESS || out.result != 0) return -1;
    memcpy(bytes, out.bytes, 32);
    return 0;
}

int sensors_smc_open(void) {
    if (gConnection) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &gConnection);
    IOObjectRelease(service);
    return kr == KERN_SUCCESS ? 0 : -1;
}

void sensors_smc_close(void) {
    if (gConnection) { IOServiceClose(gConnection); gConnection = 0; }
}

int sensors_smc_temperature_keys(char *keys, int maxKeys) {
    if (sensors_smc_open() != 0) return 0;
    SMCKeyInfo info;
    unsigned char bytes[32];
    if (smcKeyInfo(fourCC("#KEY"), &info) != 0 || smcReadBytes(fourCC("#KEY"), &info, bytes) != 0) return 0;
    UInt32 total = ((UInt32)bytes[0] << 24) | ((UInt32)bytes[1] << 16) | ((UInt32)bytes[2] << 8) | bytes[3];

    const UInt32 floatType = fourCC("flt ");
    int count = 0;
    for (UInt32 i = 0; i < total && count < maxKeys; i++) {
        SMCKeyData in, out;
        memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
        in.data8 = kSMCGetKeyFromIndex; in.data32 = i;
        if (smcCall(&in, &out) != KERN_SUCCESS || out.result != 0) continue;
        UInt32 key = out.key;
        if ((char)(key >> 24) != 'T') continue;
        if (smcKeyInfo(key, &info) != 0 || info.dataType != floatType) continue;
        fourCCString(key, keys + count * 5);
        count++;
    }
    return count;
}

double sensors_smc_read(const char *key) {
    if (sensors_smc_open() != 0 || strlen(key) != 4) return -999;
    SMCKeyInfo info;
    unsigned char bytes[32];
    UInt32 k = fourCC(key);
    if (smcKeyInfo(k, &info) != 0 || smcReadBytes(k, &info, bytes) != 0) return -999;
    if (info.dataType == fourCC("flt ")) {
        float f; memcpy(&f, bytes, sizeof f);
        return f;
    }
    if (info.dataType == fourCC("sp78")) {
        return (double)(int16_t)((bytes[0] << 8) | bytes[1]) / 256.0;
    }
    return -999;
}

// MARK: - HID temperature sensors (private IOKit HID event API)

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

enum { kIOHIDEventTypeTemperature = 15 };

static IOHIDEventSystemClientRef gHIDClient = NULL;

int sensors_hid_temperatures(char *names, double *values, int maxSensors) {
    if (!gHIDClient) {
        gHIDClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!gHIDClient) return 0;
        int page = 0xff00, usage = 5;
        CFNumberRef pageNum = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef usageNum = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        const void *vals[] = { pageNum, usageNum };
        CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        IOHIDEventSystemClientSetMatching(gHIDClient, match);
        CFRelease(match); CFRelease(pageNum); CFRelease(usageNum);
    }

    CFArrayRef services = IOHIDEventSystemClientCopyServices(gHIDClient);
    if (!services) return 0;
    int count = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(services) && count < maxSensors; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
        if (product && event && CFGetTypeID(product) == CFStringGetTypeID()) {
            char *name = names + count * 64;
            if (CFStringGetCString((CFStringRef)product, name, 64, kCFStringEncodingUTF8)) {
                values[count] = IOHIDEventGetFloatValue(event, kIOHIDEventTypeTemperature << 16);
                count++;
            }
        }
        if (event) CFRelease(event);
        if (product) CFRelease(product);
    }
    CFRelease(services);
    return count;
}
