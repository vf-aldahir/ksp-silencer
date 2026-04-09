#Requires -RunAsAdministrator

# =============================================================
# ksp-silencer.ps1
#
# Descripcion:
#   Aplica configuracion de silencio total a Kaspersky Endpoint
#   Security. Detiene toda notificacion, popup y ventana de la
#   interfaz grafica sin afectar la proteccion en segundo plano.
#
#   Antes de aplicar cambios, presenta un formulario breve para
#   registrar informacion del colaborador y el equipo. Todos los
#   datos se envian al servidor de logs del departamento de TI.
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

function Write-Success {
    param([string]$Text)
    Write-Host "        OK  $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "        **  $Text" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Text)
    Write-Host "        --  $Text" -ForegroundColor DarkGray
}

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
# BLOQUE: Formulario de registro
# =============================================================

function Read-MenuOption {
    # Muestra una lista de opciones numeradas y espera que el
    # usuario ingrese un numero valido. No avanza hasta que la
    # respuesta sea correcta.
    #
    # Parametros:
    #   $Prompt  : pregunta que se muestra al usuario
    #   $Options : array de strings con las opciones
    #
    # Retorna el texto de la opcion seleccionada.

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
            if ($idx -ge 0 -and $idx -lt $Options.Length) {
                return $Options[$idx]
            }
        }
        Write-Host "  Opcion no valida. Intenta de nuevo." -ForegroundColor Red
    }
}

