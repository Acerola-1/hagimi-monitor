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
