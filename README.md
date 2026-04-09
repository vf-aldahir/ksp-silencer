# KSP Silencer

Herramienta de configuracion automatica de silencio para Kaspersky Endpoint Security.
Desarrollada por el equipo de TI del Colegio Viktor Frankl, Queretaro.

---

## Para que sirve

Kaspersky estaba generando popups, notificaciones y ventanas emergentes que
interrumpian el trabajo en los equipos del colegio. Este script aplica una
configuracion de silencio total que mantiene la proteccion activa pero elimina
completamente toda interaccion visual con el usuario.

El antivirus sigue funcionando con normalidad: escanea, bloquea amenazas y
actualiza definiciones. Lo unico que desaparece son las notificaciones.

---

## Como usarlo (instrucciones para el equipo)

**1.** Presionar `Win + R`

**2.** Escribir `cmd` y presionar `Ctrl + Shift + Enter` (esto lo abre como administrador)

**3.** Pegar la siguiente linea y presionar Enter:

```
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/vf-aldahir/ksp-silencer/main/ksp-silencer.ps1 | iex"
```

**4.** Esperar a que el script termine y mostrar el mensaje de LISTO.

No se necesita descargar nada manualmente. El script descarga todo lo que necesita
desde este repositorio y lo aplica automaticamente.

---

## Que hace el script paso a paso

**Paso 1 — Deteccion**
Busca la instalacion de Kaspersky en las rutas estandar de Program Files.
Si no encuentra ninguna instalacion, sale sin hacer cambios.

**Paso 2 — Verificacion**
Revisa el registro de Windows para detectar si la configuracion de silencio
ya fue aplicada anteriormente. Si el equipo ya esta configurado, no repite
el proceso y registra el evento como YA_APLICADO.

**Paso 3 — Descarga**
Descarga dos archivos desde este repositorio:
- `DANIELTI_SILENCIO_TOTAL.cfg` — perfil de Kaspersky con silencio activado
- `kaspersky_SILENCIO_TOTAL.reg` — claves de registro de Windows complementarias

**Paso 4 — Aplicacion**
- Detiene los procesos de interfaz grafica de Kaspersky
- Aplica las claves de registro con regedit
- Importa el perfil CFG via la CLI de Kaspersky (avp.com)
- Reinicia el servicio principal de Kaspersky

**Paso 5 — Registro**
Guarda un log local en `C:\ProgramData\KspSilencer\log.csv` y envia
el evento al servidor de logs del VPS si esta configurado.

---

## Archivos del repositorio

| Archivo | Descripcion |
|---|---|
| `ksp-silencer.ps1` | Script principal que se ejecuta en los equipos |
| `DANIELTI_SILENCIO_TOTAL.cfg` | Perfil de Kaspersky (forceSilentMode activo en 88 modulos) |
| `kaspersky_SILENCIO_TOTAL.reg` | Claves de registro para silencio a nivel Windows |

---

## Servidor de logs (VPS)

El script puede enviar un registro de cada ejecucion a un endpoint HTTP.
Esto permite ver desde un dashboard web cuales equipos ya fueron configurados.

### Estructura del servidor

```
ksp-log-server/
  index.js          servidor Node.js + Express
  package.json      dependencias
  public/
    index.html      dashboard web con tabla de logs
```

### Instalacion en el VPS

```bash
# 1. Crear la base de datos
psql -U postgres -c "CREATE DATABASE ksp_logs;"

# 2. Subir los archivos del servidor al VPS
scp -r ksp-log-server/ root@147.93.43.189:/opt/ksp-silencer/

# 3. Instalar dependencias
cd /opt/ksp-silencer
npm install

# 4. Configurar variables de entorno
echo 'export DATABASE_URL="postgresql://postgres:TU_PASSWORD@localhost:5432/ksp_logs"' >> ~/.bashrc
echo 'export KSP_PASSWORD="tu_contrasena_segura"' >> ~/.bashrc
echo 'export KSP_PORT="4242"' >> ~/.bashrc
source ~/.bashrc

# 5. Iniciar con PM2
npm install -g pm2
pm2 start index.js --name ksp-silencer
pm2 save
pm2 startup
```

### Configuracion de Nginx

Agregar dentro del bloque `server` del dominio existente:

```nginx
location /ksp-log {
    proxy_pass http://127.0.0.1:4242/ksp-log;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}

location /ksp-logs {
    proxy_pass http://127.0.0.1:4242/ksp-logs;
    proxy_set_header X-Real-IP $remote_addr;
}

location /ksp-api/ {
    proxy_pass http://127.0.0.1:4242/ksp-api/;
    proxy_set_header X-Real-IP $remote_addr;
}

location /ksp-static/ {
    proxy_pass http://127.0.0.1:4242/ksp-static/;
}
```

Despues de editar Nginx:

```bash
nginx -t && systemctl reload nginx
```

### Acceso al dashboard

```
https://tudominio.com/ksp-logs?pass=tu_contrasena_segura
```

---

## Log local en cada equipo

Independientemente del servidor, cada equipo guarda su propio log en:

```
C:\ProgramData\KspSilencer\log.csv
```

Formato: `Fecha, Equipo, Usuario, Estado, VersionKSP, Detalle`

---

## Creditos

Desarrollado por Daniel Medero y Aldahir Sanchez
Departamento de TI — Colegio Viktor Frankl, Queretaro, Mexico
