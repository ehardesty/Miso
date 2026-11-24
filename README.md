<img src="assets/MisoAppIcon.png" width="64" height="64" alt="">

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

The build script produces an Apple Silicon app and signs it ad hoc. Set `MISO_SIGN_IDENTITY` to use a local signing identity. macOS may require permissions again after an ad hoc rebuild. Local builds have updates disabled.

Open **Settings…** from the Miso menu bar item. In **Status**, grant Accessibility and Input Monitoring, then return to Miso and choose **Check Again**. Turn on **Start at Login** to launch Miso when you sign in. Use one remapping utility at a time when evaluating input.

In **Scrolling**, choose **macOS** to scale the native wheel response, **Fixed** for a steady distance per wheel step, or **Custom** to set the slow distance and fast-scroll boost independently. In Custom, set the estimated wheel rates where boost starts and reaches its cap, then choose a Gradual, Linear, or Quick ramp between them. Custom scales native scrolling when a wheel reports continuous motion or step data is unavailable. Apps determine how far a line moves. Trackpad and phased input keep their native behavior.

Each scrolling and pointer mode remembers its own tuning when you switch modes.

On the **Buttons & Gestures** page, choose **Press Button to Map…**, then press and release the mouse button you want to configure. Assign a Click action or a directional swipe in its editor. Left and right click remain available for normal use. Hold a mapped button while moving the mouse to run its assigned swipe action. You can assign your own keyboard shortcut per app when an app handles Back or Forward differently. The Spaces actions use the shortcuts enabled under **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**.

## Distribute a release

Release builds use Sparkle for **Check for Updates…**. Automatic checks are on by default and can be turned off in Status. Miso asks before installing.

Use a public GitHub repository with a stable name. Keep your Developer ID Application identity, `notarytool` Keychain profile, and a dedicated Sparkle update key on the Mac you use for releases. Create the Sparkle key once and keep an encrypted offline backup. Sparkle exports the private key as plaintext, so write the export directly to encrypted storage outside the repository. Keep the same bundle identifier, Developer ID team, and Sparkle key for subsequent builds.

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account miso
```

Set the version and increasing build number in `Scripts/Info.plist` and commit the release source. Set `MISO_SIGN_IDENTITY` and `MISO_NOTARY_PROFILE` in your release shell, then prepare the assets.

```sh
./Scripts/release.sh prepare OWNER/REPO
```

Preparation builds, signs, notarizes and staples the app before creating the ZIP and signed appcast. Subsequent releases check the build number, Sparkle key, and Developer ID team against the public Latest release.

### Stage and publish

Push the version tag at the commit used to prepare the assets, then stage a draft with the GitHub CLI authenticated.

```sh
./Scripts/release.sh stage OWNER/REPO
```

Pass `--initial` to both commands when creating the repository’s first Sparkle release. Staging verifies the tag, uploads both assets, and compares the downloaded draft files with the originals. If that comparison fails, leave the release unpublished. Remove the failed draft, keeping its tag, before staging again.

Publish the verified release as **Latest** and confirm its appcast and tagged ZIP download without authentication. Every release marked Latest needs both assets. Issue a higher build for corrections.

For Sparkle key rotation with verification before extraction, use Sparkle’s documented [Developer ID-signed DMG recovery path](https://sparkle-project.org/documentation/#rotating-signing-keys).

## Implementation

The app applies pointer settings on profile or device changes. Its dedicated input loop subscribes to wheel and button events when needed and enables motion observation only during a captured button interaction. Logitech commands run on separate queues. Miso writes a recovery record before temporarily taking over a Logitech control and checks the physical device identity and reporting state before restoring it.
