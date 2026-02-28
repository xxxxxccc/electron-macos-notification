export interface NotificationOptions {
  /** Notification title */
  title: string;
  /** Notification subtitle (optional) */
  subtitle?: string;
  /** Notification body text */
  body?: string;
  /** Path to image file for contentImage (optional) */
  contentImage?: string;
  /** Custom identifier for the notification (optional) */
  identifier?: string;
  /** Custom data to pass back on click (optional) */
  userInfo?: string;
  /** Play sound (default: true) */
  sound?: boolean;
}

export interface NotificationResult {
  /** Whether the notification was shown successfully */
  success: boolean;
  /** Error message if failed */
  error?: string;
  /** Notification identifier */
  identifier?: string;
}

export type NotificationCallback = (event: 'click' | 'dismiss', userInfo?: string) => void;

/**
 * Show a native macOS notification with optional contentImage support
 * @param options Notification options
 * @param callback Optional callback for notification events (click/dismiss)
 * @returns Promise that resolves when notification is shown
 */
export function showNotification(
  options: NotificationOptions,
  callback?: NotificationCallback
): Promise<NotificationResult>;

/**
 * Check if native notifications are available on this platform
 * @returns true if on macOS 10.14+
 */
export function isAvailable(): boolean;

/**
 * Request notification permission from the user
 * @returns Promise that resolves to true if permission granted
 */
export function requestPermission(): Promise<boolean>;

/**
 * Check current notification permission status
 * @returns Promise that resolves to 'granted', 'denied', or 'notDetermined'
 */
export function getPermissionStatus(): Promise<'granted' | 'denied' | 'notDetermined'>;

/**
 * Remove a delivered notification by identifier
 * @param identifier The notification identifier
 */
export function removeNotification(identifier: string): void;

/**
 * Remove all delivered notifications
 */
export function removeAllNotifications(): void;
