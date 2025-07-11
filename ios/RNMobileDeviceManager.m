#import "RNMobileDeviceManager.h"
#import "react_native_mdm-Swift.h"

// Used to send events to JS
#if __has_include(<React/RCTBridge.h>)
#import <React/RCTBridge.h>
#elif __has_include(<React/RCTBridge.h>)
#import <React/RCTBridge.h>
#else
#import <React/RCTBridge.h>
#endif

#if __has_include(<React/RCTEventDispatcher.h>)
#import <React/RCTEventDispatcher.h>
#elif __has_include(<React/RCTEventDispatcher.h>)
#import <React/RCTEventDispatcher.h>
#else
#import <React/RCTEventDispatcher.h>
#endif

@interface MobileDeviceManager ()
@property dispatch_semaphore_t asamSem;
@property dispatch_queue_t eventQueue;
@property BOOL guidedAccessCallbackRequired;
@property BOOL invalidated;
@end

@implementation MobileDeviceManager

@synthesize bridge = _bridge;

static NSString * const APP_CONFIG_CHANGED = @"react-native-mdm/managedAppConfigDidChange";
static NSString * const APP_LOCK_STATUS_CHANGED = @"react-native-mdm/appLockStatusDidChange";
static NSString * const APP_LOCKED = @"appLocked";
static NSString * const APP_LOCKING_ALLOWED = @"appLockingAllowed";
static char * const OPERATION_QUEUE_NAME = "com.robinpowered.RNMobileDeviceManager.OperationQueue";
static char * const NOTIFICATION_QUEUE_NAME = "com.robinpowered.RNMobileDeivceManager.NotificationQueue";

- (instancetype)init
{
    if (self = [super init]) {
        [ManagedAppConfigSettings clientInstance].delegate = self;
        [[ManagedAppConfigSettings clientInstance] start];

        self.asamSem = dispatch_semaphore_create(1);
        self.guidedAccessCallbackRequired = YES;
        self.invalidated = NO;
        self.eventQueue = dispatch_queue_create(NOTIFICATION_QUEUE_NAME, DISPATCH_QUEUE_SERIAL);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(guidedAccessStatusChangeListenerCallback:) name:UIAccessibilityGuidedAccessStatusDidChangeNotification object:nil];
    }
    return self;
}

- (void)invalidate {
    self.invalidated = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc
{
    [[ManagedAppConfigSettings clientInstance] end];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)settingsDidChange:(NSDictionary<NSString *, id> *)changes
{
    id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];
    [_bridge.eventDispatcher sendDeviceEventWithName:APP_CONFIG_CHANGED
                                                body:appConfig];
}

- (void)guidedAccessStatusChangeListenerCallback:(NSNotification*)notification
{
    if (self.invalidated) {
        return;
    }

    dispatch_async(_eventQueue, ^{
        if (_guidedAccessCallbackRequired != NO) {
            dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);
            [self isSAMEnabled:^(BOOL isEnabled) {
                [self isASAMSupported:^(BOOL isAllowed) {
                    dispatch_semaphore_signal(self.asamSem);
                    [_bridge.eventDispatcher sendDeviceEventWithName:APP_LOCK_STATUS_CHANGED
                                                                body:(@{
                                                                        APP_LOCKED: @(isEnabled),
                                                                        APP_LOCKING_ALLOWED: @(isAllowed)
                                                                        })];
                }];
            }];
        }
    });
}

- (void) isASAMSupported:(void(^)(BOOL))callback
{
    _guidedAccessCallbackRequired = NO;

    void (^onComplete)(BOOL success) = ^(BOOL success){
        _guidedAccessCallbackRequired = YES;
        callback(success);
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        if (UIAccessibilityIsGuidedAccessEnabled()) {
            UIAccessibilityRequestGuidedAccessSession(NO, ^(BOOL didDisable) {
                if (didDisable) {
                    UIAccessibilityRequestGuidedAccessSession(YES, ^(BOOL didEnable) {
                        onComplete(didEnable);
                    });
                } else {
                    onComplete(didDisable);
                }
            });
        } else {
            UIAccessibilityRequestGuidedAccessSession(YES, ^(BOOL didEnable) {
                if (didEnable) {
                    UIAccessibilityRequestGuidedAccessSession(NO, ^(BOOL didDisable) {
                        onComplete(didDisable);
                    });
                } else {
                    onComplete(didEnable);
                }
            });
        }
    });
}

- (void) isSAMEnabled:(void(^)(BOOL))callback
{
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL isEnabled = UIAccessibilityIsGuidedAccessEnabled();
        callback(isEnabled);
    });
}

RCT_EXPORT_MODULE();

- (NSDictionary *)constantsToExport
{
    return @{ @"APP_CONFIG_CHANGED": APP_CONFIG_CHANGED,
              @"APP_LOCK_STATUS_CHANGED": APP_LOCK_STATUS_CHANGED,
              @"APP_LOCKED": APP_LOCKED,
              @"APP_LOCKING_ALLOWED": APP_LOCKING_ALLOWED };
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_queue_create(OPERATION_QUEUE_NAME, DISPATCH_QUEUE_SERIAL);
}

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

