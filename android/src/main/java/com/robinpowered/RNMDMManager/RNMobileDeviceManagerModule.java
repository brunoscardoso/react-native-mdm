package com.robinpowered.RNMDMManager;

import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.Promise;

// For MDM
import android.app.Activity;
import android.app.admin.DevicePolicyManager;
import android.content.RestrictionsManager;
import android.app.ActivityManager;
import android.os.Bundle;
import android.os.Build;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.BroadcastReceiver;
import com.facebook.react.modules.core.DeviceEventManagerModule;
import com.facebook.react.bridge.WritableNativeMap;
import com.facebook.react.bridge.WritableNativeArray;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.Arguments;
import java.util.Map;
import java.util.HashMap;
import java.util.Set;
import java.util.ArrayList;
import java.util.List;
import javax.annotation.Nullable;
import android.content.pm.PackageManager;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.util.Log;

public class RNMobileDeviceManagerModule extends ReactContextBaseJavaModule implements LifecycleEventListener {
    public static final String MODULE_NAME = "MobileDeviceManager";
    private static final String TAG = "RNMobileDeviceManager";

    public static final String APP_CONFIG_CHANGED = "react-native-mdm/managedAppConfigDidChange";
    public static final String APP_LOCK_STATUS_CHANGED = "react-native-mdm/appLockStatusDidChange";

    private BroadcastReceiver restrictionReceiver;

    public RNMobileDeviceManagerModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    private void maybeUnregisterReceiver() {
        if (restrictionReceiver == null) {
            return;
        }

        getReactApplicationContext().unregisterReceiver(restrictionReceiver);

        restrictionReceiver = null;
    }

