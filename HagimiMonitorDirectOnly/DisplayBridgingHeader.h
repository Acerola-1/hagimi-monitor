#import <Foundation/Foundation.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import <CoreGraphics/CoreGraphics.h>

typedef CFTypeRef IOAVService;
extern IOAVService IOAVServiceCreate(CFAllocatorRef allocator);
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVService service, uint32_t chipAddress, uint32_t offset, void* outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVService service, uint32_t chipAddress, uint32_t dataAddress, void* inputBuffer, uint32_t inputBufferSize);
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID);

extern int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);

// IOReport is a private framework and is intentionally declared only in the
// Direct-distribution bridging header. The App Store target neither imports
// these symbols nor links libIOReport.
extern CFDictionaryRef _Nullable IOReportCopyChannelsInGroup(
    CFStringRef _Nonnull group,
    CFStringRef _Nullable subgroup,
    uint64_t optionsA,
    uint64_t optionsB
);
extern CFTypeRef _Nullable IOReportCreateSubscription(
    CFTypeRef _Nullable allocator,
    CFMutableDictionaryRef _Nonnull channels,
    CFMutableDictionaryRef _Nullable * _Nullable subscribedChannels,
    uint64_t options,
    CFTypeRef _Nullable context
);
extern CFDictionaryRef _Nullable IOReportCreateSamples(
    CFTypeRef _Nonnull subscription,
    CFMutableDictionaryRef _Nonnull subscribedChannels,
    CFTypeRef _Nullable context
);
extern CFStringRef _Nullable IOReportChannelGetChannelName(CFDictionaryRef _Nonnull channel);
extern uint64_t IOReportChannelGetUnit(CFDictionaryRef _Nonnull channel);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef _Nonnull channel, int32_t index);

@interface OSDManager : NSObject
+ (id _Nullable)sharedManager;
- (void)showImage:(long long)image
        onDisplayID:(unsigned int)displayID
        priority:(unsigned int)priority
        msecUntilFade:(unsigned int)msec
        filledChiclets:(unsigned int)filled
        totalChiclets:(unsigned int)total
        locked:(BOOL)locked;
@end