RCT_EXPORT_METHOD(isSupported: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== App Store + Microsoft Intune Detection ===");
    BOOL isManaged = NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // 1. Primary Detection: Apple's Standard Managed Configuration Key
    // This is set when Intune delivers configuration to App Store apps
    id managedConfig = [defaults objectForKey:@"com.apple.configuration.managed"];
    if (managedConfig) {
        isManaged = YES;
        NSLog(@"✅ MANAGED: Found Apple standard managed configuration");
        resolve(@(isManaged));
        return;
    }
    
    // 2. App-Specific Managed Configuration (Microsoft Intune)
    // Format: com.apple.configuration.managed.{bundleID}
    NSString *appSpecificKey = [NSString stringWithFormat:@"com.apple.configuration.managed.%@", bundleID];
    id appSpecificConfig = [defaults objectForKey:appSpecificKey];
    if (appSpecificConfig) {
        isManaged = YES;
        NSLog(@"✅ MANAGED: Found app-specific managed configuration for %@", bundleID);
        resolve(@(isManaged));
        return;
    }
    
    // 3. ManagedAppConfigSettings Framework (iOS 11+)
    if (@available(iOS 11.0, *)) {
        id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];
        if (appConfig && [appConfig count] > 0) {
            isManaged = YES;
            NSLog(@"✅ MANAGED: Found ManagedAppConfigSettings configuration");
            resolve(@(isManaged));
            return;
        }
    }
    
    // 4. Microsoft Intune Specific Keys
    NSArray *intuneKeys = @[
        @"IntuneMAMUPN",
        @"IntuneComplianceStatus", 
        @"IntuneEnrollmentStatus"
    ];
    
    for (NSString *key in intuneKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            isManaged = YES;
            NSLog(@"✅ MANAGED: Found Intune-specific key: %@", key);
            resolve(@(isManaged));
            return;
        }
    }
    
    // 5. App Store + Intune Linking Detection (Production Workflow)
    // This handles the case where:
    // - App is published on App Store
    // - App is linked to Intune in Microsoft Endpoint Manager
    // - User downloads app through Intune (which gets it from App Store)
    // - Configuration may be delayed but app should be considered managed
    
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *bundleInfo = [mainBundle infoDictionary];
    
    // Required: App must support automatic configuration
    BOOL supportsAutoConfig = [bundleInfo objectForKey:@"NSSupportsAutomaticAppConfiguration"] != nil;
    
    if (supportsAutoConfig) {
        NSLog(@"📱 App supports automatic configuration - checking device enrollment");
        
        // Check for device enrollment in Microsoft Intune/MDM
        NSArray *enrollmentIndicators = @[
            @"CloudConfigurationUIComplete",
            @"MCProfileUUID",
            @"MCProfileVersion", 
            @"MCProfileIdentifier",
            @"DeviceManagementEnrollmentToken"
        ];
        
        BOOL deviceEnrolledInMDM = NO;
        for (NSString *key in enrollmentIndicators) {
            if ([defaults objectForKey:key]) {
                deviceEnrolledInMDM = YES;
                NSLog(@"✅ ENROLLED: Found MDM enrollment indicator: %@", key);
                break;
            }
        }
        
        if (deviceEnrolledInMDM) {
            // Microsoft Intune Standard: App Store apps on enrolled devices
            // are considered managed if they support automatic configuration
            // Configuration delivery may be delayed but app is still managed
            isManaged = YES;
            NSLog(@"✅ MANAGED: App Store app on enrolled device (Microsoft Intune standard)");
            
            // Try to trigger configuration refresh for faster delivery
            [[NSUserDefaults standardUserDefaults] synchronize];
            [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        } else {
            NSLog(@"❌ NOT MANAGED: Device not enrolled in MDM");
        }
    } else {
        NSLog(@"❌ NOT MANAGED: App doesn't support automatic configuration");
    }
    
    NSLog(@"=== FINAL RESULT: %@ ===", isManaged ? @"MANAGED" : @"NOT MANAGED");
    resolve(@(isManaged));
}

RCT_EXPORT_METHOD(getConfiguration:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== Getting MDM Configuration ===");
    
    // Try multiple methods to get configuration
    id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];
    NSMutableDictionary *finalConfig = [NSMutableDictionary dictionary];
    
    // Method 1: ManagedAppConfigSettings
    if (appConfig && [appConfig count] > 0) {
        [finalConfig addEntriesFromDictionary:appConfig];
        NSLog(@"✅ Found config via ManagedAppConfigSettings: %@", appConfig);
    }
    
    // Method 2: Direct UserDefaults check for managed configuration
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    NSArray *configKeys = @[
        @"com.apple.configuration.managed",
        [NSString stringWithFormat:@"com.apple.configuration.managed.%@", bundleID],
        @"com.apple.managed.configuration",
        [NSString stringWithFormat:@"IntuneMAM-%@", bundleID],
        @"ManagedConfiguration"
    ];
    
    for (NSString *key in configKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            if ([value isKindOfClass:[NSDictionary class]]) {
                [finalConfig addEntriesFromDictionary:value];
            } else {
                [finalConfig setObject:value forKey:key];
            }
            NSLog(@"✅ Found config via UserDefaults key %@: %@", key, value);
        }
    }
    
    // Method 3: Check for Intune-specific configuration
    NSArray *intuneKeys = @[
        @"IntuneMAMUPN",
        @"IntuneComplianceStatus", 
        @"IntuneEnrollmentStatus",
        @"IntuneMAMPolicyRequired",
        @"IntuneMAMTelemetryDisabled"
    ];
    
    for (NSString *key in intuneKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            [finalConfig setObject:value forKey:key];
            NSLog(@"✅ Found Intune config: %@ = %@", key, value);
        }
    }
    
    // Method 4: Check app-specific domain for any configuration
    NSDictionary *appDomain = [defaults persistentDomainForName:bundleID];
    if (appDomain) {
        // Look for configuration-like keys (not development keys)
        NSArray *excludeKeys = @[@"expo.eas-client-id", @"expo.devlauncher", @"RCTI18nUtil", @"RCTDevMenu", @"EXDevMenu"];
        
        for (NSString *key in [appDomain allKeys]) {
            BOOL isDevKey = NO;
            for (NSString *excludeKey in excludeKeys) {
                if ([key hasPrefix:excludeKey]) {
                    isDevKey = YES;
                    break;
                }
            }
            
            if (!isDevKey) {
                [finalConfig setObject:[appDomain objectForKey:key] forKey:key];
                NSLog(@"✅ Found app domain config: %@ = %@", key, [appDomain objectForKey:key]);
            }
        }
    }
    
    NSLog(@"Final configuration result: %@", finalConfig);
    resolve(finalConfig);
}

