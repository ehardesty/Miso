<img src="assets/MisoAppIcon.png" width="64" height="64" alt="">

# Miso

Miso, short for Mouse Input & Scrolling Optimization, is a macOS menu bar app for tuning external mice. Adjust how the pointer moves, set how far each wheel scrolls, and assign shortcuts or gestures to mouse buttons. You can use different settings for each mouse or app. Miso can also change the sensor resolution (DPI) on supported Logitech mice, including the MX Master 3S and MX Master 4.

## Build and run Miso

Use an Apple Silicon Mac with macOS 14 or later and Xcode 16 or later. Run these commands from the repository root.

```sh
./Scripts/build-app.sh
open dist/Miso.app
```

1. Open **Settings…** from the Miso menu bar item.
2. In **Status**, click **Allow…** beside each missing permission. Miso needs **Accessibility** and **Input Monitoring**.
3. If macOS asks you to quit and reopen Miso, do that first. In **Status**, click **Check Again**.
4. To open Miso whenever you sign in, turn on **Start at Login**.

Use one mouse remapping utility at a time. macOS may ask for permissions again after an ad hoc rebuild. To keep the same signing identity across builds, set `MISO_SIGN_IDENTITY` before building.

## Tune your mouse

Use **Pointer** to set tracking speed and acceleration. For a mouse with adjustable DPI, use **Sensor Resolution** to change how far the pointer moves for the same physical movement.
Miso remembers the resolution after the mouse confirms your change. While Miso is enabled, it restores that resolution when the mouse reconnects.

In **Scrolling**, set the direction and **Wheel mode** for the vertical and horizontal wheels separately. Each mode remembers its settings when you switch away.

- **macOS** keeps the macOS scroll response and lets you adjust its speed.
- **Fixed** sets a steady distance per wheel step.
- **Custom** lets you set a distance for slow turns and add boost for faster turns. For a wheel Miso can measure, use **Scroll to test** to try the response.

Trackpad scrolling keeps its macOS behavior. If the wheel reports continuous movement or Miso can't read its individual steps, **Custom** uses **Slow scroll distance** to scale macOS scrolling.

## Use different settings for a mouse or app

Open the menu in the settings toolbar that shows **All Devices & Apps** or the current mouse or app. Select a mouse to change its settings, or choose **Add App…** to set overrides for an app. App overrides apply while that app is in front.

In an app's settings, turn on an **Override** switch to change that setting. Turn it off to use the mouse or **All Devices & Apps** setting again.

## Map buttons and gestures

1. In **Buttons & Gestures**, click **Press Button to Map…**.
2. Press and release a middle, side, or supported Logitech button. Left and right clicks keep their usual behavior.
3. Set **Click** for a press. To map a swipe, choose a direction such as **Hold and move left**.
4. Hold the button and move the mouse in the direction you mapped.

If an app uses its own Back or Forward keyboard shortcut, assign that shortcut in the app's button settings. To restore the mouse or default mapping, choose **Use inherited mapping**.

For **Previous Space** and **Next Space**, enable the shortcuts to move left and right between Spaces. Find them under **Mission Control** in macOS **Keyboard Shortcuts**.

## Check for updates

In a release build, choose **Check for Updates…** from the menu bar. Miso checks automatically by default and asks before installing. To turn off automatic checks, use **Automatically check for updates** in **Status**. Local builds have updates turned off.

## Publish a release

### Set up release signing

Use a public GitHub repository with a stable name for update downloads. Set up a Developer ID Application signing identity on your release Mac. If you need a notarization profile, run `notarytool` and follow its prompts.

```sh
xcrun notarytool store-credentials miso-notary
```

Create a dedicated Sparkle key once.

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account miso
```

The private key export is plaintext. To back it up, export directly to encrypted offline storage outside the repository.

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account miso -x /path/to/encrypted-storage/miso-key
```

Keep the bundle identifier, Developer ID team, and Sparkle key the same across releases. If you need to change the key, follow the [Sparkle key recovery instructions](https://sparkle-project.org/documentation/#rotating-signing-keys).

### Prepare a release

Set a three-part version and a higher integer build number in `Scripts/Info.plist`. Commit the changes. Replace `OWNER/REPO` with the public release repository and use your local signing identity and notarization profile name.

For the first Sparkle release in the repository, add `--initial` to both `prepare` and `stage`.

```sh
release_repo='OWNER/REPO'
export MISO_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAM_ID)'
export MISO_NOTARY_PROFILE='miso-notary'
swift test && ./Scripts/release.sh prepare "$release_repo"
```

The script signs and notarizes the app, then attaches the notarization ticket. It writes the ZIP and signed update feed, `appcast.xml`, to `dist/releases/VERSION`. To prepare the same unpublished version again, move that folder out of the way first.

### Stage a draft

Pushing a version tag to the public repository exposes the tagged source and its history. In the same shell, run these commands from the commit you used to prepare the release.

```sh
version="$(plutil -extract CFBundleShortVersionString raw Scripts/Info.plist)"
tag="v$version"
gh auth status || gh auth login
git tag "$tag"
git push "https://github.com/$release_repo.git" "refs/tags/$tag"
./Scripts/release.sh stage "$release_repo"
```

For later releases, the script checks the build number, Sparkle key, and Developer ID team against the current **Latest** release.

Staging checks that the uploaded files match your local copies. If the check fails after creating a draft, confirm the release is still a draft. Delete the draft and keep its tag, then run `stage` again.

```sh
gh release delete "$tag" --repo "$release_repo"
```

### Publish the draft

Publish the draft only after staging verifies both files. If a release marked **Latest** is missing either file, installed copies cannot update. Verify that both files download without signing in.

```sh
gh release edit "$tag" --repo "$release_repo" --draft=false --latest
curl -qfsSL -o /dev/null "https://github.com/$release_repo/releases/latest/download/appcast.xml"
curl -qfsSL -o /dev/null "https://github.com/$release_repo/releases/download/$tag/Miso-$version-arm64.zip"
```

To correct a published release, use a new version and a higher build number.
