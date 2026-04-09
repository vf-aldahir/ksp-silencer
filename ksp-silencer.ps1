#Requires -RunAsAdministrator

# =============================================================
# ksp-silencer.ps1
#
# Descripcion:
#   Aplica configuracion de silencio total a Kaspersky Endpoint
#   Security. Detiene toda notificacion, popup y ventana de la
#   interfaz grafica sin afectar la proteccion en segundo plano.
#
#   El script descarga dos archivos desde el repositorio:
#     - silencer.cfg : perfil de Kaspersky con forceSilentMode
#                      activado en todos los modulos
#     - silencer.reg : claves de registro de Windows que
#                      complementan el silencio a nivel sistema
#
#   Adicionalmente registra cada ejecucion en:
#     - Log local  : C:\ProgramData\KspSilencer\log.csv
#     - Log remoto : endpoint HTTP en VPS (si esta configurado)
#
# Desarrollado por:
#   Daniel Medero y Aldahir Sanchez
#   Departamento de TI - Colegio Viktor Frankl, Queretaro
#
# Uso:
#   Abrir CMD como administrador y ejecutar:
#   powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/vf-aldahir/ksp-silencer/main/ksp-silencer.ps1 | iex"
# =============================================================

# ---- CONFIGURACION ------------------------------------------
$REPO_BASE  = "https://raw.githubusercontent.com/vf-aldahir/ksp-silencer/main"
$CFG_URL    = "$REPO_BASE/silencer.cfg"
$REG_URL    = "$REPO_BASE/silencer.reg"
$LOG_VPS    = "https://aldahir.dev/ksp-log"
$LOG_RED    = ""
# -------------------------------------------------------------

$VERSION   = "1.0"
$MACHINE   = $env:COMPUTERNAME
$USER_NAME = $env:USERNAME
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$TEMP_DIR  = "$env:TEMP\ksp_silencer"


# =============================================================
# BLOQUE: Funciones de interfaz CLI
# =============================================================
# Prefijos fijos para mantener alineacion en todas las lineas:
#   "  [ X/X ]  Texto..."   <- paso numerado
#   "        OK  Texto"     <- exito
#   "        **  Texto"     <- aviso
#   "        --  Texto"     <- informativo

function Show-Banner {
    # Muestra el encabezado con ASCII art y datos del equipo.
    # Ancho de 64 caracteres para caber en CMD de 80 columnas.
    Clear-Host
    Write-Host ""
    Write-Host "  ################################################################" -ForegroundColor Cyan
    Write-Host "  ##                                                            ##" -ForegroundColor Cyan
    Write-Host "  ##   _  _____ ___     ___ _ _    ___ _  _  ___ ___ ___       ##" -ForegroundColor Cyan
    Write-Host "  ##  | |/ / __| _ \   / __| | |  | __| \| |/ __| __| _ \      ##" -ForegroundColor Cyan
    Write-Host "  ##  | ' <\__ \  _/   \__ \ | |__| _|| .` | (__| _||   /      ##" -ForegroundColor Cyan
    Write-Host "  ##  |_|\_\___/_|     |___/_|____|___|_|\_|\___|___|_|_\      ##" -ForegroundColor Cyan
    Write-Host "  ##                                                            ##" -ForegroundColor Cyan
    Write-Host "  ##   Configurador de silencio para Kaspersky Endpoint Sec.   ##" -ForegroundColor Cyan
    Write-Host "  ##                                                            ##" -ForegroundColor DarkCyan
    Write-Host "  ##   Desarrollado por  Daniel Medero  &  Aldahir Sanchez     ##" -ForegroundColor DarkCyan
    Write-Host "  ##   TI - Colegio Viktor Frankl  //  Queretaro, Mexico       ##" -ForegroundColor DarkCyan
    Write-Host "  ##                                                    v$VERSION   ##" -ForegroundColor DarkCyan
    Write-Host "  ################################################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Equipo  : $MACHINE"   -ForegroundColor White
    Write-Host "  Usuario : $USER_NAME" -ForegroundColor White
    Write-Host "  Fecha   : $TIMESTAMP" -ForegroundColor White
    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
}

function Write-Step {
    # Encabezado de paso numerado. Siempre con linea en blanco arriba.
    param([string]$Number, [string]$Text)
    Write-Host ""
    Write-Host "  [ $Number ]  $Text" -ForegroundColor Yellow
}