RCT_EXPORT_METHOD(getDirectConfiguration:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== Direct UserDefaults Check ===");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *debugInfo = [NSMutableDictionary dictionary];
    
    // Check essential MDM configuration keys
    NSArray *potentialKeys = @[
        @"com.apple.configuration.managed",
        @"com.apple.managed.configuration",
        @"IntuneComplianceStatus",
        @"IntuneEnrollmentStatus",
        @"IntuneMAMUPN",
        @"ManagedConfiguration"
    ];
    
    BOOL foundMDMConfig = NO;
    NSMutableDictionary *mdmData = [NSMutableDictionary dictionary];
    
    for (NSString *key in potentialKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            NSLog(@"✅ Found MDM key: %@", key);
            [mdmData setObject:value forKey:key];
            foundMDMConfig = YES;
        }
    }
    
    // Check for provisioning profile
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *provisioningPath = [mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
    [debugInfo setObject:@(provisioningPath != nil) forKey:@"HasProvisioningProfile"];
    
    // Look for essential keys only
    NSDictionary *allDefaults = [defaults dictionaryRepresentation];
    NSArray *searchTerms = @[@"managed", @"intune", @"mdm"];
    NSMutableArray *relevantKeys = [NSMutableArray array];
    
    for (NSString *key in [allDefaults allKeys]) {
        for (NSString *term in searchTerms) {
            if ([key.lowercaseString containsString:term.lowercaseString]) {
                [relevantKeys addObject:@{@"key": key, @"value": [allDefaults objectForKey:key] ?: @"<null>"}];
                break;
            }
        }
    }
    
    [debugInfo setObject:@([allDefaults count]) forKey:@"TotalUserDefaultsKeys"];
    [debugInfo setObject:relevantKeys forKey:@"RelevantKeys"];
    [debugInfo setObject:@(foundMDMConfig) forKey:@"FoundMDMConfig"];
    
    if (foundMDMConfig) {
        [mdmData setObject:debugInfo forKey:@"_debugInfo"];
        NSLog(@"✅ MDM config found");
        resolve(mdmData);
    } else {
        NSLog(@"❌ No MDM config found");
        resolve(debugInfo);
    }
}

