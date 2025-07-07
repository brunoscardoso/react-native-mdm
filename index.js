'use strict';

import {
  DeviceEventEmitter,
  NativeModules
} from 'react-native';

const {MobileDeviceManager} = NativeModules;

export default {
  // Main simplified methods
  getDeviceInfo: MobileDeviceManager.getDeviceInfo,
  getOrganizationInfo: MobileDeviceManager.getOrganizationInfo,
  refreshConfiguration: MobileDeviceManager.refreshConfiguration,
  
  // Simplified event listener
  addConfigListener (callback) {
    return DeviceEventEmitter.addListener(
      MobileDeviceManager.APP_CONFIG_CHANGED,
      callback
    );
  },
  
  // Legacy methods (deprecated but kept for compatibility)
  isSupported: MobileDeviceManager.isSupported,
  getConfiguration: MobileDeviceManager.getConfiguration,
  
  // Keep app lock methods if needed
  isAppLockingAllowed: MobileDeviceManager.isAppLockingAllowed,
  isAppLocked: MobileDeviceManager.isAppLocked,
  lockApp: MobileDeviceManager.lockApp,
  unlockApp: MobileDeviceManager.unlockApp,
  
  // Legacy event listeners (deprecated)
  addAppConfigListener (callback) {
    return DeviceEventEmitter.addListener(
      MobileDeviceManager.APP_CONFIG_CHANGED,
      callback
    );
  },
  addAppLockListener (callback) {
    return DeviceEventEmitter.addListener(
      MobileDeviceManager.APP_LOCK_STATUS_CHANGED,
      callback
    );
  }
};
