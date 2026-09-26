#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <OpenGL/OpenGL.h>
#import <objc/runtime.h>
#import <stdatomic.h>

// 本文件仅供受控原型使用，不注入第三方游戏。
static _Atomic unsigned long metalDrawables;
static _Atomic unsigned long metalPresented;
static _Atomic unsigned long metalDropped;
static _Atomic unsigned long cglSwaps;
static _Atomic unsigned long cocoaSwaps;
static dispatch_source_t reportTimer;
static FILE *reportFile;

@interface CAMetalLayer (HagimiPresentObserver)
- (id<CAMetalDrawable>)hagimi_nextDrawable;
@end

@implementation CAMetalLayer (HagimiPresentObserver)
- (id<CAMetalDrawable>)hagimi_nextDrawable {
    id<CAMetalDrawable> drawable = [self hagimi_nextDrawable];
    if (!drawable) return nil;
    atomic_fetch_add_explicit(&metalDrawables, 1, memory_order_relaxed);
    [drawable addPresentedHandler:^(id<MTLDrawable> completed) {
        if (completed.presentedTime > 0) {
            atomic_fetch_add_explicit(&metalPresented, 1, memory_order_relaxed);
        } else {
            atomic_fetch_add_explicit(&metalDropped, 1, memory_order_relaxed);
        }
    }];
    return drawable;
}
@end

@interface NSOpenGLContext (HagimiPresentObserver)
- (void)hagimi_flushBuffer;
@end

@implementation NSOpenGLContext (HagimiPresentObserver)
- (void)hagimi_flushBuffer {
    [self hagimi_flushBuffer];
    atomic_fetch_add_explicit(&cocoaSwaps, 1, memory_order_relaxed);
}
@end

static void exchangeMethod(Class cls, SEL original, SEL replacement) {
    Method first = class_getInstanceMethod(cls, original);
    Method second = class_getInstanceMethod(cls, replacement);
    if (first && second) method_exchangeImplementations(first, second);
}

static CGLError observedCGLFlushDrawable(CGLContextObj context) {
    CGLError result = CGLFlushDrawable(context);
    if (result == kCGLNoError) {
        atomic_fetch_add_explicit(&cglSwaps, 1, memory_order_relaxed);
    }
    return result;
}

// dyld interpose 捕获直接调用 CGLFlushDrawable 的 OpenGL 程序。
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } cglInterpose = {
    (const void *)observedCGLFlushDrawable, (const void *)CGLFlushDrawable
};

__attribute__((constructor))
static void installObserver(void) {
    const char *path = getenv("HAGIMI_FPS_PROBE_LOG");
    reportFile = path ? fopen(path, "a") : stderr;
    if (!reportFile) reportFile = stderr;
    setvbuf(reportFile, NULL, _IOLBF, 0);
    exchangeMethod(CAMetalLayer.class, @selector(nextDrawable), @selector(hagimi_nextDrawable));
    exchangeMethod(NSOpenGLContext.class, @selector(flushBuffer), @selector(hagimi_flushBuffer));
    fprintf(reportFile, "{\"probe\":\"loaded\",\"pid\":%d}\n", getpid());

    reportTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                         dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(reportTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              NSEC_PER_SEC, NSEC_PER_MSEC * 20);
    dispatch_source_set_event_handler(reportTimer, ^{
        unsigned long acquired = atomic_exchange(&metalDrawables, 0);
        unsigned long presented = atomic_exchange(&metalPresented, 0);
        unsigned long dropped = atomic_exchange(&metalDropped, 0);
        unsigned long cgl = atomic_exchange(&cglSwaps, 0);
        unsigned long cocoa = atomic_exchange(&cocoaSwaps, 0);
        fprintf(reportFile,
                "{\"probe\":\"fps\",\"pid\":%d,\"metal_acquired\":%lu,\"metal_presented\":%lu,\"metal_dropped\":%lu,\"cgl_swaps\":%lu,\"cocoa_swaps\":%lu}\n",
                getpid(), acquired, presented, dropped, cgl, cocoa);
    });
    dispatch_resume(reportTimer);
}