RCT_EXPORT_METHOD(checkMDMCapabilities:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== MDM Capabilities Check ===");
    NSMutableDictionary *essential = [NSMutableDictionary dictionary];
    
    if (@available(iOS 11.0, *)) {
        // Essential framework checks
        Class deviceMgmtClass = NSClassFromString(@"DMClientAPIController");
        Class managedConfigClass = NSClassFromString(@"MCProfile");
        
        [essential setObject:@(deviceMgmtClass != nil) forKey:@"HasDeviceManagementFramework"];
        [essential setObject:@(managedConfigClass != nil) forKey:@"HasManagedConfigurationFramework"];
        
        // Check if downloaded from Intune (not enterprise/app store)
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *provisioningPath = [mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
        BOOL downloadedFromIntune = NO;
        
        if (provisioningPath) {
            NSData *provisioningData = [NSData dataWithContentsOfFile:provisioningPath];
            if (provisioningData) {
                NSString *provisioningString = [[NSString alloc] initWithData:provisioningData encoding:NSASCIIStringEncoding];
                
                BOOL isEnterprise = [provisioningString containsString:@"enterprise"];
                BOOL isAppStore = [provisioningString containsString:@"app-store"];
                BOOL hasB2B = [provisioningString containsString:@"B2B"];
                
                // App from Intune typically: not enterprise, not app store, possibly B2B
                downloadedFromIntune = !isEnterprise && !isAppStore;
                
                [essential setObject:@(downloadedFromIntune) forKey:@"DownloadedFromIntune"];
                [essential setObject:@(hasB2B) forKey:@"HasB2BDistribution"];
                
                NSLog(@"📱 Download source - Enterprise: %d, AppStore: %d, B2B: %d, FromIntune: %d", 
                      isEnterprise, isAppStore, hasB2B, downloadedFromIntune);
            }
        }
        
        // Try to extract company domain from TeamID or other sources
        NSString *teamIdentifier = [mainBundle objectForInfoDictionaryKey:@"TeamIdentifier"];
        if (teamIdentifier && ![teamIdentifier isEqualToString:@"9QKW94DM92"]) {
            [essential setObject:teamIdentifier forKey:@"CompanyTeamID"];
        }
    }
    
    NSLog(@"✅ Essential capabilities: %@", essential);
    resolve(essential);
}

RCT_EXPORT_METHOD(forceMDMSync:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== Forcing MDM Sync and Deep Analysis ===");
    NSMutableDictionary *syncResult = [NSMutableDictionary dictionary];
    
    // 1. Force refresh of UserDefaults
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // 2. Check bundle details that might affect MDM matching
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *bundleInfo = [mainBundle infoDictionary];
    
    NSString *bundleIdentifier = bundleInfo[@"CFBundleIdentifier"];
    NSString *bundleVersion = bundleInfo[@"CFBundleVersion"];
    NSString *bundleShortVersion = bundleInfo[@"CFBundleShortVersionString"];
    NSString *displayName = bundleInfo[@"CFBundleDisplayName"];
    
    [syncResult setObject:bundleIdentifier ?: @"Unknown" forKey:@"ActualBundleID"];
    [syncResult setObject:bundleVersion ?: @"Unknown" forKey:@"BundleVersion"];
    [syncResult setObject:bundleShortVersion ?: @"Unknown" forKey:@"ShortVersion"];
    [syncResult setObject:displayName ?: @"Unknown" forKey:@"DisplayName"];
    
    NSLog(@"Bundle details - ID: %@, Version: %@, Display: %@", bundleIdentifier, bundleVersion, displayName);
    
    // 3. Check if this specific bundle ID has any UserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Look for bundle-specific configuration keys
    NSString *bundleSpecificKey = [NSString stringWithFormat:@"com.apple.configuration.managed.%@", bundleIdentifier];
    id bundleSpecificConfig = [defaults objectForKey:bundleSpecificKey];
    [syncResult setObject:bundleSpecificConfig ?: @"Not Found" forKey:@"BundleSpecificConfig"];
    
    // 4. Check app-specific domains (only for MDM-related data)
    NSArray *appDomains = @[
        [NSString stringWithFormat:@"group.%@", bundleIdentifier],
        [NSString stringWithFormat:@"%@.managed", bundleIdentifier]
    ];
    
    NSMutableArray *domainResults = [NSMutableArray array];
    
    // Check managed domains
    for (NSString *domain in appDomains) {
        NSDictionary *domainDefaults = [defaults persistentDomainForName:domain];
        if (domainDefaults && [domainDefaults count] > 0) {
            [domainResults addObject:@{@"domain": domain, @"data": domainDefaults}];
            NSLog(@"Found MDM data in domain %@: %@", domain, domainDefaults);
        }
    }
    
    // Check main bundle domain but only include if contains MDM-specific data
    NSDictionary *mainDomain = [defaults persistentDomainForName:bundleIdentifier];
    if (mainDomain && [mainDomain count] > 0) {
        // Filter out development/expo keys and only include MDM-related data
        NSMutableDictionary *mdmData = [NSMutableDictionary dictionary];
        NSArray *mdmKeys = @[
            @"AccountName", @"AccountEmail", @"AccountDomain", @"UserGroupCode",
            @"PolicyAllowFileSave", @"PolicyRestrictCopyPaste", @"PolicyRestrictDocumentSharing",
            @"AppPasscodeLength", @"IntuneMAMUPN", @"IntuneComplianceStatus"
        ];
        
        BOOL hasMDMData = NO;
        for (NSString *key in [mainDomain allKeys]) {
            // Include explicit MDM keys
            for (NSString *mdmKey in mdmKeys) {
                if ([key isEqualToString:mdmKey]) {
                    [mdmData setObject:[mainDomain objectForKey:key] forKey:key];
                    hasMDMData = YES;
                    break;
                }
            }
            
            // Include keys that contain 'managed', 'policy', 'intune', etc.
            if (!hasMDMData && ([key.lowercaseString containsString:@"managed"] || 
                               [key.lowercaseString containsString:@"policy"] ||
                               [key.lowercaseString containsString:@"intune"] ||
                               [key.lowercaseString containsString:@"mdm"])) {
                [mdmData setObject:[mainDomain objectForKey:key] forKey:key];
                hasMDMData = YES;
            }
        }
        
        // Only include main domain if it has actual MDM data
        if (hasMDMData) {
            [domainResults addObject:@{@"domain": bundleIdentifier, @"data": mdmData}];
            NSLog(@"Found MDM data in main domain: %@", mdmData);
        }
    }
    
    [syncResult setObject:domainResults forKey:@"AppDomainData"];
    
    // 5. Force UserDefaults synchronization to get latest data
    if (@available(iOS 11.0, *)) {
        @try {
            // Force sync of UserDefaults from system
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            // Try to get fresh config from ManagedAppConfigSettings
            id freshConfig = [[ManagedAppConfigSettings clientInstance] appConfig];
            if (freshConfig) {
                [syncResult setObject:freshConfig forKey:@"FreshAppConfig"];
                [syncResult setObject:@"SUCCESS" forKey:@"RefreshAttempt"];
            } else {
                [syncResult setObject:@"NO_CONFIG" forKey:@"RefreshAttempt"];
            }
        } @catch (NSException *exception) {
            [syncResult setObject:[NSString stringWithFormat:@"FAILED: %@", exception.reason] forKey:@"RefreshAttempt"];
            NSLog(@"Failed to get fresh ManagedAppConfigSettings: %@", exception);
        }
    }
    
    // 6. Double-check all our target keys after refresh
    NSArray *targetKeys = @[
        @"com.apple.configuration.managed",
        @"com.apple.managed.configuration", 
        bundleSpecificKey,
        [NSString stringWithFormat:@"IntuneMAM-%@", bundleIdentifier]
    ];
    
    NSMutableDictionary *postRefreshCheck = [NSMutableDictionary dictionary];
    for (NSString *key in targetKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            [postRefreshCheck setObject:value forKey:key];
            NSLog(@"POST-REFRESH: Found %@ = %@", key, value);
        }
    }
    [syncResult setObject:postRefreshCheck forKey:@"PostRefreshFindings"];
    
    // 7. Check if there are any pending MDM commands
    NSString *mdmCheckoutPath = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    mdmCheckoutPath = [mdmCheckoutPath stringByAppendingPathComponent:@"ConfigurationProfiles"];
    
    BOOL hasConfigProfiles = [[NSFileManager defaultManager] fileExistsAtPath:mdmCheckoutPath];
    [syncResult setObject:@(hasConfigProfiles) forKey:@"HasConfigurationProfilesDirectory"];
    
    if (hasConfigProfiles) {
        NSArray *profileFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:mdmCheckoutPath error:nil];
        [syncResult setObject:profileFiles ?: @[] forKey:@"ProfileFiles"];
        NSLog(@"Configuration profiles directory contents: %@", profileFiles);
    }
    
    NSLog(@"Force sync result: %@", syncResult);
    resolve(syncResult);
}

