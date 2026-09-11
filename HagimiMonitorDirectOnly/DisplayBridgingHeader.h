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

// IOReport 为私有框架，仅在 Direct 分发 target 的桥接头文件中声明。
// App Store target 既不引入这些符号，也不链接 libIOReport。
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

// GPU 时钟态驻留走「状态通道」：给出的是区间内各状态各占多少 tick，而非计数器。
// 状态值只在两份样本的 delta 上有区间含义，故一并声明 delta 接口。
extern CFStringRef _Nullable IOReportChannelGetSubGroup(CFDictionaryRef _Nonnull channel);
extern int32_t IOReportChannelGetFormat(CFDictionaryRef _Nonnull channel);
extern CFDictionaryRef _Nullable IOReportCreateSamplesDelta(
    CFDictionaryRef _Nonnull previous,
    CFDictionaryRef _Nonnull current,
    CFTypeRef _Nullable context
);
extern int32_t IOReportStateGetCount(CFDictionaryRef _Nonnull channel);
extern CFStringRef _Nullable IOReportStateGetNameForIndex(
    CFDictionaryRef _Nonnull channel,
    int32_t index
);
extern int64_t IOReportStateGetResidency(CFDictionaryRef _Nonnull channel, int32_t index);
