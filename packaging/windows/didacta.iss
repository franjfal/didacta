; El instalador de Windows.
;
; Inno Setup y no un ZIP, ni un MSI, ni un MSIX. Las tres razones:
;
; * un ZIP deja a cada uno decidir dónde ponerlo, y entonces el actualizador
;   no sabe dónde está. Un instalador de verdad lo registra;
; * un MSI necesita administrador para casi todo, y esto no lo necesita;
; * un MSIX pide firma **obligatoriamente** para poder instalarse. Hoy todavía
;   no hay certificado, y un formato que no se puede instalar sin él dejaría a
;   Windows sin versión hasta que lo haya.
;
; Y sobre todo: **se instala por usuario, sin administrador.**
; `PrivilegesRequired=lowest` manda a `%LOCALAPPDATA%\Programs\Didacta`, que es
; donde alguien puede instalar y actualizar sin pedirle permiso a nadie. Es lo
; que hacen VS Code y Chrome, y es lo que permite que el actualizador ejecute
; el instalador en silencio sin un diálogo de UAC en mitad de la clase.
;
; Se compila con:
;   iscc /DDidactaVersion=1.4.2 /DDidactaSource=..\..\app\build\windows\x64\runner\Release packaging\windows\didacta.iss

#ifndef DidactaVersion
  #error Falta /DDidactaVersion=X.Y.Z
#endif
#ifndef DidactaSource
  #error Falta /DDidactaSource=<carpeta con didacta.exe>
#endif
#ifndef DidactaOutput
  #define DidactaOutput "dist"
#endif
#ifndef DidactaIcon
  #define DidactaIcon "..\\..\\app\\windows\\runner\\resources\\app_icon.ico"
#endif

[Setup]
; El AppId identifica **el producto**, no la versión: tiene que ser el mismo
; para siempre, porque es lo que hace que instalar la 1.4.2 encima de la 1.4.1
; sea una actualización y no una segunda copia.
AppId={{8E4A2F31-6C5D-4B77-9A18-7D3E5C0B2A94}
AppName=Didacta
AppVersion={#DidactaVersion}
AppVerName=Didacta {#DidactaVersion}
AppPublisher=Universitat de València
AppPublisherURL=https://github.com/franjfal/didacta_public
DefaultDirName={autopf}\Didacta
DefaultGroupName=Didacta
DisableProgramGroupPage=yes
DisableDirPage=auto
; Sin administrador. `autopf` con privilegios mínimos resuelve a
; %LOCALAPPDATA%\Programs, que es donde se puede escribir sin UAC.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; `x64` y no `x64compatible`: el segundo solo existe desde Inno Setup 6.3, y
; en una 6.2 es un error de compilación, no un aviso. `x64` lo entienden todas
; las 6.x --las nuevas lo traducen solas-- y la versión que trae la imagen del
; runner no es algo que aquí se controle.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

OutputDir={#DidactaOutput}
OutputBaseFilename=Didacta-{#DidactaVersion}-windows-x64
SetupIconFile={#DidactaIcon}
UninstallDisplayIcon={app}\didacta.exe
UninstallDisplayName=Didacta
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; Lo que hace posible actualizar sin pedir nada: si Didacta está abierta, el
; instalador la cierra usando el Restart Manager de Windows en vez de fallar
; con «el fichero está en uso». `RestartApplications=no` porque de relanzarla
; se encarga el script del actualizador, que sabe si hay que hacerlo.
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Todo lo que deja `flutter build windows`: el ejecutable, las DLL del motor,
; los plugins y `data\`. Recursivo a propósito -- enumerar los ficheros a mano
; es cómo se publica una versión a la que le falta un plugin nuevo.
Source: "{#DidactaSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Didacta"; Filename: "{app}\didacta.exe"
Name: "{autodesktop}\Didacta"; Filename: "{app}\didacta.exe"; Tasks: desktopicon

[Run]
; Solo cuando alguien lo instala a mano. En una actualización el instalador va
; con /SILENT, y entonces quien relanza es el script del actualizador.
Filename: "{app}\didacta.exe"; Description: "{cm:LaunchProgram,Didacta}"; Flags: nowait postinstall skipifsilent
