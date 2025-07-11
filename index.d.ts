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

  // Detailed diagnostics interface
  export interface DetailedDiagnostics {
    bundleInfo: {
      bundleID: string;
      version: string;
      shortVersion: string;
      displayName: string;
      teamID: string;
      supportsAutoConfig: boolean;
    };
    provisioningProfile: {
      status: string;
      isEnterprise?: boolean;
      isAppStore?: boolean;
      isAdHoc?: boolean;
      isVPP?: boolean;
      isDevelopment?: boolean;
    };
    userDefaults: {
      mdmKeys: { [key: string]: any };
      mdmKeysCount: number;
      relevantKeys: Array<{ key: string; value: any }>;
      totalKeys: number;
    };
    managedAppConfig: {
      status: string;
      config?: any;
      configCount: number;
    };
    enrollment: {
      isDeviceEnrolled: boolean;
      enrollmentKeys: Array<{ key: string; value: any }>;
    };
    detectionSteps: {
      step1_managedAppConfig: boolean;
      step2_userDefaultsMDM: boolean;
      step3_enrollmentAndAutoConfig: boolean;
      finalDecision: boolean;
    };
  }

  // Simplified MobileDeviceManager interface
  interface MobileDeviceManager {
    // Main method - returns all essential information
    getDeviceInfo(): Promise<DeviceManagementInfo>;
    
    // Organization configuration only
    getOrganizationInfo(): Promise<OrganizationInfo>;
    
    // Force refresh of configuration
    refreshConfiguration(): Promise<DeviceManagementInfo>;
    
    // Get detailed diagnostics for debugging
    getDetailedDiagnostics(): Promise<DetailedDiagnostics>;
    
    // Event listener for configuration changes
    addConfigListener(callback: ConfigUpdateListener): EmitterSubscription;
    
    // Legacy support (deprecated but kept for compatibility)
    isSupported(): Promise<boolean>;
    getConfiguration(): Promise<OrganizationInfo>;
  }

  const MobileDeviceManager: MobileDeviceManager;
  export default MobileDeviceManager;
}