RCT_EXPORT_METHOD(getEnrollmentStatus:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== Checking Device Enrollment Status ===");
    NSMutableDictionary *enrollmentInfo = [NSMutableDictionary dictionary];
    
    // Check if device is supervised (requires device to be enrolled in MDM)
    BOOL isSupervised = NO;
    if (@available(iOS 11.0, *)) {
        // Try to detect if device is supervised through various methods
        NSBundle *mainBundle = [NSBundle mainBundle];
        
        // Method 1: Check for enterprise/corporate app indicators
        NSDictionary *bundleInfo = [mainBundle infoDictionary];
        NSString *teamID = bundleInfo[@"TeamIdentifier"];
        NSString *bundleID = bundleInfo[@"CFBundleIdentifier"];
        
        [enrollmentInfo setObject:teamID ?: @"Unknown" forKey:@"TeamID"];
        [enrollmentInfo setObject:bundleID ?: @"Unknown" forKey:@"BundleID"];
        
        // Method 2: Check provisioning profile type
        NSString *provisioningPath = [mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
        if (provisioningPath) {
            NSData *provisioningData = [NSData dataWithContentsOfFile:provisioningPath];
            if (provisioningData) {
                // Parse provisioning profile to check for enterprise distribution
                NSString *provisioningString = [[NSString alloc] initWithData:provisioningData encoding:NSASCIIStringEncoding];
                
                BOOL isEnterprise = [provisioningString containsString:@"enterprise"];
                BOOL isAdHoc = [provisioningString containsString:@"ad-hoc"];
                BOOL isAppStore = [provisioningString containsString:@"app-store"];
                
                [enrollmentInfo setObject:@(isEnterprise) forKey:@"IsEnterprise"];
                [enrollmentInfo setObject:@(isAdHoc) forKey:@"IsAdHoc"];
                [enrollmentInfo setObject:@(isAppStore) forKey:@"IsAppStore"];
                
                NSLog(@"Provisioning profile analysis - Enterprise: %d, AdHoc: %d, AppStore: %d", isEnterprise, isAdHoc, isAppStore);
            }
        }
        
        // Method 3: Check for device management restrictions
        // This is a heuristic - managed devices often have specific restrictions
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        // Check for system-level management indicators
        BOOL hasSystemManagement = NO;
        NSArray *systemKeys = @[@"MCProfileUUID", @"MCProfileVersion", @"MCProfileIdentifier"];
        for (NSString *key in systemKeys) {
            if ([defaults objectForKey:key]) {
                hasSystemManagement = YES;
                NSLog(@"Found system management key: %@", key);
                break;
            }
        }
        
        [enrollmentInfo setObject:@(hasSystemManagement) forKey:@"HasSystemManagement"];
        
        // Method 4: Check app installation method
        // Apps installed through MDM often have different characteristics
        NSString *appPath = [[NSBundle mainBundle] bundlePath];
        BOOL isInApplicationsFolder = [appPath containsString:@"/Applications/"];
        [enrollmentInfo setObject:@(isInApplicationsFolder) forKey:@"IsInApplicationsFolder"];
        
        NSLog(@"App path: %@", appPath);
    }
    
    [enrollmentInfo setObject:@(isSupervised) forKey:@"IsSupervised"];
    
    NSLog(@"Enrollment info: %@", enrollmentInfo);
    resolve(enrollmentInfo);
}

RCT_EXPORT_METHOD(getDeviceInfo:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== Getting Device Management Info ===");
    NSMutableDictionary *deviceInfo = [NSMutableDictionary dictionary];
    
    // Get bundle information
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *bundleID = [mainBundle bundleIdentifier];
    [deviceInfo setObject:bundleID ?: @"unknown" forKey:@"bundleID"];
    
    // Check if managed
    BOOL isManaged = [self checkIfManagedDevice];
    [deviceInfo setObject:@(isManaged) forKey:@"isManaged"];
    
    // Check framework support
    BOOL hasManagedConfigFramework = NO;
    BOOL hasDeviceManagementFramework = NO;
    if (@available(iOS 11.0, *)) {
        Class managedConfigClass = NSClassFromString(@"MCProfile");
        Class deviceMgmtClass = NSClassFromString(@"DMClientAPIController");
        hasManagedConfigFramework = managedConfigClass != nil;
        hasDeviceManagementFramework = deviceMgmtClass != nil;
    }
    [deviceInfo setObject:@(hasManagedConfigFramework) forKey:@"hasManagedConfigFramework"];
    [deviceInfo setObject:@(hasDeviceManagementFramework) forKey:@"hasDeviceManagementFramework"];
    
    // Check provisioning profile
    NSString *provisioningPath = [mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
    [deviceInfo setObject:@(provisioningPath != nil) forKey:@"hasProvisioningProfile"];
    
    // Check if downloaded from Intune
    BOOL downloadedFromIntune = [self checkIfDownloadedFromIntune];
    [deviceInfo setObject:@(downloadedFromIntune) forKey:@"downloadedFromIntune"];
    
    // Get organization information
    NSDictionary *orgInfo = [self getOrganizationInformation];
    [deviceInfo setObject:orgInfo forKey:@"organizationInfo"];
    
    // Extract company domain
    NSString *companyDomain = [self extractCompanyDomainFromOrgInfo:orgInfo];
    [deviceInfo setObject:companyDomain ?: [NSNull null] forKey:@"companyDomain"];
    
    NSLog(@"Device info result: %@", deviceInfo);
    resolve(deviceInfo);
}

RCT_EXPORT_METHOD(getOrganizationInfo:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSDictionary *orgInfo = [self getOrganizationInformation];
    resolve(orgInfo);
}

RCT_EXPORT_METHOD(refreshConfiguration:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== Refreshing Configuration ===");
    
    // Force refresh of all configuration sources
    [[ManagedAppConfigSettings clientInstance] end];
    [[ManagedAppConfigSettings clientInstance] start];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // For App Store apps, try to trigger configuration refresh
    if (@available(iOS 11.0, *)) {
        // Post multiple notifications that might trigger MDM refresh
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ApplicationDidBecomeActive" object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ApplicationWillEnterForeground" object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UIApplicationDidBecomeActiveNotification" object:nil];
        
        // Try to access managed configuration to trigger refresh
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults synchronize];
        
        // Check for managed app configuration domains
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *managedDomain = [NSString stringWithFormat:@"com.apple.configuration.managed.%@", bundleID];
        
        // Force check of managed domain
        id managedConfig = [defaults objectForKey:managedDomain];
        NSLog(@"Forced check of managed domain %@: %@", managedDomain, managedConfig);
        
        // Also check the general managed configuration domain
        id generalManagedConfig = [defaults objectForKey:@"com.apple.configuration.managed"];
        NSLog(@"General managed config: %@", generalManagedConfig);
        
        // Force sync again after notifications
        [defaults synchronize];
    }
    
    // Wait longer for App Store apps to receive configuration
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self getDeviceInfo:resolve rejecter:reject];
    });
}

