package android.app.admin;
class DevicePolicyManager {
  int ACTION_START_ENCRYPTION;
  int ENCRYPTION_STATUS_ACTIVE;
  int ENCRYPTION_STATUS_ACTIVATING;
  int ENCRYPTION_STATUS_INACTIVE;
  int ENCRYPTION_STATUS_UNSUPPORTED;
  int WIPE_EXTERNAL_STORAGE;
  int RESET_PASSWORD_REQUIRE_ENTRY;
  int PASSWORD_QUALITY_COMPLEX;
  int PASSWORD_QUALITY_ALPHANUMERIC;
  int PASSWORD_QUALITY_ALPHABETIC;
  int PASSWORD_QUALITY_NUMERIC;
  int PASSWORD_QUALITY_SOMETHING;
  int PASSWORD_QUALITY_BIOMETRIC_WEAK;
  int PASSWORD_QUALITY_UNSPECIFIED;
  int ACTION_SET_NEW_PASSWORD;
  int EXTRA_ADD_EXPLANATION;
  int EXTRA_DEVICE_ADMIN;
  int ACTION_DEVICE_POLICY_MANAGER_STATE_CHANGED;
  int ACTION_ADD_DEVICE_ADMIN;
  int mService;
  int mContext;
  int TAG;
}
class DeviceAdminReceiver {
  int mWho;
  int mManager;
  int DEVICE_ADMIN_META_DATA;
  int ACTION_PASSWORD_EXPIRING;
  int ACTION_PASSWORD_SUCCEEDED;
  int ACTION_PASSWORD_FAILED;
  int ACTION_PASSWORD_CHANGED;
  int ACTION_DEVICE_ADMIN_DISABLED;
  int EXTRA_DISABLE_WARNING;
  int ACTION_DEVICE_ADMIN_DISABLE_REQUESTED;
  int ACTION_DEVICE_ADMIN_ENABLED;
  int localLOGV;
  int TAG;
}
class DeviceAdminInfo {
  int CREATOR;
  int mUsesPolicies;
  int mVisible;
  int mReceiver;
  int sRevKnownPolicies;
  int sKnownPolicies;
  int sPoliciesDisplayOrder;
  class PolicyInfo {
    int description;
    int label;
    int tag;
    int ident;
  }
  int USES_POLICY_DISABLE_CAMERA;
  int USES_ENCRYPTED_STORAGE;
  int USES_POLICY_EXPIRE_PASSWORD;
  int USES_POLICY_SETS_GLOBAL_PROXY;
  int USES_POLICY_WIPE_DATA;
  int USES_POLICY_FORCE_LOCK;
  int USES_POLICY_RESET_PASSWORD;
  int USES_POLICY_WATCH_LOGIN;
  int USES_POLICY_LIMIT_PASSWORD;
  int TAG;
}
