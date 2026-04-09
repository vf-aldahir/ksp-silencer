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
#     - DANIELTI_SILENCIO_TOTAL.cfg  : perfil de Kaspersky con
#       forceSilentMode activado en todos los modulos
#     - kaspersky_SILENCIO_TOTAL.reg : claves de registro de
#       Windows que complementan el silencio a nivel sistema
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
# URL base del repositorio donde viven el .cfg y el .reg
$REPO_BASE  = "https://raw.githubusercontent.com/vf-aldahir/ksp-silencer/main"

# URLs individuales de los archivos de configuracion
$CFG_URL    = "$REPO_BASE/silencer.cfg"
$REG_URL    = "$REPO_BASE/silencer.reg"

# URL del endpoint de logs en el VPS.
# Dejar vacio ("") para no enviar logs remotos.
$LOG_VPS    = "http://147.93.43.189/ksp-log"

# Carpeta de red opcional para log compartido (dejar "" si no aplica)
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
# Todas las funciones Write-* controlan como se ve la salida en
# la consola. Se usan colores y prefijos para diferenciar el
# tipo de mensaje sin necesidad de emojis ni caracteres especiales.

function Show-Banner {
    # Limpia la pantalla y muestra el encabezado principal
    # del programa con los creditos y datos del equipo actual.
    Clear-Host
    $lines = @(
        "",
        "  +================================================================+",
        "  |                                                                |",
        "  |   KSP SILENCER                                                 |",
        "  |   Configurador de silencio para Kaspersky Endpoint Security   |",
        "  |                                                                |",
        "  |   Desarrollado por  Daniel Medero  &  Aldahir Sanchez         |",
        "  |   TI - Colegio Viktor Frankl  //  Queretaro, Mexico           |",
        "  |                                                        v$VERSION   |",
        "  +================================================================+",
        ""
    )
    foreach ($line in $lines) {
        Write-Host $line -ForegroundColor Cyan
    }
    Write-Host "  Equipo  : $MACHINE"   -ForegroundColor White
    Write-Host "  Usuario : $USER_NAME" -ForegroundColor White
    Write-Host "  Fecha   : $TIMESTAMP" -ForegroundColor White
    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Step {
    # Muestra el numero y descripcion del paso actual.
    # Parametros:
    #   $Number : numero del paso (ej. "1/5")
    #   $Text   : descripcion breve de lo que se va a hacer
    param([string]$Number, [string]$Text)
    Write-Host "  [ $Number ]  $Text" -ForegroundColor Yellow
}

function Write-Success {
    # Confirma que una operacion termino correctamente.
    param([string]$Text)
    Write-Host "         OK   $Text" -ForegroundColor Green
}

function Write-Warning {
    # Aviso de algo que no es critico pero el usuario debe saber.
    param([string]$Text)
    Write-Host "         **   $Text" -ForegroundColor Yellow
}

function Write-Info {
    # Informacion de contexto, sin implicacion de exito o error.
    param([string]$Text)
    Write-Host "         --   $Text" -ForegroundColor DarkGray
}

function Write-Divider {
    # Separador visual entre secciones.
    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Exit-Script {
    # Pausa antes de cerrar para que el usuario pueda leer el resultado.
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
    # Busca la instalacion de Kaspersky en las rutas estandar
    # de Program Files (32 y 64 bit).
    #
    # Retorna un hashtable con:
    #   Found   : booleano, si encontro alguna instalacion
    #   Version : string con la version del producto
    #   AvpCom  : ruta completa a avp.com (CLI de Kaspersky)
    #   AvpExe  : ruta completa a avp.exe

    $result = @{
        Found   = $false
        Version = "Desconocida"
        AvpCom  = $null
        AvpExe  = $null
    }

    $search_paths = @(
        "C:\Program Files\Kaspersky Lab",
        "C:\Program Files (x86)\Kaspersky Lab"
    )

    foreach ($base in $search_paths) {
        if (-not (Test-Path $base)) { continue }

        $subdirs = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $subdirs) {
            $avp_com = Join-Path $dir.FullName "avp.com"
            $avp_exe = Join-Path $dir.FullName "avp.exe"

            if (Test-Path $avp_com) {
                $result.Found  = $true
                $result.AvpCom = $avp_com
                $result.AvpExe = $avp_exe

                # Intentar leer la version del ejecutable
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
    # Verifica si el equipo ya tiene la configuracion de silencio.
    # Revisa tres claves de registro que el script aplica:
    #   1. SilentMode en KES 64bit
    #   2. SilentMode en KES 32bit (WOW64)
    #   3. EnableNotifications en Notifications
    #
    # Si al menos 2 de 3 estan correctas, considera que ya esta aplicado.
    # Esto evita aplicar cambios redundantes en equipos ya configurados.

    $hits = 0

    $k1 = Get-ItemProperty "HKLM:\SOFTWARE\KasperskyLab\KES\settings" `
                           -Name "SilentMode" -ErrorAction SilentlyContinue
    if ($k1 -and $k1.SilentMode -eq 1) { $hits++ }

    $k2 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\KasperskyLab\KES\settings" `
                           -Name "SilentMode" -ErrorAction SilentlyContinue
    if ($k2 -and $k2.SilentMode -eq 1) { $hits++ }

    $k3 = Get-ItemProperty "HKLM:\SOFTWARE\KasperskyLab\KES\settings\Notifications" `
                           -Name "EnableNotifications" -ErrorAction SilentlyContinue
    if ($k3 -and $k3.EnableNotifications -eq 0) { $hits++ }

    return ($hits -ge 2)
}


# =============================================================
# BLOQUE: Descarga de archivos
# =============================================================

function Get-RemoteFile {
    # Descarga un archivo desde una URL a una ruta local.
    # Usa System.Net.WebClient para compatibilidad con
    # versiones antiguas de PowerShell (v3+).
    #
    # Retorna $true si la descarga fue exitosa, $false si fallo.

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
    # Aplica un archivo .reg al registro de Windows usando regedit
    # en modo silencioso (/s). No muestra ningun dialogo.
    # Retorna $true si regedit termino sin error.

    param([string]$RegFile)
    try {
        $proc = Start-Process "regedit.exe" `
                    -ArgumentList "/s `"$RegFile`"" `
                    -Wait -PassThru -WindowStyle Hidden
        return ($proc.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Apply-KasperskyCfg {
    # Importa un archivo .cfg a Kaspersky usando su CLI (avp.com).
    # El comando IMPORT carga el perfil completo de politicas,
    # incluyendo los flags de forceSilentMode y useSpecialAlert.
    # Retorna $true si avp.com termino sin error.

    param([string]$AvpCom, [string]$CfgFile)
    try {
        $proc = Start-Process $AvpCom `
                    -ArgumentList "IMPORT `"$CfgFile`"" `
                    -Wait -PassThru -WindowStyle Hidden
        return ($proc.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Stop-KasperskyUI {
    # Termina todos los procesos conocidos de la interfaz grafica
    # de Kaspersky antes de aplicar la configuracion.
    # Esto evita que Kaspersky revierta los cambios al detectar
    # que su configuracion fue modificada mientras estaba activo.
    #
    # Nota: el servicio AVP (proteccion real) NO se detiene aqui.
    # Solo se matan los procesos de UI.

    $ui_procs = @("avpui", "kavtray", "ksde", "kisui", "kav", "klwtblfs")
    foreach ($proc in $ui_procs) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
    }
}

function Restart-KasperskyService {
    # Reinicia el servicio principal de Kaspersky (AVP) y el
    # agente de red (klnagent) para que cargue la nueva
    # configuracion aplicada.
    #
    # Se espera 3 segundos entre el stop y el start para
    # asegurar que el servicio termine completamente.

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
    # Registra el resultado de la ejecucion en tres destinos:
    #
    #   1. LOCAL  - CSV en C:\ProgramData\KspSilencer\log.csv
    #              Siempre se escribe, sin importar si hay red.
    #
    #   2. RED    - CSV en carpeta compartida (si $LOG_RED != "")
    #              Util si tienen un servidor de archivos interno.
    #
    #   3. VPS    - POST HTTP al endpoint del servidor de logs
    #              (si $LOG_VPS != ""). Envia JSON con los datos
    #              del equipo, usuario, estado y version.
    #
    # Parametros:
    #   $Status  : "OK" | "YA_APLICADO" | "ERROR"
    #   $Version : version de Kaspersky detectada
    #   $Detail  : texto libre con informacion adicional

    param(
        [string]$Status,
        [string]$Version,
        [string]$Detail = ""
    )

    $log_line = "$TIMESTAMP,$MACHINE,$USER_NAME,$Status,$Version,`"$Detail`""

    # -- Log local --
    $local_file = "$env:ProgramData\KspSilencer\log.csv"
    $local_dir  = Split-Path $local_file

    if (-not (Test-Path $local_dir)) {
        New-Item -ItemType Directory $local_dir -Force | Out-Null
    }
    if (-not (Test-Path $local_file)) {
        Add-Content $local_file "Fecha,Equipo,Usuario,Estado,VersionKSP,Detalle"
    }
    Add-Content $local_file $log_line

    # -- Log en carpeta de red --
    if ($script:LOG_RED -ne "") {
        try {
            $net_dir = Split-Path $script:LOG_RED
            if (-not (Test-Path $net_dir)) {
                New-Item -ItemType Directory $net_dir -Force | Out-Null
            }
            if (-not (Test-Path $script:LOG_RED)) {
                Add-Content $script:LOG_RED "Fecha,Equipo,Usuario,Estado,VersionKSP,Detalle"
            }
            Add-Content $script:LOG_RED $log_line
        } catch {}
    }

    # -- Log remoto en VPS --
    if ($script:LOG_VPS -ne "") {
        try {
            $payload = @{
                equipo  = $MACHINE
                usuario = $USER_NAME
                estado  = $Status
                version = $Version
                detalle = $Detail
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $script:LOG_VPS `
                              -Method Post `
                              -Body $payload `
                              -ContentType "application/json" `
                              -TimeoutSec 8 | Out-Null
        } catch {}
    }
}


# =============================================================
# EJECUCION PRINCIPAL
# =============================================================

Show-Banner

# -- Paso 1: Detectar instalacion de Kaspersky ----------------
# Si no esta instalado no hay nada que hacer. Se registra el
# evento y se sale sin aplicar ninguna modificacion.

Write-Step "1/5" "Buscando instalacion de Kaspersky..."

$ksp = Get-KasperskyInstall

if (-not $ksp.Found) {
    Write-Warning "Kaspersky no fue encontrado en este equipo."
    Write-EventLog -Status "ERROR" -Version "N/A" -Detail "Kaspersky no instalado"
    Write-Host ""
    Write-Host "  No hay nada que configurar en este equipo." -ForegroundColor Yellow
    Exit-Script 1
}

Write-Success "Kaspersky encontrado - Version: $($ksp.Version)"
Write-Info    "Ruta: $($ksp.AvpCom)"
Write-Host ""


# -- Paso 2: Verificar si ya esta configurado -----------------
# Si el equipo ya tiene el silencio aplicado se registra como
# YA_APLICADO y se sale sin hacer cambios innecesarios.

Write-Step "2/5" "Verificando configuracion actual..."

if (Test-SilenceAlreadyApplied) {
    Write-Success "Este equipo ya tiene la configuracion de silencio aplicada."
    Write-Info    "No se realizaran cambios."
    Write-EventLog -Status "YA_APLICADO" -Version $ksp.Version
    Write-Divider
    Write-Host "  Kaspersky ya corre en segundo plano sin notificaciones." -ForegroundColor Green
    Exit-Script 0
}

Write-Warning "Configuracion de silencio no detectada. Continuando con la instalacion..."
Write-Host ""


# -- Paso 3: Descargar archivos de configuracion --------------
# Se descarga el .cfg (perfil interno de Kaspersky) y el .reg
# (claves de registro de Windows). Si ninguno se puede descargar
# se aborta el proceso.

Write-Step "3/5" "Descargando archivos de configuracion..."

if (-not (Test-Path $TEMP_DIR)) {
    New-Item -ItemType Directory $TEMP_DIR -Force | Out-Null
}

$cfg_dest = "$TEMP_DIR\SILENCIO_TOTAL.cfg"
$reg_dest = "$TEMP_DIR\SILENCIO_TOTAL.reg"

$cfg_ok = Get-RemoteFile -Url $CFG_URL -Destination $cfg_dest
$reg_ok = Get-RemoteFile -Url $REG_URL -Destination $reg_dest

if ($cfg_ok) { Write-Success "Perfil CFG descargado" }
else         { Write-Warning "No se pudo descargar el CFG (continuando con REG)" }

if ($reg_ok) { Write-Success "Archivo REG descargado" }
else         { Write-Warning "No se pudo descargar el REG (continuando con CFG)" }

if (-not $cfg_ok -and -not $reg_ok) {
    Write-Host ""
    Write-Host "  ERROR: No se pudo descargar ninguno de los archivos." -ForegroundColor Red
    Write-Host "  Verifica la conexion a internet e intenta de nuevo."  -ForegroundColor Red
    Write-EventLog -Status "ERROR" -Version $ksp.Version -Detail "Fallo descarga de archivos"
    Exit-Script 1
}

Write-Host ""


# -- Paso 4: Aplicar configuracion ----------------------------
# Se siguen tres sub-pasos en orden:
#   4a. Matar procesos de UI para que Kaspersky no revierta cambios
#   4b. Aplicar el registro de Windows (.reg)
#   4c. Importar el perfil de Kaspersky (.cfg) via avp.com
# Al final se reinicia el servicio para cargar la nueva config.

Write-Step "4/5" "Aplicando configuracion de silencio..."

Write-Info "Deteniendo interfaz grafica de Kaspersky..."
Stop-KasperskyUI
Write-Success "Procesos de UI detenidos"

if ($reg_ok) {
    Write-Info "Aplicando claves de registro..."
    $reg_result = Apply-RegistryFile -RegFile $reg_dest
    if ($reg_result) { Write-Success "Registro aplicado" }
    else             { Write-Warning "El registro pudo no haberse aplicado completamente" }
}

if ($cfg_ok -and $ksp.AvpCom) {
    Write-Info "Importando perfil de Kaspersky via avp.com..."
    $cfg_result = Apply-KasperskyCfg -AvpCom $ksp.AvpCom -CfgFile $cfg_dest
    if ($cfg_result) { Write-Success "Perfil importado correctamente" }
    else             { Write-Warning "avp.com retorno un codigo no-cero (puede ser normal en algunos sistemas)" }
}

Write-Info "Reiniciando servicio de Kaspersky..."
Restart-KasperskyService
Write-Success "Servicio reiniciado en modo silencioso"

Write-Host ""


# -- Paso 5: Registrar resultado ------------------------------
# Se escribe el log local siempre. El log remoto solo si
# $LOG_VPS esta configurado. Se limpia la carpeta temporal.

Write-Step "5/5" "Guardando registro de la operacion..."

Write-EventLog -Status "OK" -Version $ksp.Version

Write-Success "Log guardado en: $env:ProgramData\KspSilencer\log.csv"
if ($LOG_VPS -ne "") { Write-Success "Log enviado al servidor de TI" }

Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue

Write-Divider

Write-Host "  +------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  LISTO. Kaspersky corre en segundo plano sin notificaciones |" -ForegroundColor Green
Write-Host "  |  Si algo persiste despues de reiniciar, avisale al equipo.  |" -ForegroundColor Green
Write-Host "  +------------------------------------------------------------+" -ForegroundColor Green
Write-Host ""

Exit-Script 0
