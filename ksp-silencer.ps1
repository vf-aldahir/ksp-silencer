#Requires -RunAsAdministrator

# =============================================================
# ksp-silencer.ps1
#
# Descripcion:
#   Aplica configuracion de silencio total a Kaspersky Endpoint
#   Security. Silencia TODAS las notificaciones: popups, alertas
#   de red, certificados, dispositivos Wi-Fi, sonidos y mas.
#
#   Logica de versionado:
#     El .reg guarda la version aplicada en el registro bajo
#     HKLM\SOFTWARE\KspSilencer\RegVersion. Si el equipo ya
#     tiene una version anterior, re-aplica el .reg actualizado
#     sin mostrar el formulario de nuevo.
#
#   Primera ejecucion  : muestra formulario + aplica todo
#   Actualizacion      : re-aplica .reg silencioso, sin formulario
#   Ya actualizado     : no hace nada
#
# Desarrollado por:
#   Daniel Medero y Aldahir Sanchez
#   Departamento de TI - Colegio Viktor Frankl, Queretaro
#
# Uso:
#   powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/vf-aldahir/ksp-silencer/main/ksp-silencer.ps1 | iex"
# =============================================================

# ---- CONFIGURACION ------------------------------------------
$REPO_BASE       = "https://raw.githubusercontent.com/vf-aldahir/ksp-silencer/main"
$REG_URL         = "$REPO_BASE/silencer.reg"
$LOG_VPS         = "https://aldahir.dev/ksp-log"
$LOG_RED         = ""

# Version actual del .reg en el repositorio.
# Debe coincidir con el valor RegVersion dentro de silencer.reg.
# Incrementar este numero cada vez que se actualice el .reg.
$REG_VERSION_ACTUAL = 4
# -------------------------------------------------------------

$VERSION   = "1.1"
$MACHINE   = $env:COMPUTERNAME
$USER_NAME = $env:USERNAME
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$TEMP_DIR  = "$env:TEMP\ksp_silencer"
$REG_KEY   = "HKLM:\SOFTWARE\KspSilencer"


# =============================================================
# BLOQUE: Funciones de interfaz CLI
# =============================================================

function Show-Banner {
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
    param([string]$Number, [string]$Text)
    Write-Host ""
    Write-Host "  [ $Number ]  $Text" -ForegroundColor Yellow
}

function Write-Success { param([string]$Text); Write-Host "        OK  $Text" -ForegroundColor Green }
function Write-Warn    { param([string]$Text); Write-Host "        **  $Text" -ForegroundColor Yellow }
function Write-Info    { param([string]$Text); Write-Host "        --  $Text" -ForegroundColor DarkGray }

