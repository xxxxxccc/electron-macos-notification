# electron-macos-notification

Native macOS notification support for Electron with `contentImage` attachment support using `UNUserNotificationCenter`.

## Why?

Electron's built-in `Notification` API does not support `contentImage` (the image displayed alongside the notification). This module uses the native `UNUserNotificationCenter` API directly, enabling:

- Image attachments (`contentImage`) in notifications
- Click and dismiss event callbacks
- Permission management (`request` / `check` status)
- Foreground notification display
- Proper app icon and name

## Installation

Install directly from GitHub via SSH:

```bash
npm install git+ssh://git@github.com:xxxxxccc/electron-macos-notification.git
# or
pnpm add git+ssh://git@github.com:xxxxxccc/electron-macos-notification.git
```

Or add to `package.json` manually:

```json
{
  "dependencies": {
    "electron-macos-notification": "git+ssh://git@github.com:xxxxxccc/electron-macos-notification.git"
  }
}
```

> **Note:** This is a native addon that compiles from source during installation. Requires Xcode Command Line Tools on macOS.

### Build from source

```bash
git clone git@github.com:xxxxxccc/electron-macos-notification.git
cd electron-macos-notification
pnpm install
pnpm build
```

## Usage

> **Important:** This module only works on macOS. When used in a cross-platform Electron app, always check `process.platform` before importing to avoid loading the native binary on unsupported platforms. Use dynamic `import()` with a try-catch so that missing or incompatible modules fail gracefully.

### Basic

```typescript
if (process.platform === 'darwin') {
  try {
    const {
      showNotification,
      isAvailable,
      requestPermission,
    } = await import('electron-macos-notification');

    if (isAvailable()) {
      const granted = await requestPermission();

      if (granted) {
        const result = await showNotification({
          title: 'New Email',
          subtitle: 'From: John Doe',
          body: 'Hello, this is a test email.',
          contentImage: '/path/to/avatar.png', // optional
          sound: true,
        }, (event, userInfo) => {
          if (event === 'click') {
            console.log('Notification clicked!', userInfo);
          }
        });

        console.log('Notification shown:', result.success);
      }
    }
  } catch {
    // Module not available, fall back to Electron Notification API
  }
}
```

### Electron Integration with Fallback

In a real Electron app, you typically want to fall back to `Electron.Notification` when the native module is unavailable or permission is denied:

```typescript
import { Notification, BrowserWindow } from 'electron';

let nativeNoti: typeof import('electron-macos-notification') | null = null;

async function getNativeNotifier() {
  if (!nativeNoti) {
    try {
      nativeNoti = await import('electron-macos-notification');
    } catch {
      return null;
    }
  }
  return nativeNoti;
}

async function showAppNotification(data: {
  title: string;
  body?: string;
  subtitle?: string;
  imagePath?: string;
  userInfo?: string;
}) {
  const notifier = await getNativeNotifier();

  if (notifier?.isAvailable()) {
    // Check / request permission
    const status = await notifier.getPermissionStatus();
    if (status === 'notDetermined') {
      await notifier.requestPermission();
    }

    const result = await notifier.showNotification(
      {
        title: data.title,
        body: data.body,
        subtitle: data.subtitle,
        contentImage: data.imagePath,
        userInfo: data.userInfo,
        sound: true,
      },
      (event, userInfo) => {
        if (event === 'click') {
          // Bring window to front on click
          BrowserWindow.getAllWindows().forEach((win) => {
            if (win.isMinimized()) win.restore();
            win.show();
            win.focus();
          });
        }
      },
    );

    if (result.success) return;
  }

  // Fallback to Electron Notification
  new Notification({ title: data.title, body: data.body }).show();
}
```

## API

### `isAvailable(): boolean`

Returns `true` if native notifications are available (macOS only).

### `requestPermission(): Promise<boolean>`

Requests notification permission from the user. Returns `true` if granted.

### `getPermissionStatus(): Promise<'granted' | 'denied' | 'notDetermined'>`

Returns the current notification permission status.

### `showNotification(options, callback?): Promise<NotificationResult>`

Shows a notification with the given options.

**Options:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `title` | `string` | Yes | Notification title |
| `subtitle` | `string` | No | Notification subtitle |
| `body` | `string` | No | Notification body text |
| `contentImage` | `string` | No | Absolute path to image file for attachment |
| `identifier` | `string` | No | Custom notification identifier (auto-generated if omitted) |
| `userInfo` | `string` | No | Custom data passed back in the click callback |
| `sound` | `boolean` | No | Play notification sound (default: `true`) |

**Callback:**
- `event`: `'click'` or `'dismiss'`
- `userInfo`: The custom data string if provided

**Returns:** `Promise<NotificationResult>`

```typescript
interface NotificationResult {
  success: boolean;
  error?: string;
  identifier?: string;
}
```

### `removeNotification(identifier: string): void`

Removes a delivered notification by its identifier.

### `removeAllNotifications(): void`

Removes all delivered notifications.

## Packaging

When packaging your Electron app for the Mac App Store, the native addon's build artifacts (debug symbols, Makefiles, config files, etc.) may cause **MAS validation failures**. You need to clean them up before signing.

Here's an example using [Electron Forge](https://www.electronforge.io/) — add this to your `forge.config.ts` in a `packagerConfig.afterCopy` hook:

```typescript
import { join } from 'path'
import { existsSync, readdirSync, statSync, unlinkSync, rmdirSync } from 'fs'

// In packagerConfig.afterCopy:
async (buildPath: string) => {
  const notiPath = join(buildPath, 'node_modules', 'electron-macos-notification')
  if (!existsSync(notiPath)) return

  // Remove node-addon-api (not needed at runtime)
  const nodeAddonApiPath = join(notiPath, 'node-addon-api')
  if (existsSync(nodeAddonApiPath)) {
    rmdirSync(nodeAddonApiPath, { recursive: true })
  }

  // Remove dSYM debug symbols
  const dSYMPath = join(
    notiPath, 'build', 'Release',
    'electron_native_mac_noti.node.dSYM',
  )
  if (existsSync(dSYMPath)) {
    rmdirSync(dSYMPath, { recursive: true })
  }

  // Clean build directory — keep only .o, .node, .stamp files
  const buildDir = join(notiPath, 'build')
  if (existsSync(buildDir)) {
    const cleanBuildDir = (dir: string) => {
      for (const item of readdirSync(dir)) {
        const itemPath = join(dir, item)
        const stats = statSync(itemPath)
        if (stats.isDirectory()) {
          cleanBuildDir(itemPath)
          if (readdirSync(itemPath).length === 0) rmdirSync(itemPath)
        } else if (stats.isFile()) {
          const ext = item.split('.').pop()?.toLowerCase()
          if (ext !== 'o' && ext !== 'node' && ext !== 'stamp') {
            unlinkSync(itemPath)
          }
        }
      }
    }
    cleanBuildDir(buildDir)
  }
}
```

**What this cleans up and why:**

| Artifact | Reason to remove |
|----------|-----------------|
| `node-addon-api/` | Header files only needed at compile time, not at runtime |
| `*.dSYM` | Debug symbols inflate bundle size and are rejected by MAS |
| Makefiles, `config.gypi`, etc. | Build system files that trigger MAS validation errors |

Only `.o` (object), `.node` (native binary), and `.stamp` files are kept — these are required for the addon to function.

## Requirements

- macOS 10.14+ (Mojave)
- Xcode Command Line Tools
- Node.js 16+
- Electron 16+

## License

[MIT](LICENSE)