RCT_EXPORT_METHOD(getDetailedDiagnostics:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"=== Getting Detailed Diagnostics ===");
    NSMutableDictionary *diagnostics = [NSMutableDictionary dictionary];
    
    // 1. Bundle Information
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *bundleInfo = [mainBundle infoDictionary];
    NSString *bundleID = [mainBundle bundleIdentifier];
    
    NSMutableDictionary *bundleDetails = [NSMutableDictionary dictionary];
    [bundleDetails setObject:bundleID ?: @"Unknown" forKey:@"bundleID"];
    [bundleDetails setObject:bundleInfo[@"CFBundleVersion"] ?: @"Unknown" forKey:@"version"];
    [bundleDetails setObject:bundleInfo[@"CFBundleShortVersionString"] ?: @"Unknown" forKey:@"shortVersion"];
    [bundleDetails setObject:bundleInfo[@"CFBundleDisplayName"] ?: @"Unknown" forKey:@"displayName"];
    [bundleDetails setObject:bundleInfo[@"TeamIdentifier"] ?: @"Unknown" forKey:@"teamID"];
    [bundleDetails setObject:@([bundleInfo objectForKey:@"NSSupportsAutomaticAppConfiguration"] != nil) forKey:@"supportsAutoConfig"];
    
    [diagnostics setObject:bundleDetails forKey:@"bundleInfo"];
    
    // 2. Provisioning Profile Analysis
    NSMutableDictionary *provisioningInfo = [NSMutableDictionary dictionary];
    NSString *provisioningPath = [mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
    
    if (provisioningPath) {
        NSData *provisioningData = [NSData dataWithContentsOfFile:provisioningPath];
        if (provisioningData) {
            NSString *provisioningString = [[NSString alloc] initWithData:provisioningData encoding:NSASCIIStringEncoding];
            
            BOOL isEnterprise = [provisioningString containsString:@"enterprise"];
            BOOL isAppStore = [provisioningString containsString:@"app-store"];
            BOOL isAdHoc = [provisioningString containsString:@"ad-hoc"];
            BOOL isVPP = [provisioningString containsString:@"B2B"] || 
                        [provisioningString containsString:@"VPP"] ||
                        [provisioningString containsString:@"volume-purchase"];
            BOOL isDevelopment = [provisioningString containsString:@"development"];
            
            
            [provisioningInfo setObject:@(isEnterprise) forKey:@"isEnterprise"];
            [provisioningInfo setObject:@(isAppStore) forKey:@"isAppStore"];
            [provisioningInfo setObject:@(isAdHoc) forKey:@"isAdHoc"];
            [provisioningInfo setObject:@(isVPP) forKey:@"isVPP"];
            [provisioningInfo setObject:@(isDevelopment) forKey:@"isDevelopment"];
            [provisioningInfo setObject:@"Found" forKey:@"status"];
            
            NSLog(@"📱 Provisioning Profile Analysis:");
            NSLog(@"  - Enterprise: %@", isEnterprise ? @"YES" : @"NO");
            NSLog(@"  - App Store: %@", isAppStore ? @"YES" : @"NO");
            NSLog(@"  - Ad Hoc: %@", isAdHoc ? @"YES" : @"NO");
            NSLog(@"  - VPP/B2B: %@", isVPP ? @"YES" : @"NO");
            NSLog(@"  - Development: %@", isDevelopment ? @"YES" : @"NO");
        } else {
            [provisioningInfo setObject:@"Found but unreadable" forKey:@"status"];
        }
    } else {
        [provisioningInfo setObject:@"Not found" forKey:@"status"];
        NSLog(@"❌ No provisioning profile found at path: %@", provisioningPath);
    }
    
    
    [diagnostics setObject:provisioningInfo forKey:@"provisioningProfile"];
    
    // 3. UserDefaults Analysis
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *userDefaultsInfo = [NSMutableDictionary dictionary];
    
    // Check all potential MDM keys
    NSArray *mdmKeys = @[
        @"com.apple.configuration.managed",
        [NSString stringWithFormat:@"com.apple.configuration.managed.%@", bundleID],
        @"com.apple.managed.configuration",
        @"IntuneMAMUPN",
        @"IntuneComplianceStatus",
        @"IntuneEnrollmentStatus",
        @"MCProfileUUID",
        @"MCProfileVersion",
        @"MCProfileIdentifier",
        @"CloudConfigurationUIComplete",
        @"SetupAssistantFinished"
    ];
    
    NSMutableDictionary *mdmKeysFound = [NSMutableDictionary dictionary];
    for (NSString *key in mdmKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            [mdmKeysFound setObject:value forKey:key];
            NSLog(@"✅ Found MDM key: %@ = %@", key, value);
        } else {
            NSLog(@"❌ Missing MDM key: %@", key);
        }
    }
    
    [userDefaultsInfo setObject:mdmKeysFound forKey:@"mdmKeys"];
    [userDefaultsInfo setObject:@([mdmKeysFound count]) forKey:@"mdmKeysCount"];
    
    // Get all UserDefaults keys for analysis
    NSDictionary *allDefaults = [defaults dictionaryRepresentation];
    NSMutableArray *relevantKeys = [NSMutableArray array];
    NSArray *searchTerms = @[@"managed", @"intune", @"config", @"apple", @"mdm", @"policy"];
    
    for (NSString *key in [allDefaults allKeys]) {
        for (NSString *term in searchTerms) {
            if ([key.lowercaseString containsString:term.lowercaseString]) {
                [relevantKeys addObject:@{@"key": key, @"value": [allDefaults objectForKey:key] ?: @"<null>"}];
                break;
            }
        }
    }
    
    [userDefaultsInfo setObject:relevantKeys forKey:@"relevantKeys"];
    [userDefaultsInfo setObject:@([allDefaults count]) forKey:@"totalKeys"];
    
    [diagnostics setObject:userDefaultsInfo forKey:@"userDefaults"];
    
    // 4. ManagedAppConfigSettings Analysis
    NSMutableDictionary *managedAppConfigInfo = [NSMutableDictionary dictionary];
    id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];
    
    if (appConfig && [appConfig count] > 0) {
        [managedAppConfigInfo setObject:appConfig forKey:@"config"];
        [managedAppConfigInfo setObject:@([appConfig count]) forKey:@"configCount"];
        [managedAppConfigInfo setObject:@"Available" forKey:@"status"];
        NSLog(@"✅ ManagedAppConfigSettings found: %@", appConfig);
    } else {
        [managedAppConfigInfo setObject:@"Not available" forKey:@"status"];
        [managedAppConfigInfo setObject:@0 forKey:@"configCount"];
        NSLog(@"❌ ManagedAppConfigSettings not available");
    }
    
    [diagnostics setObject:managedAppConfigInfo forKey:@"managedAppConfig"];
    
    // 5. Device Enrollment Detection
    NSMutableDictionary *enrollmentInfo = [NSMutableDictionary dictionary];
    NSArray *enrollmentKeys = @[
        @"MCProfileUUID", @"MCProfileVersion", @"MCProfileIdentifier",
        @"CloudConfigurationUIComplete", @"SetupAssistantFinished",
        @"DeviceManagementEnrollmentToken", @"MDMConfiguration",
        @"ServerCapabilities", @"DeviceTokenV2"
    ];
    
    BOOL deviceEnrolled = NO;
    NSMutableArray *foundEnrollmentKeys = [NSMutableArray array];
    
    // Check standard enrollment keys
    for (NSString *key in enrollmentKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            deviceEnrolled = YES;
            [foundEnrollmentKeys addObject:@{@"key": key, @"value": value}];
            NSLog(@"✅ Enrollment indicator: %@ = %@", key, value);
        }
    }
    
    // Check for Intune-specific enrollment
    if (!deviceEnrolled) {
        // Look for Intune Company Portal indicators
        NSArray *intuneKeys = @[@"IntuneEnrollmentId", @"IntuneDeviceId", @"IntuneUserPrincipalName"];
        for (NSString *key in intuneKeys) {
            id value = [defaults objectForKey:key];
            if (value) {
                deviceEnrolled = YES;
                [foundEnrollmentKeys addObject:@{@"key": key, @"value": value}];
                NSLog(@"✅ Intune enrollment indicator: %@ = %@", key, value);
            }
        }
    }
    
    
    [enrollmentInfo setObject:@(deviceEnrolled) forKey:@"isDeviceEnrolled"];
    [enrollmentInfo setObject:foundEnrollmentKeys forKey:@"enrollmentKeys"];
    
    [diagnostics setObject:enrollmentInfo forKey:@"enrollment"];
    
    // 6. Final Detection Logic Step-by-Step
    NSMutableDictionary *detectionSteps = [NSMutableDictionary dictionary];
    
    // Step 1: ManagedAppConfigSettings
    BOOL step1 = appConfig && [appConfig count] > 0;
    [detectionSteps setObject:@(step1) forKey:@"step1_managedAppConfig"];
    
    // Step 2: UserDefaults MDM keys
    BOOL step2 = [mdmKeysFound count] > 0;
    [detectionSteps setObject:@(step2) forKey:@"step2_userDefaultsMDM"];
    
    // Step 3: Device enrollment + auto config support
    BOOL supportsAutoConfig = [bundleInfo objectForKey:@"NSSupportsAutomaticAppConfiguration"] != nil;
    BOOL step3 = deviceEnrolled && supportsAutoConfig;
    [detectionSteps setObject:@(step3) forKey:@"step3_enrollmentAndAutoConfig"];
    
    // Step 4: Final decision
    BOOL isManaged = step1 || step2 || step3;
    [detectionSteps setObject:@(isManaged) forKey:@"finalDecision"];
    
    [diagnostics setObject:detectionSteps forKey:@"detectionSteps"];
    
    NSLog(@"=== Detection Steps Summary ===");
    NSLog(@"Step 1 (ManagedAppConfig): %@", step1 ? @"PASS" : @"FAIL");
    NSLog(@"Step 2 (UserDefaults MDM): %@", step2 ? @"PASS" : @"FAIL");
    NSLog(@"Step 3 (Enrollment + AutoConfig): %@", step3 ? @"PASS" : @"FAIL");
    NSLog(@"Final Decision: %@", isManaged ? @"MANAGED" : @"NOT MANAGED");
    
    resolve(diagnostics);
}

