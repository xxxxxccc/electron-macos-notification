const path = require('path');
const fs = require('fs');

// Get Electron's module version (ABI)
const moduleVersion = process.versions.modules;
const platform = process.platform;
const arch = process.arch;

// Try to load from prebuilt binary first
const prebuiltPath = path.join(
  __dirname,
  'bin',
  `${platform}-${arch}-${moduleVersion}`,
  'electron-macos-notification.node'
);

// Fallback paths
const buildReleasePath = path.join(__dirname, 'build', 'Release', 'electron_native_mac_noti.node');
const buildDebugPath = path.join(__dirname, 'build', 'Debug', 'electron_native_mac_noti.node');

let nativeModule = null;

try {
  if (fs.existsSync(prebuiltPath)) {
    nativeModule = require(prebuiltPath);
  } else if (fs.existsSync(buildReleasePath)) {
    nativeModule = require(buildReleasePath);
  } else if (fs.existsSync(buildDebugPath)) {
    nativeModule = require(buildDebugPath);
  } else {
    // Fallback to bindings for other cases
    nativeModule = require('bindings')('electron_native_mac_noti');
  }
} catch (error) {
  console.error('[electron-macos-notification] Failed to load native module:', error.message);
  // Export stub module that returns safe defaults
  nativeModule = {
    isAvailable: () => false,
    requestPermission: () => Promise.resolve(false),
    getPermissionStatus: () => Promise.resolve('notDetermined'),
    showNotification: () => Promise.resolve({ success: false, error: 'Native module not available' }),
    removeNotification: () => {},
    removeAllNotifications: () => {},
  };
}

module.exports = nativeModule;