function Write-Divider {
    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Exit-Script {
    param([int]$Code = 0)
    Write-Host ""
    Write-Host "  Presiona cualquier tecla para cerrar..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit $Code
}


# =============================================================
# BLOQUE: Versionado
# =============================================================

function Get-InstalledRegVersion {
    # Lee la version del .reg que fue aplicada en este equipo.
    # Retorna 0 si nunca se ha aplicado nada.

    try {
        $val = Get-ItemProperty -Path $REG_KEY -Name "RegVersion" -ErrorAction SilentlyContinue
        if ($val) { return [int]$val.RegVersion }
    } catch {}
    return 0
}


# =============================================================
# BLOQUE: Formulario de registro
# =============================================================

function Read-MenuOption {
    # Muestra lista numerada y espera opcion valida.
    param([string]$Prompt, [string[]]$Options)
    while ($true) {
        Write-Host ""
        Write-Host "  $Prompt" -ForegroundColor White
        Write-Host ""
        for ($i = 0; $i -lt $Options.Length; $i++) {
            Write-Host ("  {0,2}.  {1}" -f ($i + 1), $Options[$i]) -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host -NoNewline "  Opcion: " -ForegroundColor Yellow
        $input = Read-Host
        if ($input -match '^\d+$') {
            $idx = [int]$input - 1
            if ($idx -ge 0 -and $idx -lt $Options.Length) { return $Options[$idx] }
        }
        Write-Host "  Opcion no valida. Intenta de nuevo." -ForegroundColor Red
    }
}

function Read-TextInput {
    # Solicita texto libre, normaliza a mayusculas, no acepta vacio.
    param([string]$Prompt)
    while ($true) {
        Write-Host ""
        Write-Host "  $Prompt" -ForegroundColor White
        Write-Host -NoNewline "  Respuesta: " -ForegroundColor Yellow
        $input = (Read-Host).Trim().ToUpper()
        if ($input -ne "") { return $input }
        Write-Host "  Este campo es obligatorio." -ForegroundColor Red
    }
}

function Show-IntakeForm {
    # Formulario de registro del colaborador y equipo.
    # Solo se muestra en la primera instalacion, no en actualizaciones.

    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  REGISTRO DE EQUIPO" -ForegroundColor White
    Write-Host "  Completa los datos antes de continuar. Todos son obligatorios." -ForegroundColor DarkGray
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray

    $tipo = Read-MenuOption -Prompt "Tipo de equipo:" `
        -Options @("PC", "LAPTOP")

    $sede = Read-MenuOption -Prompt "Sede:" `
        -Options @("REFUGIO", "CORREGIDORA", "CORREGIDORA SECUNDARIA", "JURIQUILLA")

    $area = Read-MenuOption -Prompt "Area:" `
        -Options @("PRIMARIA", "SECUNDARIA", "PREESCOLAR", "SISTEMA VF", "MARKETING", "SALUD Y BIENESTAR", "TI")

    $puesto = Read-TextInput -Prompt "Puesto del colaborador (ej. DOCENTE, ADMINISTRATIVO):"
    $nombre = Read-TextInput -Prompt "Nombre completo del colaborador:"

    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Resumen:" -ForegroundColor White
    Write-Host "    Tipo        : $tipo"   -ForegroundColor Gray
    Write-Host "    Sede        : $sede"   -ForegroundColor Gray
    Write-Host "    Area        : $area"   -ForegroundColor Gray
    Write-Host "    Puesto      : $puesto" -ForegroundColor Gray
    Write-Host "    Colaborador : $nombre" -ForegroundColor Gray
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host -NoNewline "  Confirmar y continuar? (S/N): " -ForegroundColor Yellow
    $confirm = (Read-Host).Trim().ToUpper()

    # Acepta S, s o Enter. Cualquier otra letra cancela.
    if ($confirm -ne "S" -and $confirm -ne "") {
        Write-Host "  Cancelado. Ejecuta el script de nuevo para reintentar." -ForegroundColor Red
        Exit-Script 1
    }

    return @{ Tipo=$tipo; Sede=$sede; Area=$area; Puesto=$puesto; Colaborador=$nombre }
}


# =============================================================
# BLOQUE: Deteccion de Kaspersky
# =============================================================

function Get-KasperskyInstall {
    $result = @{ Found=$false; Version="Desconocida"; AvpCom=$null; AvpExe=$null }
    foreach ($base in @("C:\Program Files\Kaspersky Lab","C:\Program Files (x86)\Kaspersky Lab")) {
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

function Get-SerialNumber {
    try {
        $s = (Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
        if ($s) { return $s.Trim() }
    } catch {}
    return "DESCONOCIDO"
}


# =============================================================
# BLOQUE: Aplicacion
# =============================================================

function Get-RemoteFile {
    param([string]$Url, [string]$Destination)
    try {
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($Url, $Destination)
        return $true
    } catch { return $false }
}

function Apply-RegistryFile {
    param([string]$RegFile)
    try {
        $proc = Start-Process "regedit.exe" -ArgumentList "/s `"$RegFile`"" -Wait -PassThru -WindowStyle Hidden
        return ($proc.ExitCode -eq 0)
    } catch { return $false }
}

function Stop-KasperskyUI {
    foreach ($proc in @("avpui","kavtray","ksde","kisui","kav","klwtblfs")) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
    }
}

