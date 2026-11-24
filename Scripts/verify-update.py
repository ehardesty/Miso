#!/usr/bin/env python3
"""Verify that Sparkle's generated feed describes the exact Miso release."""
import plistlib
import re
import sys
from pathlib import Path
from xml.etree import ElementTree
from zipfile import ZipFile

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def require(condition, message):
    if not condition:
        sys.exit(message)


def verify(archive, feed, repository, version, build, public_key):
    items = ElementTree.parse(feed).findall("./channel/item")
    require(len(items) == 1, "Expected one update in the generated appcast.")
    item = items[0]
    enclosure = item.find("enclosure")
    require(enclosure is not None, "Appcast has no download.")
    base_url = f"https://github.com/{repository}/releases"
    expected_url = f"{base_url}/download/v{version}/{archive.name}"
    require(enclosure.get("url") == expected_url, "Appcast download URL does not match the release tag and ZIP.")
    require(enclosure.get("length") == str(archive.stat().st_size), "Appcast download length does not match the ZIP.")
    signature = enclosure.get(SPARKLE + "edSignature")
    require(signature, "Appcast is missing the ZIP signature.")
    require(item.findtext(SPARKLE + "version") == build, "Appcast build number does not match the release.")
    require(item.findtext(SPARKLE + "shortVersionString") == version, "Appcast version does not match the release.")
    require(item.findtext(SPARKLE + "hardwareRequirements") == "arm64", "Appcast must require Apple Silicon.")

    with ZipFile(archive) as zipped:
        bundle = plistlib.loads(zipped.read("Miso.app/Contents/Info.plist"))
    require(bundle["CFBundleIdentifier"] == "dev.mousetweaks.MouseTweaks", "Unexpected Miso bundle identifier.")
    require(bundle["CFBundleVersion"] == build and bundle["CFBundleShortVersionString"] == version,
            "Packaged version or build does not match the release.")
    require(item.findtext(SPARKLE + "minimumSystemVersion") == bundle["LSMinimumSystemVersion"],
            "Appcast and bundle minimum macOS versions differ.")
    require(bundle.get("SUFeedURL") == f"{base_url}/latest/download/appcast.xml",
            "Bundle uses a different update feed.")
    require(bundle.get("SUPublicEDKey") == public_key, "Bundle uses a different Sparkle signing key.")
    require(bundle.get("SUVerifyUpdateBeforeExtraction") is True and bundle.get("SURequireSignedFeed") is True,
            "Bundle does not require signed updates and feeds.")
    print(signature)


def previous_release(feed, build, repository):
    items = ElementTree.parse(feed).findall("./channel/item")
    require(items, "The published appcast has no releases.")
    latest = max(items, key=lambda item: int(item.findtext(SPARKLE + "version")))
    require(int(build) > int(latest.findtext(SPARKLE + "version")),
            "The build number must exceed the published appcast.")
    enclosure = latest.find("enclosure")
    require(enclosure is not None, "Previous appcast has no download.")
    version = latest.findtext(SPARKLE + "shortVersionString")
    require(version and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version),
            "Previous appcast has an invalid release version.")
    url = f"https://github.com/{repository}/releases/download/v{version}/Miso-{version}-arm64.zip"
    require(enclosure.get("url") == url, "Previous appcast download does not match its release tag.")
    signature = enclosure.get(SPARKLE + "edSignature")
    require(signature, "Previous appcast is missing the ZIP signature.")
    print(url, signature, sep="\t")


if __name__ == "__main__":
    command, *args = sys.argv[1:]
    if command == "verify":
        archive, feed, *metadata = args
        verify(Path(archive), Path(feed), *metadata)
    elif command == "previous-release":
        previous_release(*args)
    else:
        sys.exit("Expected verify or previous-release.")
