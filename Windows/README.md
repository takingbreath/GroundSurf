# GroundSurf for Windows

Standalone Windows system-tray app by Akhilesh Khajuria, using the same MIT-licensed generator, numeric commands, worker, and canvas renderer as the Mac version. Lively Wallpaper is not required.

## Architecture

The C# shell targets .NET Framework 4.8 and hosts WebView2 using the separately installed Evergreen Runtime. Both are normally present on Windows 11; the installer checks for WebView2 and directs the user to Microsoft's official download if it is missing. The app does not bundle another Chromium or a new .NET runtime. This keeps the download small, rather than guaranteeing low whole-process RAM.

There is one click-through desktop surface per monitor and a shared WebView2 environment. Native animation pulses run at about 30 Hz, with at most one outstanding call per surface. Pause, lock, display sleep, computer sleep, configured fullscreen rules, and optional battery rules stop the per-surface animation; when all surfaces are paused, the animation timer stops. A separate 1 Hz lifecycle check remains to detect fullscreen/battery state and broken desktop attachments. Paused artwork remains visible, with memory retained.

Preferences are stored under `%LOCALAPPDATA%\GroundSurf`. Start with Windows is off by default and uses a per-user Run entry when chosen. The app needs no administrator privileges and performs no wallpaper network requests. Microsoft's shared runtime can update independently.

Explorer provides no documented animated-wallpaper embedding API. `NativeDesktop.cs` isolates the classic WorkerW and current raised-desktop attachment paths. Attachment fails visibly if no suitable host exists. Window hierarchy recovery checks and display events rebuild surfaces as needed. Future Windows shell changes can need compatibility work.

## Build

On Windows, install the .NET SDK, Python 3, and Inno Setup, then run:

```powershell
./scripts/package-windows.ps1 -InnoCompiler 'C:\Path\To\ISCC.exe'
```

The source pins the WebView2 NuGet SDK. Output in `dist/` includes a portable x64 ZIP, per-user setup EXE, and SHA-256 hashes. The setup offers optional startup and desktop shortcuts and has a standard uninstaller.

## Validation and distribution

The Windows workflow compiles and executes the renderer on a Windows runner. Its smoke mode checks scene generation, scrolling, pause, overlapping sleep-state logic, and setup/uninstall. It reports whether a desktop host was available for a parent-attachment check. A WebView snapshot verifies that the artwork was actually painted. This is not a substitute for physical Windows 11 multi-monitor, DPI, lock/unlock, Explorer-restart, and battery testing.

The preview app and setup are not Authenticode signed; Windows may show an unknown-publisher or SmartScreen warning. Direct distribution does not require an Apple Developer membership or Lively. Signing and SmartScreen reputation are separate Windows distribution concerns.

Windows 11 x64 is the primary target. Windows 10 build 19041+ is targeted but needs broader validation. Windows on Arm is not yet a supported/tested target. Detailed limits are in Install.txt.
