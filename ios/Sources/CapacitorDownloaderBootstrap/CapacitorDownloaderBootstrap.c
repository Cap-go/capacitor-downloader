#import <objc/message.h>
#import <objc/runtime.h>

__attribute__((constructor)) static void CapacitorDownloaderBootstrapOnLoad(void) {
    Class lifecycle = objc_getClass("CapacitorDownloaderLifecycle");
    if (lifecycle == nil) {
        return;
    }
    SEL selector = sel_registerName("warmUpBackgroundSessions");
    if (!class_respondsToSelector(object_getClass(lifecycle), selector)) {
        return;
    }
    ((void (*)(id, SEL))objc_msgSend)(lifecycle, selector);
}