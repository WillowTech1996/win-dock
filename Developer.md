
# Developer Guide

```
gem install xcpretty   # optional, prettier build output

! sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
! xcode-select -p
./build.sh
```

## Xcode Signing Setup (required for Accessibility permissions)

macOS tracks accessibility approvals by code signature. Without a stable signature, each rebuild is treated as a new app and the permission is lost.

1. Open `WinDock.xcodeproj` in Xcode
2. Select the **WinDock** target → **Signing & Capabilities**
3. Enable **Automatically manage signing**
4. Set **Team** to your Apple Developer account (a free Personal Team works). If Xcode reports no "Mac Development" certificate, create one under Xcode → Settings → Accounts → Manage Certificates → + → Apple Development.
5. The bundle ID is `WillowTech.WinDock`. Changing it or the signing identity means re-granting Accessibility.

Once configured, `build.sh` uses Xcode's signing automatically and accessibility approvals persist across rebuilds.

## Packaging

`./package.sh` builds Release, zips with `ditto`, and verifies the extracted copy with `codesign --verify --deep --strict`.
Never modify the `.app` after the build (for example copying files in): that invalidates the signature. Add resources to the `WinDock/` folder instead so Xcode bundles them.
