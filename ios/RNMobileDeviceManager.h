#if __has_include(<React/RCTBridgeModule.h>)
#import <React/RCTBridgeModule.h>
#elif __has_include(<React/RCTBridgeModule.h>)
#import <React/RCTBridgeModule.h>
#else
#import <React/RCTBridgeModule.h>
#endif
@import AppConfigSettingsFramework;

#import <UIKit/UIKit.h>

@interface MobileDeviceManager : NSObject <RCTBridgeModule, ManagedAppConfigSettingsDelegate>
@end