RCT_EXPORT_METHOD(isAppLockingAllowed: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);
    [self isASAMSupported:^(BOOL isSupported){
        dispatch_semaphore_signal(self.asamSem);
        resolve(@(isSupported));
    }];

}

RCT_EXPORT_METHOD(isAppLocked: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);
    [self isSAMEnabled:^(BOOL isEnabled) {
        dispatch_semaphore_signal(self.asamSem);
        resolve(@(isEnabled));
    }];
}

RCT_EXPORT_METHOD(lockApp: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAccessibilityRequestGuidedAccessSession(YES, ^(BOOL didSucceed) {
            dispatch_semaphore_signal(self.asamSem);
            if (didSucceed) {
                resolve(@(didSucceed));
            } else {
                reject(@"failed", @"Unable to lock app", nil);
            }
        });
    });
}

RCT_EXPORT_METHOD(unlockApp: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_semaphore_wait(self.asamSem, DISPATCH_TIME_FOREVER);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAccessibilityRequestGuidedAccessSession(NO, ^(BOOL didSucceed) {
            dispatch_semaphore_signal(self.asamSem);
            if (didSucceed) {
                resolve(@(didSucceed));
            } else {
                reject(@"failed", @"Unable to unlock app", nil);
            }
        });
    });
}

// Helper method to check if device is managed
- (BOOL)checkIfManagedDevice
{
    NSLog(@"=== App Store + Microsoft Intune Detection ===");
    BOOL isManaged = NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // 1. Primary Detection: Apple's Standard Managed Configuration Key
    id managedConfig = [defaults objectForKey:@"com.apple.configuration.managed"];
    if (managedConfig) {
        NSLog(@"✅ MANAGED: Found Apple standard managed configuration");
        return YES;
    }
    
    // 2. App-Specific Managed Configuration (Microsoft Intune)
    NSString *appSpecificKey = [NSString stringWithFormat:@"com.apple.configuration.managed.%@", bundleID];
    id appSpecificConfig = [defaults objectForKey:appSpecificKey];
    if (appSpecificConfig) {
        NSLog(@"✅ MANAGED: Found app-specific managed configuration for %@", bundleID);
        return YES;
    }
    
    // 3. ManagedAppConfigSettings Framework (iOS 11+)
    if (@available(iOS 11.0, *)) {
        id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];
        if (appConfig && [appConfig count] > 0) {
            NSLog(@"✅ MANAGED: Found ManagedAppConfigSettings configuration");
            return YES;
        }
    }
    
    // 4. Microsoft Intune Specific Keys
    NSArray *intuneKeys = @[@"IntuneMAMUPN", @"IntuneComplianceStatus", @"IntuneEnrollmentStatus"];
    for (NSString *key in intuneKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            NSLog(@"✅ MANAGED: Found Intune-specific key: %@", key);
            return YES;
        }
    }
    
    // 5. App Store + Intune Linking Detection (Production Workflow)
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *bundleInfo = [mainBundle infoDictionary];
    BOOL supportsAutoConfig = [bundleInfo objectForKey:@"NSSupportsAutomaticAppConfiguration"] != nil;
    
    if (supportsAutoConfig) {
        NSLog(@"📱 App supports automatic configuration - checking device enrollment");
        
        NSArray *enrollmentIndicators = @[
            @"CloudConfigurationUIComplete",
            @"MCProfileUUID",
            @"MCProfileVersion", 
            @"MCProfileIdentifier",
            @"DeviceManagementEnrollmentToken"
        ];
        
        for (NSString *key in enrollmentIndicators) {
            if ([defaults objectForKey:key]) {
                NSLog(@"✅ MANAGED: App Store app on enrolled device (Microsoft Intune standard)");
                
                // Try to trigger configuration refresh
                [[NSUserDefaults standardUserDefaults] synchronize];
                [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
                return YES;
            }
        }
        
        NSLog(@"❌ NOT MANAGED: Device not enrolled in MDM");
    } else {
        NSLog(@"❌ NOT MANAGED: App doesn't support automatic configuration");
    }
    
    NSLog(@"=== FINAL RESULT: NOT MANAGED ===");
    return NO;
}

