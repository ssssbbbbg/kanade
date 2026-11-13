; Inno Setup 安装包脚本，由 .github/workflows/release.yml 调用：
; ISCC /DAppVersion=1.0.0 /DSourceDir=... /DOutputDir=... /DOutputName=... kanade.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F1B2C4E-8A3D-4E5F-9B7C-2D1A0E3F4B5C}
AppName=Kanade
AppVersion={#AppVersion}
AppPublisher=LuckyLxi
AppPublisherURL=https://github.com/LuckyLxi/kanade
DefaultDirName={autopf}\Kanade
DefaultGroupName=Kanade
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\kanade.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Kanade"; Filename: "{app}\kanade.exe"; AppUserModelID: "LuckyLxi.Kanade"
Name: "{autodesktop}\Kanade"; Filename: "{app}\kanade.exe"; AppUserModelID: "LuckyLxi.Kanade"; Tasks: desktopicon

[Run]
Filename: "{app}\kanade.exe"; Description: "{cm:LaunchProgram,Kanade}"; Flags: nowait postinstall skipifsilent
; 应用内更新用 /SILENT 运行安装包，装完自动打开新版本
Filename: "{app}\kanade.exe"; Flags: nowait runasoriginaluser; Check: WizardSilent
