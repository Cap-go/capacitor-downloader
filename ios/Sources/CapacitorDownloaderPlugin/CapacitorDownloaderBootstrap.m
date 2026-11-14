#import <Foundation/Foundation.h>

@interface CapacitorDownloaderLaunchHook : NSObject
@end

@implementation CapacitorDownloaderLaunchHook

+ (void)load {
  Class lifecycle = NSClassFromString(@"CapacitorDownloaderLifecycle");
  if (lifecycle == nil) {
    return;
  }
  SEL selector = NSSelectorFromString(@"warmUpBackgroundSessions");
  if (![lifecycle respondsToSelector:selector]) {
    return;
  }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [lifecycle performSelector:selector];
#pragma clang diagnostic pop
}

@end