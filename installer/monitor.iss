; installer/monitor.iss -- instalador Windows do Monitor Protheus (Inno Setup 6).
;
; Compilar:  ISCC.exe /DAppVersion=1.0.9 installer\monitor.iss
; Espera, ao lado deste .iss (na raiz do checkout): MonitorService.exe,
; MonitorTUI.exe, config.example.json, abrir-painel.bat.
;
; Instala em Program Files (precisa de admin uma vez, na instalacao) mas
; libera escrita pra Usuarios na pasta inteira -- o proprio monitor grava
; config.json/state.json/monitor.log ali, caminho relativo ao lado do
; .exe, e Program Files por padrao nao aceita escrita de usuario comum.
; Mesmo problema e mesma solucao ja usados no projeto irmao GesCon.

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

[Setup]
AppId={{A1B2C3D4-5E6F-4A7B-8C9D-0E1F2A3B4C5D}
AppName=Monitor Protheus
AppVersion={#AppVersion}
AppVerName=Monitor Protheus {#AppVersion}
AppPublisher=Monitor Protheus
DefaultDirName={autopf}\MonitorProtheus
DefaultGroupName=Monitor Protheus
OutputDir=.
OutputBaseFilename=Monitor-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayName=Monitor Protheus {#AppVersion}
UninstallDisplayIcon={app}\MonitorTUI.exe

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
Source: "..\MonitorService.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\MonitorTUI.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\config.example.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\abrir-painel.bat"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
; config.json/state.json/monitor.log sao escritos pelo proprio monitor
; direto nesta pasta -- sem isso, um usuario comum nao consegue gravar
; em Program Files depois da instalacao.
Name: "{app}"; Permissions: users-modify

[Icons]
Name: "{group}\Monitor Protheus"; Filename: "{app}\abrir-painel.bat"
Name: "{group}\Desinstalar o Monitor Protheus"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Monitor Protheus"; Filename: "{app}\abrir-painel.bat"

[Run]
Filename: "{app}\abrir-painel.bat"; Description: "Abrir o painel agora"; \
    Flags: nowait postinstall skipifsilent