// Helper method to check if downloaded from Intune
- (BOOL)checkIfDownloadedFromIntune
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *provisioningPath = [mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
    
    if (provisioningPath) {
        NSData *provisioningData = [NSData dataWithContentsOfFile:provisioningPath];
        if (provisioningData) {
            NSString *provisioningString = [[NSString alloc] initWithData:provisioningData encoding:NSASCIIStringEncoding];
            
            BOOL isEnterprise = [provisioningString containsString:@"enterprise"];
            BOOL isAppStore = [provisioningString containsString:@"app-store"];
            BOOL isVPP = [provisioningString containsString:@"B2B"] || 
                        [provisioningString containsString:@"VPP"] ||
                        [provisioningString containsString:@"volume-purchase"];
            
            
            // Downloaded from Intune: 
            // 1. Direct upload (!enterprise && !app-store) OR
            // 2. VPP/B2B app-store distribution
            BOOL downloadedFromIntune = !isEnterprise && (!isAppStore || isVPP);
            
            NSLog(@"📱 Intune detection - Enterprise: %d, AppStore: %d, VPP: %d, FromIntune: %d", 
                  isEnterprise, isAppStore, isVPP, downloadedFromIntune);
            
            return downloadedFromIntune;
        }
    }
    
    
    return NO;
}

// Helper method to get organization information
- (NSDictionary *)getOrganizationInformation
{
    NSMutableDictionary *orgInfo = [NSMutableDictionary dictionary];
    
    // 1. Try ManagedAppConfigSettings first
    id appConfig = [[ManagedAppConfigSettings clientInstance] appConfig];
    if (appConfig && [appConfig count] > 0) {
        [orgInfo addEntriesFromDictionary:appConfig];
    }
    
    // 2. Check UserDefaults for additional info
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    NSArray *configKeys = @[
        @"com.apple.configuration.managed",
        [NSString stringWithFormat:@"com.apple.configuration.managed.%@", bundleID],
        @"IntuneMAMUPN",
        @"IntuneComplianceStatus"
    ];
    
    for (NSString *key in configKeys) {
        id value = [defaults objectForKey:key];
        if (value) {
            if ([value isKindOfClass:[NSDictionary class]]) {
                [orgInfo addEntriesFromDictionary:value];
            } else {
                [orgInfo setObject:value forKey:key];
            }
        }
    }
    
    return orgInfo;
}

// Helper method to extract company domain
- (NSString *)extractCompanyDomainFromOrgInfo:(NSDictionary *)orgInfo
{
    // 1. Direct domain from configuration
    NSString *domain = orgInfo[@"AccountDomain"];
    if (domain) return domain;
    
    // 2. Extract from email
    NSString *email = orgInfo[@"AccountEmail"];
    if (email && [email containsString:@"@"]) {
        return [email componentsSeparatedByString:@"@"].lastObject;
    }
    
    // 3. Extract from Intune UPN
    NSString *upn = orgInfo[@"IntuneMAMUPN"];
    if (upn && [upn containsString:@"@"]) {
        return [upn componentsSeparatedByString:@"@"].lastObject;
    }
    
    return nil;
}

@end
