[Setup]
AppId={{85BDD6FC-FE10-47E8-90CA-DCE6566CA11B}
AppName=ZEDP-RTL
AppVersion={#ProductVersion}
AppPublisher=ZEDP-RTL contributors
DefaultDirName={localappdata}\Programs\ZEDP-RTL
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\ZEDP-RTL.exe
OutputBaseFilename=ZEDP-RTL-{#ProductVersion}-x64
Compression=lzma2/fast
SolidCompression=yes
DisableProgramGroupPage=yes
CloseApplications=yes

[Files]
Source: "{#Payload}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{userprograms}\ZEDP-RTL"; Filename: "{app}\ZEDP-RTL.exe"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\zedp.exe"; ValueType: string; ValueName: ""; ValueData: "{app}\bin\zedp.exe"; Flags: uninsdeletekey

[Run]
Filename: "{app}\ZEDP-RTL.exe"; Description: "Open ZEDP-RTL"; Flags: nowait postinstall skipifsilent
