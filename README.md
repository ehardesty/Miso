<img src="assets/icon.svg" width="64" height="64" alt="">

# Miso

Miso (Mouse Input & Scrolling Optimization) is a native macOS menu bar utility for tuning external mice, with HID++ support for the Logitech MX Master 3S and MX Master 4.

- Adjust pointer speed and acceleration using per-mouse macOS settings. Change hardware DPI directly when the mouse reports an adjustable sensor.
- Set speed, acceleration, and direction independently for the vertical and horizontal wheels. Wheel events are processed as they arrive. Smooth scrolling is outside this version.
- Remap buttons to clicks, shortcuts, navigation, or desktop actions. Assign a tap and up to four directional swipes on a held button.
- Edit settings globally, by mouse, or by the frontmost app. In an app profile, turn off an override or choose **Use inherited mapping** to return to the mouse or global setting.

## Run locally

Build with Xcode 16 or newer on macOS. The app targets macOS 14 and later.

```sh
swift test
./Scripts/build-app.sh
open dist/Miso.app
```

The build script signs the app ad hoc. Set `MISO_SIGN_IDENTITY` to use a local signing identity. macOS may require permissions again after an ad hoc rebuild.

Use **Status** to grant Accessibility and Input Monitoring, then return to Miso and choose **Check Again**. Use one remapping utility at a time when evaluating input. The menu bar item opens settings, pauses remapping, or quits the app.

For a predictable wheel distance, choose **Off** under the wheel’s acceleration setting. Miso uses raw HID counts for discrete mouse-wheel events when available. Continuous mouse-wheel input can retain the macOS acceleration curve. Trackpad and phased input keep their native behavior.

On the **Buttons & Gestures** page, choose **Press Button to Map…**, then press and release the mouse button you want to configure. Assign a Click action or a directional swipe in its editor. Left and right click remain available for normal use. Hold a mapped button while moving the mouse to run its assigned swipe action. You can assign your own keyboard shortcut per app when an app handles Back or Forward differently. The Spaces actions use the shortcuts enabled under **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**.

## Implementation

The app applies pointer settings on profile or device changes. Its dedicated input loop subscribes to wheel and button events when needed and enables motion observation only during a captured button interaction. Logitech commands run on separate queues. Miso writes a recovery record before temporarily taking over a Logitech control and checks the physical device identity and reporting state before restoring it.