function Restart-KasperskyService {
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
    param(
        [string]$Status,
        [string]$Version,
        [string]$Serial      = "",
        [string]$Tipo        = "",
        [string]$Sede        = "",
        [string]$Area        = "",
        [string]$Puesto      = "",
        [string]$Colaborador = "",
        [string]$Detail      = ""
    )

    $log_line = "$TIMESTAMP,$MACHINE,$USER_NAME,$Serial,$Tipo,$Sede,$Area,$Puesto,$Colaborador,$Status,$Version,`"$Detail`""

    $local_file = "$env:ProgramData\KspSilencer\log.csv"
    $local_dir  = Split-Path $local_file
    if (-not (Test-Path $local_dir)) { New-Item -ItemType Directory $local_dir -Force | Out-Null }
    if (-not (Test-Path $local_file)) {
        Add-Content $local_file "Fecha,Equipo,Usuario,NumSerie,Tipo,Sede,Area,Puesto,Colaborador,Estado,VersionKSP,Detalle"
    }
    Add-Content $local_file $log_line

    if ($script:LOG_RED -ne "") {
        try {
            if (-not (Test-Path $script:LOG_RED)) {
                Add-Content $script:LOG_RED "Fecha,Equipo,Usuario,NumSerie,Tipo,Sede,Area,Puesto,Colaborador,Estado,VersionKSP,Detalle"
            }
            Add-Content $script:LOG_RED $log_line
        } catch {}
    }

    if ($script:LOG_VPS -ne "") {
        try {
            $payload = @{
                equipo=$MACHINE; usuario=$USER_NAME; serial=$Serial
                tipo=$Tipo; sede=$Sede; area=$Area
                puesto=$Puesto; colaborador=$Colaborador
                estado=$Status; version=$Version; detalle=$Detail
            } | ConvertTo-Json
            Invoke-RestMethod -Uri $script:LOG_VPS -Method Post -Body $payload `
                              -ContentType "application/json" -TimeoutSec 8 | Out-Null
        } catch {}
    }
}


# =============================================================
# EJECUCION PRINCIPAL
# =============================================================

Show-Banner

# -- Detectar Kaspersky primero -------------------------------
# Si no hay Kaspersky no tiene sentido hacer nada mas.

Write-Step "1/5" "Buscando instalacion de Kaspersky..."
$ksp    = Get-KasperskyInstall
$serial = Get-SerialNumber

if (-not $ksp.Found) {
    Write-Warn "Kaspersky no fue encontrado en este equipo."
    Write-EventLog -Status "ERROR" -Version "N/A" -Serial $serial -Detail "Kaspersky no instalado"
    Write-Host ""
    Write-Host "  No hay nada que configurar en este equipo." -ForegroundColor Yellow
    Exit-Script 1
}

Write-Success "Kaspersky encontrado - Version: $($ksp.Version)"
Write-Info    "Num. Serie : $serial"


# -- Verificar version instalada ------------------------------
# Tres casos posibles:
#   A) Version actual = version repo  -> ya esta al dia, salir
#   B) Version actual < version repo  -> actualizar sin formulario
#   C) Version actual = 0             -> primera vez, formulario completo

Write-Step "2/5" "Verificando version de configuracion..."

$version_instalada = Get-InstalledRegVersion