    private void maybeRegisterReceiver() {
        final ReactApplicationContext reactContext = getReactApplicationContext();

        if (restrictionReceiver != null || Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return;
        }

        final RestrictionsManager restrictionsManager = (RestrictionsManager) reactContext.getSystemService(Context.RESTRICTIONS_SERVICE);

        IntentFilter restrictionFilter = new IntentFilter(Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED);
        BroadcastReceiver restrictionReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                Bundle appRestrictions = restrictionsManager.getApplicationRestrictions();
                WritableNativeMap data = new WritableNativeMap();
                for (String key : appRestrictions.keySet()){
                    data.putString(key, appRestrictions.getString(key));
                }
                if (reactContext.hasActiveCatalystInstance()) {
                    reactContext
                            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                            .emit(APP_CONFIG_CHANGED, data);
                }
            }
        };
        reactContext.registerReceiver(restrictionReceiver,restrictionFilter);
    }

    public boolean enableLockState() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && !isLockState()) {
            Activity activity = getCurrentActivity();
            if (activity == null) {
                return false;
            }
            activity.startLockTask();
            return true;
        }
        return false;
    }

    public boolean disableLockState() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && isLockState()) {
            Activity activity = getCurrentActivity();
            if (activity == null) {
                return false;
            }
            activity.stopLockTask();
            return true;
        }
        return false;
    }

    public boolean isLockStatePermitted() {
        // lock state introduced in API 21 / Android 5.0 and up
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return false;
        }

        DevicePolicyManager dpm = (DevicePolicyManager)
                getReactApplicationContext().getSystemService(Context.DEVICE_POLICY_SERVICE);

        return dpm.isLockTaskPermitted(getReactApplicationContext().getPackageName());
    }

    public boolean isLockState() {
        // lock state introduced in API 21 / Android 5.0 and up
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return false;
        }

        ActivityManager am = (ActivityManager) getReactApplicationContext().getSystemService(Context.ACTIVITY_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return am.getLockTaskModeState() != ActivityManager.LOCK_TASK_MODE_NONE;
        } else {
            return am.isInLockTaskMode();
        }
    }

    @Override
    public String getName() {
        return MODULE_NAME;
    }

    @Override
    public @Nullable Map<String, Object> getConstants() {
        HashMap<String, Object> constants = new HashMap<String, Object>();
        constants.put("APP_CONFIG_CHANGED", APP_CONFIG_CHANGED);
        constants.put("APP_LOCK_STATUS_CHANGED", APP_LOCK_STATUS_CHANGED);
        return constants;
    }

    private boolean isMDMSupported() {
        // If app is running on any version that's older than lollipop, answer is no
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return false;
        }

        // Else, we look at restrictions manager and see if there's any app config settings in there
        RestrictionsManager restrictionsManager = (RestrictionsManager) getReactApplicationContext().getSystemService(Context.RESTRICTIONS_SERVICE);
        return restrictionsManager.getApplicationRestrictions().size() > 0;
    }

    @ReactMethod
    public void isSupported(final Promise promise) {
        promise.resolve(isMDMSupported());
    }

    @ReactMethod
    public void getConfiguration(final Promise promise) {
        if (isMDMSupported()) {
            RestrictionsManager restrictionsManager = (RestrictionsManager) getReactApplicationContext().getSystemService(Context.RESTRICTIONS_SERVICE);
            Bundle appRestrictions = restrictionsManager.getApplicationRestrictions();
            WritableNativeMap data = new WritableNativeMap();
            for (String key : appRestrictions.keySet()){
                data.putString(key, appRestrictions.getString(key));
            }
            promise.resolve(data);
        } else {
            // Return empty configuration instead of rejecting when MDM is not available
            promise.resolve(Arguments.createMap());
        }
    }

    @ReactMethod
    public void getDirectConfiguration(final Promise promise) {
        Log.d(TAG, "=== Direct Android MDM Check ===");
        WritableMap debugInfo = Arguments.createMap();
        
        RestrictionsManager restrictionsManager = (RestrictionsManager) getReactApplicationContext().getSystemService(Context.RESTRICTIONS_SERVICE);
        Bundle appRestrictions = restrictionsManager.getApplicationRestrictions();
        
        // Essential MDM configuration keys to check
        String[] potentialKeys = {
            "com.google.android.work.configuration.managed",
            "AccountName", "AccountDomain", "AccountEmail",
            "IntuneComplianceStatus", "IntuneEnrollmentStatus", 
            "IntuneMAMUPN", "ManagedConfiguration"
        };
        
        boolean foundMDMConfig = false;
        WritableMap mdmData = Arguments.createMap();
        
        for (String key : potentialKeys) {
            if (appRestrictions.containsKey(key)) {
                String value = appRestrictions.getString(key);
                if (value != null) {
                    Log.d(TAG, "✅ Found MDM key: " + key);
                    mdmData.putString(key, value);
                    foundMDMConfig = true;
                }
            }
        }
        
        // Look for essential keys only
        Set<String> allKeys = appRestrictions.keySet();
        WritableArray relevantKeys = Arguments.createArray();
        String[] searchTerms = {"managed", "intune", "mdm", "policy", "account"};
        
        for (String key : allKeys) {
            for (String term : searchTerms) {
                if (key.toLowerCase().contains(term.toLowerCase())) {
                    WritableMap keyData = Arguments.createMap();
                    keyData.putString("key", key);
                    keyData.putString("value", appRestrictions.getString(key, "<null>"));
                    relevantKeys.pushMap(keyData);
                    break;
                }
            }
        }
        
        debugInfo.putInt("TotalRestrictionsKeys", allKeys.size());
        debugInfo.putArray("RelevantKeys", relevantKeys);
        debugInfo.putBoolean("FoundMDMConfig", foundMDMConfig);
        debugInfo.putBoolean("HasRestrictionsManager", restrictionsManager != null);
        
        if (foundMDMConfig) {
            mdmData.putMap("_debugInfo", debugInfo);
            Log.d(TAG, "✅ MDM config found");
            promise.resolve(mdmData);
        } else {
            Log.d(TAG, "❌ No MDM config found");
            promise.resolve(debugInfo);
        }
    }

    @ReactMethod
    public void checkMDMCapabilities(final Promise promise) {
        Log.d(TAG, "=== Android MDM Capabilities Check ===");
        WritableMap essential = Arguments.createMap();
        
        Context context = getReactApplicationContext();
        
        // Essential framework checks
        RestrictionsManager restrictionsManager = (RestrictionsManager) context.getSystemService(Context.RESTRICTIONS_SERVICE);
        DevicePolicyManager devicePolicyManager = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
        
        essential.putBoolean("HasRestrictionsManager", restrictionsManager != null);
        essential.putBoolean("HasDevicePolicyManager", devicePolicyManager != null);
        essential.putBoolean("HasManagedConfigurationFramework", restrictionsManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP);
        essential.putBoolean("HasDeviceManagementFramework", devicePolicyManager != null);
        
        // Check if downloaded from managed source (work profile, enterprise, etc.)
        boolean downloadedFromIntune = false;
        boolean isWorkProfile = false;
        boolean isDeviceOwner = false;
        
        try {
            PackageManager pm = context.getPackageManager();
            ApplicationInfo appInfo = pm.getApplicationInfo(context.getPackageName(), 0);
            
            // Check if app is in work profile
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                isWorkProfile = (appInfo.flags & ApplicationInfo.FLAG_INSTALLED) != 0 && 
                               devicePolicyManager != null && 
                               !devicePolicyManager.getActiveAdmins().isEmpty();
            }
            
            // Check if device is managed
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                isDeviceOwner = devicePolicyManager != null && devicePolicyManager.isDeviceOwnerApp(context.getPackageName());
            }
            
            // App from Intune typically: work profile or device management
            downloadedFromIntune = isWorkProfile || isDeviceOwner || 
                                 (restrictionsManager != null && restrictionsManager.getApplicationRestrictions().size() > 0);
            
            essential.putBoolean("DownloadedFromIntune", downloadedFromIntune);
            essential.putBoolean("IsWorkProfile", isWorkProfile);
            essential.putBoolean("IsDeviceOwner", isDeviceOwner);
            
            Log.d(TAG, "📱 Download source - WorkProfile: " + isWorkProfile + ", DeviceOwner: " + isDeviceOwner + ", FromIntune: " + downloadedFromIntune);
            
        } catch (Exception e) {
            Log.e(TAG, "Error checking app source: " + e.getMessage());
            essential.putBoolean("DownloadedFromIntune", false);
            essential.putBoolean("IsWorkProfile", false);
            essential.putBoolean("IsDeviceOwner", false);
        }
        
        // Try to extract company domain from package info
        try {
            PackageManager pm = context.getPackageManager();
            PackageInfo packageInfo = pm.getPackageInfo(context.getPackageName(), PackageManager.GET_META_DATA);
            if (packageInfo.applicationInfo.metaData != null) {
                String companyDomain = packageInfo.applicationInfo.metaData.getString("CompanyDomain");
                if (companyDomain != null) {
                    essential.putString("CompanyDomain", companyDomain);
                }
            }
        } catch (Exception e) {
            Log.d(TAG, "No company domain in metadata");
        }
        
        Log.d(TAG, "✅ Essential capabilities checked");
        promise.resolve(essential);
    }

    @ReactMethod
    public void getEnrollmentStatus(final Promise promise) {
        Log.d(TAG, "=== Checking Android Device Enrollment Status ===");
        WritableMap enrollmentInfo = Arguments.createMap();
        
        Context context = getReactApplicationContext();
        DevicePolicyManager devicePolicyManager = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
        
        try {
            PackageManager pm = context.getPackageManager();
            PackageInfo packageInfo = pm.getPackageInfo(context.getPackageName(), 0);
            ApplicationInfo appInfo = pm.getApplicationInfo(context.getPackageName(), 0);
            
            enrollmentInfo.putString("BundleID", context.getPackageName());
            enrollmentInfo.putString("VersionName", packageInfo.versionName);
            enrollmentInfo.putInt("VersionCode", packageInfo.versionCode);
            
            // Check if device is managed/supervised
            boolean isSupervised = false;
            boolean hasSystemManagement = false;
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (devicePolicyManager != null) {
                    // Check if device has active device admin
                    List activeAdmins = devicePolicyManager.getActiveAdmins();
                    hasSystemManagement = activeAdmins != null && !activeAdmins.isEmpty();
                    
                    // Check if device is in supervised/kiosk mode
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        isSupervised = devicePolicyManager.isDeviceOwnerApp(context.getPackageName()) ||
                                     devicePolicyManager.isProfileOwnerApp(context.getPackageName());
                    }
                }
            }
            
            enrollmentInfo.putBoolean("IsSupervised", isSupervised);
            enrollmentInfo.putBoolean("HasSystemManagement", hasSystemManagement);
            
            // Check installation source
            String installerPackage = pm.getInstallerPackageName(context.getPackageName());
            boolean isEnterprise = installerPackage != null && 
                                  (installerPackage.contains("work") || 
                                   installerPackage.contains("enterprise") ||
                                   installerPackage.contains("intune"));
            boolean isPlayStore = "com.android.vending".equals(installerPackage);
            
            enrollmentInfo.putBoolean("IsEnterprise", isEnterprise);
            enrollmentInfo.putBoolean("IsPlayStore", isPlayStore);
            enrollmentInfo.putString("InstallerPackage", installerPackage != null ? installerPackage : "Unknown");
            
            // Check if app is in work profile
            boolean isInWorkProfile = false;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try {
                    // Try to detect work profile context
                    isInWorkProfile = (appInfo.flags & ApplicationInfo.FLAG_INSTALLED) != 0 && hasSystemManagement;
                } catch (Exception e) {
                    Log.d(TAG, "Could not determine work profile status");
                }
            }
            
            enrollmentInfo.putBoolean("IsInWorkProfile", isInWorkProfile);
            
            Log.d(TAG, "Enrollment info: " + enrollmentInfo.toString());
            
        } catch (Exception e) {
            Log.e(TAG, "Error getting enrollment status: " + e.getMessage());
            enrollmentInfo.putString("Error", e.getMessage());
        }
        
        promise.resolve(enrollmentInfo);
    }

    @ReactMethod
    public void forceMDMSync(final Promise promise) {
        Log.d(TAG, "=== Forcing Android MDM Sync and Deep Analysis ===");
        WritableMap syncResult = Arguments.createMap();
        
        Context context = getReactApplicationContext();
        RestrictionsManager restrictionsManager = (RestrictionsManager) context.getSystemService(Context.RESTRICTIONS_SERVICE);
        
        try {
            // Get package details
            PackageManager pm = context.getPackageManager();
            PackageInfo packageInfo = pm.getPackageInfo(context.getPackageName(), 0);
            
            syncResult.putString("ActualBundleID", context.getPackageName());
            syncResult.putString("VersionName", packageInfo.versionName);
            syncResult.putInt("VersionCode", packageInfo.versionCode);
            syncResult.putString("DisplayName", pm.getApplicationLabel(packageInfo.applicationInfo).toString());
            
            // Force refresh restrictions
            Bundle appRestrictions = restrictionsManager.getApplicationRestrictions();
            
            // Check for bundle-specific configuration
            String bundleSpecificKey = "managed." + context.getPackageName();
            boolean hasBundleSpecificConfig = appRestrictions.containsKey(bundleSpecificKey);
            syncResult.putBoolean("BundleSpecificConfig", hasBundleSpecificConfig);
            
            // Get fresh restrictions after potential sync
            WritableMap postRefreshFindings = Arguments.createMap();
            String[] targetKeys = {
                "com.google.android.work.configuration.managed",
                "com.android.managed.configuration",
                bundleSpecificKey,
                "IntuneMAM-" + context.getPackageName()
            };
            
            for (String key : targetKeys) {
                if (appRestrictions.containsKey(key)) {
                    String value = appRestrictions.getString(key);
                    if (value != null) {
                        postRefreshFindings.putString(key, value);
                        Log.d(TAG, "POST-REFRESH: Found " + key + " = " + value);
                    }
                }
            }
            syncResult.putMap("PostRefreshFindings", postRefreshFindings);
            
            // App domain data equivalent (restrictions data)
            WritableArray appDomainData = Arguments.createArray();
            WritableMap domainData = Arguments.createMap();
            domainData.putString("domain", context.getPackageName());
            
            WritableMap restrictionsData = Arguments.createMap();
            for (String key : appRestrictions.keySet()) {
                String value = appRestrictions.getString(key);
                if (value != null) {
                    restrictionsData.putString(key, value);
                }
            }
            domainData.putMap("data", restrictionsData);
            appDomainData.pushMap(domainData);
            syncResult.putArray("AppDomainData", appDomainData);
            
            // Refresh attempt status
            if (restrictionsManager != null) {
                syncResult.putString("RefreshAttempt", appRestrictions.size() > 0 ? "SUCCESS" : "NO_CONFIG");
            } else {
                syncResult.putString("RefreshAttempt", "NO_RESTRICTIONS_MANAGER");
            }
            
            Log.d(TAG, "Force sync result: " + syncResult.toString());
            
        } catch (Exception e) {
            Log.e(TAG, "Error in force sync: " + e.getMessage());
            syncResult.putString("RefreshAttempt", "FAILED: " + e.getMessage());
        }
        
        promise.resolve(syncResult);
    }

    @ReactMethod
    public void isAppLockingAllowed(final Promise promise) {
        promise.resolve(isLockStatePermitted());
    }

    @ReactMethod
    public void isAppLocked(final Promise promise) {
        try {
          promise.resolve(isLockState());
        } catch (Exception e) {
          promise.reject(e);
        }
    }

    @ReactMethod
    public void lockApp(final Promise promise) {
        try {
            boolean locked = enableLockState();
            if (locked) {
              promise.resolve(locked);
            } else {
              promise.reject(new Error("Unable to lock app"));
            }
        } catch (Exception e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void unlockApp(final Promise promise) {
        try {
            boolean unlocked = disableLockState();
            if (unlocked) {
              promise.resolve(unlocked);
            } else {
              promise.reject(new Error("Unable to unlock app"));
            }
        } catch (Exception e) {
            promise.reject(e);
        }
    }

    // Life cycle methods
    @Override
    public void initialize() {
        getReactApplicationContext().addLifecycleEventListener(this);
        maybeRegisterReceiver();
    }

    @Override
    public void onHostResume() {
        maybeRegisterReceiver();
    }

    @Override
    public void onHostPause() {
        maybeUnregisterReceiver();
    }

    @Override
    public void onHostDestroy() {
        maybeUnregisterReceiver();
        getReactApplicationContext().removeLifecycleEventListener(this);
    }
}