function Read-TextInput {
    # Solicita un texto libre al usuario y lo normaliza a
    # mayusculas. No acepta entrada vacia — repite hasta
    # que el usuario escriba algo.
    #
    # Parametros:
    #   $Prompt : instruccion que se muestra al usuario
    #
    # Retorna el texto en mayusculas sin espacios al inicio/fin.

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
    # Presenta el formulario completo de registro al usuario.
    # Todos los campos son obligatorios.
    #
    # Retorna un hashtable con:
    #   Tipo        : "PC" o "LAPTOP"
    #   Sede        : sede del colegio seleccionada
    #   Area        : area de trabajo seleccionada
    #   Puesto      : puesto del colaborador (mayusculas)
    #   Colaborador : nombre del colaborador (mayusculas)

    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  REGISTRO DE EQUIPO" -ForegroundColor White
    Write-Host "  Completa los siguientes datos antes de continuar." -ForegroundColor DarkGray
    Write-Host "  Todos los campos son obligatorios." -ForegroundColor DarkGray
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray

    $tipo = Read-MenuOption `
        -Prompt "Tipo de equipo:" `
        -Options @("PC", "LAPTOP")

    $sede = Read-MenuOption `
        -Prompt "Sede:" `
        -Options @("REFUGIO", "CORREGIDORA", "CORREGIDORA SECUNDARIA", "JURIQUILLA")

    $area = Read-MenuOption `
        -Prompt "Area:" `
        -Options @("PRIMARIA", "SECUNDARIA", "PREESCOLAR", "SISTEMA VF", "MARKETING", "SALUD Y BIENESTAR")

    $puesto = Read-TextInput -Prompt "Puesto del colaborador (ej. DOCENTE, ADMINISTRATIVO):"

    $nombre = Read-TextInput -Prompt "Nombre completo del colaborador:"

    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Resumen del registro:" -ForegroundColor White
    Write-Host "    Tipo        : $tipo"        -ForegroundColor Gray
    Write-Host "    Sede        : $sede"        -ForegroundColor Gray
    Write-Host "    Area        : $area"        -ForegroundColor Gray
    Write-Host "    Puesto      : $puesto"      -ForegroundColor Gray
    Write-Host "    Colaborador : $nombre"      -ForegroundColor Gray
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host -NoNewline "  Confirmar y continuar? (S/N): " -ForegroundColor Yellow
    $confirm = (Read-Host).Trim().ToUpper()

    if ($confirm -ne "S") {
        Write-Host "  Formulario cancelado. Ejecuta el script de nuevo para reintentar." -ForegroundColor Red
        Exit-Script 1
    }

    return @{
        Tipo        = $tipo
        Sede        = $sede
        Area        = $area
        Puesto      = $puesto
        Colaborador = $nombre
    }
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

function Get-SerialNumber {
    # Obtiene el numero de serie del equipo via WMI.
    # En laptops suele ser el numero de serie del fabricante.
    # En PCs de escritorio puede ser el de la placa base.
    # Retorna "DESCONOCIDO" si WMI no responde.

    try {
        $serial = (Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
        if ($serial) { return $serial.Trim() }
        return "DESCONOCIDO"
    } catch {
        return "DESCONOCIDO"
    }
}

function Test-SilenceAlreadyApplied {
    # Revisa 3 claves de registro. Si 2+ coinciden, el equipo
    # ya tiene la configuracion aplicada.

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
# BLOQUE: Descarga y aplicacion
# =============================================================

function Get-RemoteFile {
    # Descarga un archivo desde URL a disco local via WebClient.
    param([string]$Url, [string]$Destination)
    try {
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($Url, $Destination)
        return $true
    } catch { return $false }
}

function Apply-RegistryFile {
    # Aplica un .reg con regedit en modo silencioso.
    param([string]$RegFile)
    try {
        $proc = Start-Process "regedit.exe" -ArgumentList "/s `"$RegFile`"" -Wait -PassThru -WindowStyle Hidden
        return ($proc.ExitCode -eq 0)
    } catch { return $false }
}

function Stop-KasperskyUI {
    # Termina procesos de UI de Kaspersky. El servicio AVP no se toca.
    foreach ($proc in @("avpui","kavtray","ksde","kisui","kav","klwtblfs")) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
    }
}

function Restart-KasperskyService {
    # Reinicia AVP y klnagent con pausa de 3s entre stop y start.
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
    # Guarda el evento en log local, carpeta de red y VPS.
    # Incluye todos los datos del formulario y del equipo.

    param(
        [string]$Status,
        [string]$Version,
        [string]$Serial,
        [string]$Tipo,
        [string]$Sede,
        [string]$Area,
        [string]$Puesto,
        [string]$Colaborador,
        [string]$Detail = ""
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
                equipo      = $MACHINE
                usuario     = $USER_NAME
                serial      = $Serial
                tipo        = $Tipo
                sede        = $Sede
                area        = $Area
                puesto      = $Puesto
                colaborador = $Colaborador
                estado      = $Status
                version     = $Version
                detalle     = $Detail
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

# -- Formulario de registro -----------------------------------
# Se presenta antes de cualquier paso tecnico para asegurarse
# de que el log tenga informacion completa del colaborador.

$form = Show-IntakeForm


# -- Numero de serie (en segundo plano) -----------------------
$serial = Get-SerialNumber


# -- Paso 1: Detectar Kaspersky -------------------------------
Write-Step "1/5" "Buscando instalacion de Kaspersky..."

$ksp = Get-KasperskyInstall

if (-not $ksp.Found) {
    Write-Warn "Kaspersky no fue encontrado en este equipo."
    Write-EventLog -Status "ERROR" -Version "N/A" -Serial $serial `
                   -Tipo $form.Tipo -Sede $form.Sede -Area $form.Area `
                   -Puesto $form.Puesto -Colaborador $form.Colaborador `
                   -Detail "Kaspersky no instalado"
    Write-Host ""
    Write-Host "  No hay nada que configurar en este equipo." -ForegroundColor Yellow
    Exit-Script 1
}

Write-Success "Kaspersky encontrado - Version: $($ksp.Version)"
Write-Info    "Num. Serie  : $serial"
Write-Info    "Ruta        : $($ksp.AvpCom)"


# -- Paso 2: Verificar configuracion actual -------------------
Write-Step "2/5" "Verificando configuracion actual..."

if (Test-SilenceAlreadyApplied) {
    Write-Success "Este equipo ya tiene la configuracion de silencio aplicada."
    Write-Info    "No se realizaran cambios."
    Write-EventLog -Status "YA_APLICADO" -Version $ksp.Version -Serial $serial `
                   -Tipo $form.Tipo -Sede $form.Sede -Area $form.Area `
                   -Puesto $form.Puesto -Colaborador $form.Colaborador `
                   -Detail "Configuracion detectada, sin cambios"
    Write-Divider
    Write-Host "  Kaspersky ya corre en segundo plano sin notificaciones." -ForegroundColor Green
    Exit-Script 0
}

Write-Warn "Configuracion de silencio no detectada. Continuando..."


# -- Paso 3: Descargar archivos -------------------------------
Write-Step "3/5" "Descargando archivos de configuracion..."

if (-not (Test-Path $TEMP_DIR)) { New-Item -ItemType Directory $TEMP_DIR -Force | Out-Null }

$reg_dest = "$TEMP_DIR\silencer.reg"
$reg_ok   = Get-RemoteFile -Url $REG_URL -Destination $reg_dest

if ($reg_ok) { Write-Success "Archivo REG descargado" }
else {
    Write-Host ""
    Write-Host "  ERROR: No se pudo descargar el archivo de configuracion." -ForegroundColor Red
    Write-Host "  Verifica la conexion a internet e intenta de nuevo."      -ForegroundColor Red
    Write-EventLog -Status "ERROR" -Version $ksp.Version -Serial $serial `
                   -Tipo $form.Tipo -Sede $form.Sede -Area $form.Area `
                   -Puesto $form.Puesto -Colaborador $form.Colaborador `
                   -Detail "Fallo descarga de silencer.reg"
    Exit-Script 1
}


# -- Paso 4: Aplicar configuracion ----------------------------
Write-Step "4/5" "Aplicando configuracion de silencio..."

Write-Info "Deteniendo interfaz grafica de Kaspersky..."
Stop-KasperskyUI
Write-Success "Procesos de UI detenidos"

$reg_detail = "REG:omitido"
Write-Info "Aplicando claves de registro..."
if (Apply-RegistryFile -RegFile $reg_dest) {
    Write-Success "Registro aplicado"
    $reg_detail = "REG:OK"
} else {
    Write-Warn "El registro pudo no haberse aplicado completamente"
    $reg_detail = "REG:fallo"
}

Write-Info "Reiniciando servicio de Kaspersky..."
Restart-KasperskyService
Write-Success "Servicio reiniciado en modo silencioso"


# -- Paso 5: Registrar resultado ------------------------------
Write-Step "5/5" "Guardando registro de la operacion..."

Write-EventLog -Status "OK" -Version $ksp.Version -Serial $serial `
               -Tipo $form.Tipo -Sede $form.Sede -Area $form.Area `
               -Puesto $form.Puesto -Colaborador $form.Colaborador `
               -Detail $reg_detail

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