if ($version_instalada -eq $REG_VERSION_ACTUAL) {
    Write-Success "Este equipo ya tiene la version mas reciente (v$REG_VERSION_ACTUAL)."
    Write-Info    "No se realizaran cambios."
    Write-EventLog -Status "YA_APLICADO" -Version $ksp.Version -Serial $serial `
                   -Detail "RegVersion $version_instalada ya es la mas reciente"
    Write-Divider
    Write-Host "  Kaspersky ya corre en segundo plano sin notificaciones." -ForegroundColor Green
    Exit-Script 0
}

if ($version_instalada -eq 0) {
    Write-Warn "Primera instalacion detectada. Se mostrara el formulario de registro."
    $es_actualizacion = $false
} else {
    Write-Warn "Version instalada: v$version_instalada  ->  Version disponible: v$REG_VERSION_ACTUAL"
    Write-Info "Actualizando configuracion en segundo plano..."
    $es_actualizacion = $true
}


# -- Formulario (solo en primera instalacion) -----------------

if (-not $es_actualizacion) {
    $form = Show-IntakeForm
} else {
    # En actualizacion no hay formulario, se usan valores vacios
    # para el log — el registro anterior ya tiene los datos reales
    $form = @{ Tipo=""; Sede=""; Area=""; Puesto=""; Colaborador="ACTUALIZACION AUTOMATICA" }
}


# -- Descargar .reg -------------------------------------------

Write-Step "3/5" "Descargando configuracion v$REG_VERSION_ACTUAL..."

if (-not (Test-Path $TEMP_DIR)) { New-Item -ItemType Directory $TEMP_DIR -Force | Out-Null }

$reg_dest = "$TEMP_DIR\silencer.reg"
$reg_ok   = Get-RemoteFile -Url $REG_URL -Destination $reg_dest

if ($reg_ok) { Write-Success "Archivo REG descargado (v$REG_VERSION_ACTUAL)" }
else {
    Write-Host ""
    Write-Host "  ERROR: No se pudo descargar el archivo de configuracion." -ForegroundColor Red
    Write-Host "  Verifica la conexion a internet e intenta de nuevo."      -ForegroundColor Red
    Write-EventLog -Status "ERROR" -Version $ksp.Version -Serial $serial `
                   -Tipo $form.Tipo -Sede $form.Sede -Area $form.Area `
                   -Puesto $form.Puesto -Colaborador $form.Colaborador `
                   -Detail "Fallo descarga de silencer.reg v$REG_VERSION_ACTUAL"
    Exit-Script 1
}


# -- Aplicar configuracion ------------------------------------

Write-Step "4/5" "Aplicando configuracion de silencio..."

Write-Info "Deteniendo interfaz grafica de Kaspersky..."
Stop-KasperskyUI
Write-Success "Procesos de UI detenidos"

Write-Info "Aplicando claves de registro (v$REG_VERSION_ACTUAL)..."
$reg_detail = "REG:omitido"
if (Apply-RegistryFile -RegFile $reg_dest) {
    Write-Success "Registro aplicado - todas las notificaciones silenciadas"
    $reg_detail = "REG:OK-v$REG_VERSION_ACTUAL"
} else {
    Write-Warn "El registro pudo no haberse aplicado completamente"
    $reg_detail = "REG:fallo-v$REG_VERSION_ACTUAL"
}

Write-Info "Reiniciando servicio de Kaspersky..."
Restart-KasperskyService
Write-Success "Servicio reiniciado en modo silencioso"


# -- Log ------------------------------------------------------

Write-Step "5/5" "Guardando registro de la operacion..."

$estado_log = if ($es_actualizacion) { "ACTUALIZADO" } else { "OK" }

Write-EventLog -Status $estado_log -Version $ksp.Version -Serial $serial `
               -Tipo $form.Tipo -Sede $form.Sede -Area $form.Area `
               -Puesto $form.Puesto -Colaborador $form.Colaborador `
               -Detail $reg_detail

Write-Success "Log guardado en: $env:ProgramData\KspSilencer\log.csv"
if ($LOG_VPS -ne "") { Write-Success "Log enviado al servidor de TI" }

Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue

Write-Divider

if ($es_actualizacion) {
    Write-Host "  ################################################################" -ForegroundColor Cyan
    Write-Host "  ##                                                            ##" -ForegroundColor Cyan
    Write-Host "  ##   ACTUALIZADO a v$REG_VERSION_ACTUAL. Todas las alertas silenciadas.     ##" -ForegroundColor Cyan
    Write-Host "  ##   Si algo persiste despues de reiniciar, avisa al TI.     ##" -ForegroundColor Cyan
    Write-Host "  ##                                                            ##" -ForegroundColor Cyan
    Write-Host "  ################################################################" -ForegroundColor Cyan
} else {
    Write-Host "  ################################################################" -ForegroundColor Green
    Write-Host "  ##                                                            ##" -ForegroundColor Green
    Write-Host "  ##   LISTO. Kaspersky corre en segundo plano sin popups.     ##" -ForegroundColor Green
    Write-Host "  ##   Si algo persiste despues de reiniciar, avisa al TI.     ##" -ForegroundColor Green
    Write-Host "  ##                                                            ##" -ForegroundColor Green
    Write-Host "  ################################################################" -ForegroundColor Green
}

Write-Host ""
Exit-Script 0
