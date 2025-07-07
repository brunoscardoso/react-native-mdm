declare module 'react-native-mdm' {
  import { EmitterSubscription } from 'react-native';

  // Simplified Organization Information interface
  export interface OrganizationInfo {
    AccountName?: string;
    AccountUserDisplayName?: string;
    AccountEmail?: string;
    AccountDomain?: string;
    UserGroupCode?: string;
    IntuneMAMUPN?: string;
    [key: string]: any;
  }

  // Main Device Management Information interface
  export interface DeviceManagementInfo {
    // Core Status
    isManaged: boolean;
    downloadedFromIntune: boolean;
    
    // Framework Support
    hasManagedConfigFramework: boolean;
    hasDeviceManagementFramework: boolean;
    hasProvisioningProfile: boolean;
    
    // Organization Information
    organizationInfo: OrganizationInfo;
    
    // Detected Domain
    companyDomain: string | null;
    
    // Bundle Information
    bundleID: string;
  }

  // Event listener callback type
  export type ConfigUpdateListener = (organizationInfo: OrganizationInfo) => void;

  // Simplified MobileDeviceManager interface
  interface MobileDeviceManager {
    // Main method - returns all essential information
    getDeviceInfo(): Promise<DeviceManagementInfo>;
    
    // Organization configuration only
    getOrganizationInfo(): Promise<OrganizationInfo>;
    
    // Force refresh of configuration
    refreshConfiguration(): Promise<DeviceManagementInfo>;
    
    // Event listener for configuration changes
    addConfigListener(callback: ConfigUpdateListener): EmitterSubscription;
    
    // Legacy support (deprecated but kept for compatibility)
    isSupported(): Promise<boolean>;
    getConfiguration(): Promise<OrganizationInfo>;
  }

  const MobileDeviceManager: MobileDeviceManager;
  export default MobileDeviceManager;
}