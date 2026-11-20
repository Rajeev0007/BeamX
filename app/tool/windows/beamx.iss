; BeamX Windows installer (Inno Setup 6). Built by .github/workflows/build.yml.
#define AppVersion GetEnv("BEAMX_VERSION")
#if AppVersion == ""
  #define AppVersion "0.0.0-dev"
#endif

[Setup]
AppId={{7E1B0C2A-4F3B-4C8E-9A51-B2E1D0F3BEA7}
AppName=BeamX
AppVersion={#AppVersion}
AppPublisher=Rajeev Development
AppCopyright=(C) 2026 Rajeev Development
VersionInfoCompany=Rajeev Development
VersionInfoCopyright=(C) 2026 Rajeev Development
VersionInfoProductName=BeamX
AppPublisherURL=https://github.com/Rajeev0007/BeamX
AppSupportURL=https://github.com/Rajeev0007/BeamX/issues
DefaultDirName={autopf}\BeamX
DisableProgramGroupPage=yes
OutputDir=..\..\..\dist
OutputBaseFilename=BeamX-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Admin is needed to install to Program Files and add the firewall rule.
PrivilegesRequired=admin
UninstallDisplayIcon={app}\beamx.exe
LicenseFile=..\..\..\LICENSE
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\BeamX"; Filename: "{app}\beamx.exe"
Name: "{autodesktop}\BeamX"; Filename: "{app}\beamx.exe"; Tasks: desktopicon

[Run]
; Allow BeamX on all network types: Windows 11 marks most Wi-Fi networks
; "Public", where a private-only rule silently blocked connections. Every
; connection still needs a pairing code, password or trust key.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""BeamX"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""BeamX"" dir=in action=allow program=""{app}\beamx.exe"" enable=yes profile=any"; Flags: runhidden
Filename: "{app}\beamx.exe"; Description: "{cm:LaunchProgram,BeamX}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""BeamX"""; Flags: runhidden; RunOnceId: "RemoveFirewallRule"
