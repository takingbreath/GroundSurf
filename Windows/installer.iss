#define AppVersion "0.1.0"
[Setup]
AppId={{990ED815-171C-45B3-A264-248BF24B3142}
AppName=GroundSurf
AppVersion={#AppVersion}
AppPublisher=Akhilesh Khajuria
AppPublisherURL=https://github.com/takingbreath/GroundSurf
DefaultDirName={localappdata}\Programs\GroundSurf
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.19041
OutputDir=..\dist
OutputBaseFilename=GroundSurf-Windows-{#AppVersion}-Setup-x64
SetupIconFile=GroundSurf.ico
UninstallDisplayIcon={app}\GroundSurf.exe
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
CloseApplicationsFilter=GroundSurf.exe
RestartApplications=no
WizardStyle=modern
LicenseFile=..\LICENSE

[Files]
Source: "..\dist\GroundSurf-Windows-{#AppVersion}-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "startup"; Description: "Start GroundSurf when I sign in"; Flags: unchecked

[Icons]
Name: "{autoprograms}\GroundSurf"; Filename: "{app}\GroundSurf.exe"
Name: "{autodesktop}\GroundSurf"; Filename: "{app}\GroundSurf.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "GroundSurf"; ValueData: """{app}\GroundSurf.exe"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\GroundSurf.exe"; Description: "Launch GroundSurf"; Flags: nowait postinstall skipifsilent

[Code]
function HasRuntimeAt(Root: Integer; Key: String): Boolean;
var Version: String;
begin
  Result := RegQueryStringValue(Root, Key, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0');
end;
function InitializeSetup(): Boolean;
var Key: String; ErrorCode: Integer;
begin
  Key := 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  Result := HasRuntimeAt(HKCU, Key) or HasRuntimeAt(HKLM64, Key) or HasRuntimeAt(HKLM32, Key);
  if not Result then begin
    if MsgBox('GroundSurf needs Microsoft Edge WebView2 Runtime. It is normally included with Windows 11. Open Microsoft''s official download page, install the Evergreen Runtime, then run this setup again?', mbConfirmation, MB_YESNO) = IDYES then
      ShellExec('open', 'https://developer.microsoft.com/microsoft-edge/webview2/', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;
end;