function Write-Success {
    # Confirmacion de operacion exitosa.
    param([string]$Text)
    Write-Host "        OK  $Text" -ForegroundColor Green
}

function Write-Warn {
    # Aviso no critico.
    param([string]$Text)
    Write-Host "        **  $Text" -ForegroundColor Yellow
}

function Write-Info {
    # Informacion de contexto sin implicacion de resultado.
    param([string]$Text)
    Write-Host "        --  $Text" -ForegroundColor DarkGray
}

function Write-Divider {
    # Separador visual entre secciones.
    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Exit-Script {
    # Pausa antes de cerrar para que el usuario lea el resultado.
    param([int]$Code = 0)
    Write-Host ""
    Write-Host "  Presiona cualquier tecla para cerrar..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit $Code
}


# =============================================================
# BLOQUE: Deteccion de Kaspersky
# =============================================================

function Get-KasperskyInstall {
    # Busca avp.com en las rutas estandar de Program Files.
    # Retorna hashtable con Found, Version, AvpCom, AvpExe.

    $result = @{ Found = $false; Version = "Desconocida"; AvpCom = $null; AvpExe = $null }

    foreach ($base in @("C:\Program Files\Kaspersky Lab", "C:\Program Files (x86)\Kaspersky Lab")) {
        if (-not (Test-Path $base)) { continue }
        foreach ($dir in (Get-ChildItem $base -Directory -ErrorAction SilentlyContinue)) {
            $avp_com = Join-Path $dir.FullName "avp.com"
            $avp_exe = Join-Path $dir.FullName "avp.exe"
            if (Test-Path $avp_com) {
                $result.Found  = $true
                $result.AvpCom = $avp_com
                $result.AvpExe = $avp_exe
                try {
                    $info = (Get-Item $avp_exe -ErrorAction SilentlyContinue).VersionInfo
                    if ($info) { $result.Version = $info.ProductVersion }
                } catch {}
                break
            }
        }
        if ($result.Found) { break }
    }
    return $result
}

function Test-SilenceAlreadyApplied {
    # Revisa 3 claves de registro. Si 2+ coinciden, el equipo
    # ya tiene la configuracion aplicada y no se repite el proceso.

    $hits = 0
    $k1 = Get-ItemProperty "HKLM:\SOFTWARE\KasperskyLab\KES\settings" -Name "SilentMode" -ErrorAction SilentlyContinue
    if ($k1 -and $k1.SilentMode -eq 1) { $hits++ }
    $k2 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\KasperskyLab\KES\settings" -Name "SilentMode" -ErrorAction SilentlyContinue
    if ($k2 -and $k2.SilentMode -eq 1) { $hits++ }
    $k3 = Get-ItemProperty "HKLM:\SOFTWARE\KasperskyLab\KES\settings\Notifications" -Name "EnableNotifications" -ErrorAction SilentlyContinue
    if ($k3 -and $k3.EnableNotifications -eq 0) { $hits++ }
    return ($hits -ge 2)
}


# =============================================================
# BLOQUE: Descarga de archivos
# =============================================================

function Get-RemoteFile {
    # Descarga un archivo desde URL a disco local.
    # Usa WebClient para compatibilidad con PowerShell v3+.
    # Retorna $true si exitoso, $false si fallo.

    param([string]$Url, [string]$Destination)
    try {
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($Url, $Destination)
        return $true
    } catch {
        return $false
    }
}


# =============================================================
# BLOQUE: Aplicacion de configuracion
# =============================================================

function Apply-RegistryFile {
    # Aplica un .reg con regedit /s (silencioso, sin dialogos).
    # Retorna $true si regedit termino con codigo 0.

    param([string]$RegFile)
    try {
        $proc = Start-Process "regedit.exe" -ArgumentList "/s `"$RegFile`"" -Wait -PassThru -WindowStyle Hidden
        return ($proc.ExitCode -eq 0)
    } catch { return $false }
}

function Apply-KasperskyCfg {
    # Importa el perfil .cfg via avp.com con ventana VISIBLE.
    #
    # Se abre en ventana visible (no Hidden) para que el usuario
    # pueda responder si Kaspersky solicita confirmacion o la
    # contrasena del administrador de proteccion.
    #
    # El script pausa y avisa al usuario antes de abrir la ventana.
    # Si avp.com termina con codigo 0, la importacion fue exitosa.

    param([string]$AvpCom, [string]$CfgFile)
    try {
        Write-Host ""
        Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  Se abrira una ventana de Kaspersky para importar el perfil." -ForegroundColor White
        Write-Host "  Si aparece confirmacion o contrasena, acepta para continuar." -ForegroundColor White
        Write-Host "  Cuando termine, esta ventana continuara automaticamente." -ForegroundColor White
        Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Presiona cualquier tecla para abrir la ventana de Kaspersky..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Write-Host ""

        $proc = Start-Process $AvpCom -ArgumentList "IMPORT `"$CfgFile`"" -Wait -PassThru
        return ($proc.ExitCode -eq 0)
    } catch { return $false }
}

function Stop-KasperskyUI {
    # Termina procesos de UI de Kaspersky antes de aplicar cambios.
    # El servicio AVP (proteccion real) NO se detiene aqui.

    foreach ($proc in @("avpui","kavtray","ksde","kisui","kav","klwtblfs")) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
    }
}

function Restart-KasperskyService {
    # Reinicia AVP y klnagent para cargar la nueva configuracion.
    # Espera 3 segundos entre stop y start.

    Stop-Service  "AVP"      -Force -ErrorAction SilentlyContinue
    Stop-Service  "klnagent" -Force -ErrorAction SilentlyContinue
    Start-Sleep   3
    Start-Service "AVP"      -ErrorAction SilentlyContinue
    Start-Service "klnagent" -ErrorAction SilentlyContinue
}


# =============================================================
# BLOQUE: Sistema de logs
# =============================================================

function Write-EventLog {
    # Guarda el evento en hasta tres destinos:
    #   1. LOCAL : C:\ProgramData\KspSilencer\log.csv (siempre)
    #   2. RED   : carpeta compartida (si $LOG_RED != "")
    #   3. VPS   : POST JSON al servidor (si $LOG_VPS != "")
    #
    # El campo $Detail debe contener el resultado de cada sub-paso
    # para que el log refleje exactamente que ocurrio en el equipo.

    param([string]$Status, [string]$Version, [string]$Detail = "")

    $log_line = "$TIMESTAMP,$MACHINE,$USER_NAME,$Status,$Version,`"$Detail`""

    $local_file = "$env:ProgramData\KspSilencer\log.csv"
    $local_dir  = Split-Path $local_file
    if (-not (Test-Path $local_dir)) { New-Item -ItemType Directory $local_dir -Force | Out-Null }
    if (-not (Test-Path $local_file)) { Add-Content $local_file "Fecha,Equipo,Usuario,Estado,VersionKSP,Detalle" }
    Add-Content $local_file $log_line

    if ($script:LOG_RED -ne "") {
        try {
            if (-not (Test-Path $script:LOG_RED)) { Add-Content $script:LOG_RED "Fecha,Equipo,Usuario,Estado,VersionKSP,Detalle" }
            Add-Content $script:LOG_RED $log_line
        } catch {}
    }

    if ($script:LOG_VPS -ne "") {
        try {
            $payload = @{ equipo=$MACHINE; usuario=$USER_NAME; estado=$Status; version=$Version; detalle=$Detail } | ConvertTo-Json
            Invoke-RestMethod -Uri $script:LOG_VPS -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 8 | Out-Null
        } catch {}
    }
}


# =============================================================
# EJECUCION PRINCIPAL
# =============================================================

Show-Banner

# -- Paso 1: Detectar Kaspersky -------------------------------
Write-Step "1/5" "Buscando instalacion de Kaspersky..."

$ksp = Get-KasperskyInstall

if (-not $ksp.Found) {
    Write-Warn "Kaspersky no fue encontrado en este equipo."
    Write-EventLog -Status "ERROR" -Version "N/A" -Detail "Kaspersky no instalado"
    Write-Host ""
    Write-Host "  No hay nada que configurar en este equipo." -ForegroundColor Yellow
    Exit-Script 1
}

Write-Success "Kaspersky encontrado - Version: $($ksp.Version)"
Write-Info    "Ruta: $($ksp.AvpCom)"


# -- Paso 2: Verificar configuracion actual -------------------
Write-Step "2/5" "Verificando configuracion actual..."

if (Test-SilenceAlreadyApplied) {
    Write-Success "Este equipo ya tiene la configuracion de silencio aplicada."
    Write-Info    "No se realizaran cambios."
    Write-EventLog -Status "YA_APLICADO" -Version $ksp.Version -Detail "Configuracion detectada, sin cambios"
    Write-Divider
    Write-Host "  Kaspersky ya corre en segundo plano sin notificaciones." -ForegroundColor Green
    Exit-Script 0
}

Write-Warn "Configuracion de silencio no detectada. Continuando..."


# -- Paso 3: Descargar archivos -------------------------------
Write-Step "3/5" "Descargando archivos de configuracion..."

if (-not (Test-Path $TEMP_DIR)) { New-Item -ItemType Directory $TEMP_DIR -Force | Out-Null }

$cfg_dest = "$TEMP_DIR\silencer.cfg"
$reg_dest = "$TEMP_DIR\silencer.reg"
$cfg_ok   = Get-RemoteFile -Url $CFG_URL -Destination $cfg_dest
$reg_ok   = Get-RemoteFile -Url $REG_URL -Destination $reg_dest

if ($cfg_ok) { Write-Success "Perfil CFG descargado" }
else         { Write-Warn    "No se pudo descargar el CFG (continuando con REG)" }

if ($reg_ok) { Write-Success "Archivo REG descargado" }
else         { Write-Warn    "No se pudo descargar el REG (continuando con CFG)" }

if (-not $cfg_ok -and -not $reg_ok) {
    Write-Host ""
    Write-Host "  ERROR: No se pudo descargar ninguno de los archivos." -ForegroundColor Red
    Write-Host "  Verifica la conexion a internet e intenta de nuevo."  -ForegroundColor Red
    Write-EventLog -Status "ERROR" -Version $ksp.Version -Detail "Fallo descarga de archivos"
    Exit-Script 1
}


# -- Paso 4: Aplicar configuracion ----------------------------
Write-Step "4/5" "Aplicando configuracion de silencio..."

Write-Info "Deteniendo interfaz grafica de Kaspersky..."
Stop-KasperskyUI
Write-Success "Procesos de UI detenidos"

# Sub-paso REG
$reg_detail = "REG:omitido"
if ($reg_ok) {
    Write-Info "Aplicando claves de registro..."
    if (Apply-RegistryFile -RegFile $reg_dest) {
        Write-Success "Registro aplicado"
        $reg_detail = "REG:OK"
    } else {
        Write-Warn "El registro pudo no haberse aplicado completamente"
        $reg_detail = "REG:fallo"
    }
}

# Sub-paso CFG
$cfg_detail = "CFG:omitido"
if ($cfg_ok -and $ksp.AvpCom) {
    Write-Info "Importando perfil de Kaspersky via avp.com..."
    if (Apply-KasperskyCfg -AvpCom $ksp.AvpCom -CfgFile $cfg_dest) {
        Write-Success "Perfil CFG importado correctamente"
        $cfg_detail = "CFG:OK"
    } else {
        Write-Warn "El CFG no pudo importarse o fue cancelado (el .reg ya fue aplicado)"
        $cfg_detail = "CFG:fallo"
    }
}

Write-Info "Reiniciando servicio de Kaspersky..."
Restart-KasperskyService
Write-Success "Servicio reiniciado en modo silencioso"


# -- Paso 5: Registrar resultado ------------------------------
# El detalle del log incluye el resultado de cada sub-paso para
# que en el dashboard se pueda ver exactamente que ocurrio.

Write-Step "5/5" "Guardando registro de la operacion..."

Write-EventLog -Status "OK" -Version $ksp.Version -Detail "$reg_detail | $cfg_detail"

Write-Success "Log guardado en: $env:ProgramData\KspSilencer\log.csv"
if ($LOG_VPS -ne "") { Write-Success "Log enviado al servidor de TI" }

Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue

Write-Divider

Write-Host "  ################################################################" -ForegroundColor Green
Write-Host "  ##                                                            ##" -ForegroundColor Green
Write-Host "  ##   LISTO. Kaspersky corre en segundo plano sin popups.     ##" -ForegroundColor Green
Write-Host "  ##   Si algo persiste despues de reiniciar, avisa al TI.     ##" -ForegroundColor Green
Write-Host "  ##                                                            ##" -ForegroundColor Green
Write-Host "  ################################################################" -ForegroundColor Green
Write-Host ""

Exit-Script 0
