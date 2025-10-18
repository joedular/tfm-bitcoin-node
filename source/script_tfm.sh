#!/bin/bash

# Script: install_bitcoin.sh
# Objetivo: Instalar Bitcoin Core con opción de instalación completa o según perfil de usuario
#========== EJECUCIÓN ==========#
# chown bitcoin:bitcoin /var/log/bitcoind-monitor
# LOGFILE="/var/log/bitcoind-monitor/bitcoin_install.log"
# exec > >(tee -a "$LOGFILE") 2>&1

# echo "[🕒] Inicio de la instalación: $(date)"
export log=0
#========== FUNCIONES BASE ==========#
function verificar_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root."
    exit 1
  fi
}

function verificar_requisitos() {
  echo -e "\n[+] Verificando requisitos del sistema..."

  echo -e "\n[Información del sistema]"
  echo "Usuario actual     : $(whoami)"
  echo "Fecha y hora       : $(date)"
  echo "Nombre de host     : $(hostname)"
  echo "Sistema operativo  : $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d '"' -f2)"
  echo "Versión del kernel : $(uname -r)"
  echo "Arquitectura       : $(uname -m)"

  echo -e "\n[CPU]"
  echo "Modelo CPU         : $(grep 'model name' /proc/cpuinfo | head -1 | cut -d ':' -f2 | xargs)"
  echo "Núcleos disponibles: $(nproc)"

  echo -e "\n[Memoria RAM]"
  free -h | awk '/^Mem:/ {print "Total: "$2" | Libre: "$4}'

  echo -e "\n[Disco principal (/)]"
  df -h / | awk 'NR==1 || NR==2 {print $0}'

  echo -e "\n[Discos detectados]"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v loop

  echo -e "\n[Evaluación]"
  local ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
  local disk_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
  local cpu_cores=$(nproc)

  [[ $cpu_cores -lt 2 ]] && echo "[!] Advertencia: se recomienda al menos 2 núcleos de CPU."
  [[ $ram_mb -lt 4000 ]] && echo "[!] Advertencia: menos de 4 GB de RAM puede afectar el rendimiento."
  [[ $disk_gb -lt 500 ]] && echo "[!] Advertencia: menos de 500 GB disponibles puede ser insuficiente para nodo completo."

  echo -e "\n[+] Verificación de requisitos completada.\n"
  read -p "¿Desea continuar con la instalación? [S/n]: " respuesta
  [[ "$respuesta" =~ ^[Nn]$ ]] && exit 0
}


function detectar_instalacion_bitcoin() {
  if command -v bitcoind >/dev/null 2>&1; then
    echo "[✔] Bitcoin Core ya está instalado en el sistema."
    return 0
  else
    echo "[✘] Bitcoin Core no está instalado."
    return 1
  fi
}

function detectar_perfil_actual() {
  local conf="/etc/bitcoin/bitcoin.conf"
  if [[ -f "$conf" ]]; then
    echo "[+] Detectando perfil actual basado en $conf..."
    local prune=$(grep -E '^\s*prune=' "$conf" | cut -d '=' -f2)
    local txindex=$(grep -E '^\s*txindex=' "$conf" | cut -d '=' -f2)
    local blockfilterindex=$(grep -E '^\s*blockfilterindex=' "$conf" | cut -d '=' -f2)
    echo "  prune=$prune | txindex=$txindex | blockfilterindex=$blockfilterindex"

    if [[ "$txindex" == "1" && -z "$prune" && -z "$blockfilterindex" ]]; then
      echo "  → Perfil detectado: Configuración estándar (por defecto)"
    elif [[ "$prune" == "0" && "$txindex" == "1" ]]; then
      echo "  → Perfil detectado: Validador/Operador"
    elif [[ "$txindex" == "1" && "$blockfilterindex" == "1" ]]; then
      echo "  → Perfil detectado: Analista de datos"
    elif [[ "$prune" -ge 500 && "$txindex" == "0" ]]; then
      echo "  → Perfil detectado: Educador o Lightning"
    else
      echo "  → Perfil detectado: Desconocido o personalizado"
    fi
  else
    echo "[!] No se encontró bitcoin.conf en /etc/bitcoin"
  fi
}

function desinstalar_bitcoin() {
  echo "[!] Esto eliminará Bitcoin Core y su configuración. ¿Desea continuar?"
  read -p "[s/N]: " confirm
  if [[ "$confirm" =~ ^[Ss]$ ]]; then
    echo "[+] Deteniendo servicio bitcoind..."
    systemctl stop bitcoind 2>/dev/null
    echo "[+] Eliminando binarios, configuraciones y datos..."
    rm -rf /usr/local/bin/bitcoin* /usr/local/src/bitcoin
    rm -rf /etc/bitcoin /opt/BLOCKCHAIN ~/.bitcoin
    systemctl disable bitcoind 2>/dev/null
    rm -f /etc/systemd/system/bitcoind.service
    systemctl daemon-reload
    echo "[✔] Desinstalación completada."
  else
    echo "[✘] Operación cancelada."
  fi
}

function esperar_bitcoind_listo() {
  echo "[⌛] Esperando a que bitcoind finalice la descarga inicial (IBD)..."
  for i in {1..60}; do
    local estado=$(bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf getblockchaininfo 2>/dev/null)
    if [[ $? -eq 0 ]]; then
      ibd=$(echo "$estado" | jq -r .initialblockdownload)
      if [[ "$ibd" == "false" ]]; then
        echo "[✔] Nodo completamente sincronizado."
        return 0
      fi
    fi
    echo "[⏳] Aún en proceso de descarga inicial... ($i/60)"
    sleep 30
  done
  echo "[✘] El nodo no se ha sincronizado completamente tras varios intentos."
  return 1
}



#========== CREAR PERFILES ==========#

function preservar_datos_conf() {
  local conf="/etc/bitcoin/bitcoin.conf"
  local tmp="$conf.tmp"
  local datadir_line=$(grep '^datadir=' "$conf")
  local auth_line=$(grep '^rpcauth=' "$conf")

  echo "# bitcoin.conf generado por el script de instalación" > "$tmp"
  [[ -n "$datadir_line" ]] && echo "$datadir_line" >> "$tmp" || echo "datadir=/opt/BLOCKCHAIN" >> "$tmp"
  [[ -n "$auth_line" ]] && echo "$auth_line" >> "$tmp"
  {
    echo "server=1"
    echo "daemon=1"
  } >> "$tmp"
}

function configurar_perfil_estandar() {
  echo "[+] Aplicando configuración estándar (por defecto)..."
  mkdir -p /etc/bitcoin
  preservar_datos_conf
  {
    echo "txindex=1"
  } >> /etc/bitcoin/bitcoin.conf.tmp
  mv /etc/bitcoin/bitcoin.conf.tmp /etc/bitcoin/bitcoin.conf
  echo "[✔] Configuración estándar aplicada en /etc/bitcoin/bitcoin.conf"
}

function configurar_perfil_validador() {
  echo "[+] Aplicando perfil: Validador..."
  mkdir -p /etc/bitcoin
  preservar_datos_conf
  {
    echo "prune=0"
    echo "txindex=1"
  } >> /etc/bitcoin/bitcoin.conf.tmp
  mv /etc/bitcoin/bitcoin.conf.tmp /etc/bitcoin/bitcoin.conf
  echo "[✔] Perfil Validador aplicado."
}


function configurar_perfil_analista() {
  echo -e "\n[⚙️] Aplicando perfil: Analista de datos..."
  mkdir -p /etc/bitcoin
  preservar_datos_conf
  {
    echo "prune=0"                    # Asegura nodo completo (sin pruning)
    echo "txindex=1"                 # Indexado de transacciones completo
    echo "blockfilterindex=1"       # Filtros compactos para búsquedas
  } >> /etc/bitcoin/bitcoin.conf.tmp
  mv /etc/bitcoin/bitcoin.conf.tmp /etc/bitcoin/bitcoin.conf
  echo "[✔] Perfil Analista aplicado."
}


function configurar_perfil_dapps() {
  echo -e "\n[⚙️] Aplicando perfil: dApp / Wallet Developer"
  mkdir -p /etc/bitcoin
  preservar_datos_conf
  {
    echo "prune=550"                 # Nodo podado: mantiene últimos bloques (~550 = ~5GB)
    echo "txindex=0"                 # No se necesita indexado completo
    echo "blockfilterindex=0"        # No requiere filtros compactos
  } >> /etc/bitcoin/bitcoin.conf.tmp
  mv /etc/bitcoin/bitcoin.conf.tmp /etc/bitcoin/bitcoin.conf
  echo "[✔] Perfil dApp/Developer aplicado."
}


function configurar_perfil_lightning() {
  echo -e "\n[⚙️] Aplicando perfil: Lightning Operator"
  mkdir -p /etc/bitcoin
  preservar_datos_conf
  {
    echo "prune=1000"               # Nodo podado, suficiente para operaciones Lightning (~10 GB)
    echo "txindex=0"                # No se necesita acceso total a transacciones
    echo "blockfilterindex=0"       # No se requieren filtros compactos
    echo "mempoolexpiry=336"        # Mempool activo hasta por 14 días (default), útil para LN
    echo "maxconnections=40"        # Buen número para estabilidad de pares
  } >> /etc/bitcoin/bitcoin.conf.tmp
  mv /etc/bitcoin/bitcoin.conf.tmp /etc/bitcoin/bitcoin.conf
  echo "[✔] Perfil Lightning aplicado."
}


function configurar_perfil_educador() {
  echo -e "\n[⚙️] Aplicando perfil: Educador/Estudiante"
  mkdir -p /etc/bitcoin
  preservar_datos_conf
  {
    echo "prune=1000"                # Nodo podado: bajo consumo (~10 GB)
    echo "txindex=0"                 # No es necesario índice completo
    echo "blockfilterindex=0"        # Desactivado por simplicidad
    echo "assumevalid=0"              # Desactiva validación de firmas de bloques anteriores
    echo "maxconnections=20"         # Fewer peers to reduce CPU/RAM use
    echo "mempoolexpiry=72"          # Reducción del tiempo de transacciones en mempool
    echo "dbcache=100"               # Menor uso de RAM (~100 MB)
  } >> /etc/bitcoin/bitcoin.conf.tmp
  mv /etc/bitcoin/bitcoin.conf.tmp /etc/bitcoin/bitcoin.conf
  echo "[✔] Perfil Educador/Estudiante aplicado."
}



#========== INSTALAR BITCOIN CORE ==========#

function instalar_dependencias() {
  echo -e "\n[+] Instalando dependencias básicas..."
  apt update && apt-get install -y --no-install-recommends \
    build-essential cmake pkgconf python3 \
    libevent-dev libboost-dev libsqlite3-dev libzmq3-dev \
    jq git lsb-release iproute2 ca-certificates
  echo "[✔] Dependencias instaladas."
}

function crear_usuario_y_directorio() {
  echo -e "\n[+] Verificando existencia del usuario 'bitcoin'..."
  if id "bitcoin" &>/dev/null; then
    echo "[✔] Usuario 'bitcoin' ya existe."
  else
    echo "[+] Creando usuario 'bitcoin' con permisos limitados..."
    useradd -m -s /bin/bash bitcoin
    echo "[✔] Usuario 'bitcoin' creado."
  fi
  mkdir -p /opt/BLOCKCHAIN
  chown bitcoin:bitcoin /opt/BLOCKCHAIN
  echo "[✔] Directorio /opt/BLOCKCHAIN creado y asignado a usuario bitcoin."
}

function compilar_bitcoin() {
  echo -e "\n[+] Clonando repositorio Bitcoin Core v29.0..."
  sudo -u bitcoin git clone https://github.com/bitcoin/bitcoin.git /home/bitcoin/bitcoin
  cd /home/bitcoin/bitcoin || exit 1
  sudo -u bitcoin git checkout v29.0

  echo -e "\n[+] ¿Desea compilar con soporte para ZMQ?"
  read -p "[s/N]: " resp_zmq

  local zmq_flag=""
  [[ "$resp_zmq" =~ ^[Ss]$ ]] && zmq_flag="-DWITH_ZMQ=ON"

  echo -e "\n[+] Compilando Bitcoin Core..."
  sudo -u bitcoin cmake -B build $zmq_flag
  sudo -u bitcoin cmake --build build -j$(nproc)
  cmake --install build
  echo "[✔] Bitcoin Core compilado e instalado."
}

function configurar_servicio() {
  echo -e "\n[+] Configurando servicio systemd para bitcoind..."
  cat > /etc/systemd/system/bitcoind.service <<EOF
[Unit]
Description=Bitcoin daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/bitcoind -conf=/etc/bitcoin/bitcoin.conf -pid=/run/bitcoind/bitcoind.pid
ExecStop=/usr/local/bin/bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf stop
User=bitcoin
Group=bitcoin
Type=forking
PIDFile=/run/bitcoind/bitcoind.pid
Restart=on-failure
RuntimeDirectory=bitcoind

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable bitcoind
  echo "[✔] Servicio systemd creado y habilitado."
}

function generar_rpc_auth() {
  echo -e "\n[+] Generando credenciales RPC..."
  mkdir -p /home/bitcoin/.bitcoin
  chown bitcoin:bitcoin /home/bitcoin/.bitcoin
  local salida=$(sudo -u bitcoin python3 /home/bitcoin/bitcoin/share/rpcauth/rpcauth.py bitcoin)
  local rpcauth_line=$(echo "$salida" | grep '^rpcauth=')
  local password_line=$(echo "$salida" | tail -n 1)

  # Configurar /etc/bitcoin/bitcoin.conf
  mkdir -p /etc/bitcoin
  [[ -f /etc/bitcoin/bitcoin.conf ]] && cp /etc/bitcoin/bitcoin.conf /etc/bitcoin/bitcoin.conf.bak
  echo "# bitcoin.conf generado por el script de instalación" > /etc/bitcoin/bitcoin.conf
  echo "server=1" >> /etc/bitcoin/bitcoin.conf
  echo "daemon=1" >> /etc/bitcoin/bitcoin.conf
  echo "datadir=/opt/BLOCKCHAIN" >> /etc/bitcoin/bitcoin.conf
  echo "$rpcauth_line" >> /etc/bitcoin/bitcoin.conf

  # Configurar ~/.bitcoin/bitcoin.conf del usuario bitcoin
  [[ -f /home/bitcoin/.bitcoin/bitcoin.conf ]] && cp /home/bitcoin/.bitcoin/bitcoin.conf /home/bitcoin/.bitcoin/bitcoin.conf.bak
  echo "rpcuser=bitcoin" > /home/bitcoin/.bitcoin/bitcoin.conf
  echo "rpcpassword=$password_line" >> /home/bitcoin/.bitcoin/bitcoin.conf
  echo "datadir=/opt/BLOCKCHAIN" >> /home/bitcoin/.bitcoin/bitcoin.conf
  chown bitcoin:bitcoin /home/bitcoin/.bitcoin/bitcoin.conf
  chmod 600 /home/bitcoin/.bitcoin/bitcoin.conf
  echo "[✔] RPC configurado correctamente."
  echo "[🔐] Contraseña RPC generada: $password_line"
  echo "[🗂] Archivos de configuración:"
  echo " - /etc/bitcoin/bitcoin.conf"
  echo " - /home/bitcoin/.bitcoin/bitcoin.conf"
}

#========== REGISTRAR DATOS PARA ESTUDIOS ==========#

function iniciar_monitoreo() {
  echo "[📊] Iniciando monitoreo de recursos..."

  # Esperar a que bitcoin-cli esté disponible
  echo "[⌛] Esperando a que bitcoin-cli esté disponible en el sistema..."
  while ! command -v bitcoin-cli &>/dev/null; do
    sleep 5
  done
  echo "[✔] bitcoin-cli encontrado."

  # Esperar a que el nodo entre en IBD
  echo "[⌛] Esperando a que el nodo inicie la descarga inicial (IBD)..."
  while true; do
    INFO=$(bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf getblockchaininfo 2>/dev/null)
    if [[ $? -eq 0 && -n "$INFO" ]]; then
      IBD=$(echo "$INFO" | jq -r '.initialblockdownload')
      if [[ "$IBD" == "true" ]]; then
        echo "[🚀] Ya esta instalado Bitcoin. Nodo en proceso de sincronización..."
        echo "     Puedes seguir trabajando sin problemas mientras se sincroniza..."
        break
      elif [[ "$IBD" == "false" ]]; then
        echo "[✔] Nodo ya está sincronizado. No se registrará nada."
        exit 0
      fi
    fi
    sleep 10
  done
}

function iniciar_monitoreo_log() {
  echo "[📊] Iniciando monitoreo de recursos..."

  PERFIL="${1:-desconocido}"
  INTERFAZ=$(ip route get 8.8.8.8 | awk '{print $5}')
  TS=$(date +%Y%m%d_%H%M%S)
  LOGFILE="/var/log/bitcoin-monitor/sync_log_${PERFIL}_${TS}.csv"

  # Esperar a que bitcoin-cli esté disponible
  echo "[⌛] Esperando a que bitcoin-cli esté disponible en el sistema..."
  while ! command -v bitcoin-cli &>/dev/null; do
    sleep 5
  done
  echo "[✔] bitcoin-cli encontrado."

  # Esperar a que el nodo entre en IBD
  echo "[⌛] Esperando a que el nodo inicie la descarga inicial (IBD)..."
  while true; do
    INFO=$(bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf getblockchaininfo 2>/dev/null)
    if [[ $? -eq 0 && -n "$INFO" ]]; then
      IBD=$(echo "$INFO" | jq -r '.initialblockdownload')
      if [[ "$IBD" == "true" ]]; then
        echo "[🚀] Nodo en proceso de sincronización. Iniciando registro de métricas..."
        # Crear archivo con cabecera
          echo "ciclo;timestamp;profile;blocks;headers;verificationprogress;cpu_percent;mem_percent;disk_used_MB;net_rx_kB;net_tx_kB" > "$LOGFILE"

          # Comenzar a registrar métricas mientras dure la sincronización
          CICLO=0
          while true; do
            INFO=$(bitcoin-cli -conf=/etc/bitcoin/bitcoin.conf getblockchaininfo 2>/dev/null)
            if [[ $? -eq 0 && -n "$INFO" ]]; then
              IBD=$(echo "$INFO" | jq -r '.initialblockdownload')

              TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
              BLOCKS=$(echo "$INFO" | jq '.blocks')
              HEADERS=$(echo "$INFO" | jq '.headers')
              PROGRESS=$(echo "$INFO" | jq '.verificationprogress')

              CPU_PERCENT=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
              MEM_PERCENT=$(free | awk '/Mem/ {printf("%.2f", $3/$2 * 100)}')
              DISK_USED=$(df -m /opt/BLOCKCHAIN | awk 'NR==2 {print $3}')

              NET_RX=$(cat /sys/class/net/$INTERFAZ/statistics/rx_bytes 2>/dev/null || echo 0)
              NET_TX=$(cat /sys/class/net/$INTERFAZ/statistics/tx_bytes 2>/dev/null || echo 0)
              NET_RX_KB=$((NET_RX / 1024))
              NET_TX_KB=$((NET_TX / 1024))

              echo "$CICLO;$TIMESTAMP;$PERFIL;$BLOCKS;$HEADERS;$PROGRESS;$CPU_PERCENT;$MEM_PERCENT;$DISK_USED;$NET_RX_KB;$NET_TX_KB" >> "$LOGFILE"
              ((CICLO++))
              if [[ "$IBD" == "false" ]]; then
                echo "[✔] Sincronización completa. Registro finalizado."
                echo "[✔] Monitoreo completado. Archivo generado: $LOGFILE"
                break
              fi
            fi
            sleep 60
          done
          monitoreo_post_1hora "$PERFIL"
        break
      elif [[ "$IBD" == "false" ]]; then
        echo "[✔] Nodo ya está sincronizado. No se registrará nada."
        exit 0
      fi
    fi
    sleep 10
  done
}

function monitoreo_post_1hora() {
  PERFIL="${1:-desconocido}"
  INTERFAZ=$(ip route get 8.8.8.8 | awk '{print $5}')
  TS=$(date +%Y%m%d_%H%M%S)
  LOGFILE="/var/log/bitcoin-monitor/post_sync_metrics_${PERFIL}_${TS}.csv"

  # Escribir cabecera
  echo "ciclo;timestamp;profile;cpu_percent;cpu_cores;load_1min;load_5min;load_15min;mem_used_MB;mem_free_MB;swap_used_MB;swap_free_MB;disk_used_MB;disk_avail_MB;net_rx_kB;net_tx_kB;uptime_minutes;num_processes" > "$LOGFILE"

  echo "[📊] Monitoreando sistema durante 1 hora (registro cada 60 segundos)..."
  CICLO=0
  for i in {1..60}; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # CPU
    CPU_PERCENT=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    CPU_CORES=$(nproc)

    # Carga promedio
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | sed 's/ //g')
    LOAD_1=$(echo $LOAD | cut -d',' -f1)
    LOAD_5=$(echo $LOAD | cut -d',' -f2)
    LOAD_15=$(echo $LOAD | cut -d',' -f3)

    # Memoria
    MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    MEM_FREE=$(free -m | awk '/Mem:/ {print $4}')
    SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
    SWAP_FREE=$(free -m | awk '/Swap:/ {print $4}')

    # Disco
    DISK_USED=$(df -m /opt/BLOCKCHAIN | awk 'NR==2 {print $3}')
    DISK_AVAIL=$(df -m /opt/BLOCKCHAIN | awk 'NR==2 {print $4}')

    # Red
    RX_BYTES=$(cat /sys/class/net/$INTERFAZ/statistics/rx_bytes 2>/dev/null || echo 0)
    TX_BYTES=$(cat /sys/class/net/$INTERFAZ/statistics/tx_bytes 2>/dev/null || echo 0)
    NET_RX_KB=$((RX_BYTES / 1024))
    NET_TX_KB=$((TX_BYTES / 1024))

    # Uptime y procesos
    UPTIME_MIN=$(awk '{print int($1/60)}' /proc/uptime)
    PROC_COUNT=$(ps -e --no-headers | wc -l)

    echo "$CICLO;$TIMESTAMP;$PERFIL;$CPU_PERCENT;$CPU_CORES;$LOAD_1;$LOAD_5;$LOAD_15;$MEM_USED;$MEM_FREE;$SWAP_USED;$SWAP_FREE;$DISK_USED;$DISK_AVAIL;$NET_RX_KB;$NET_TX_KB;$UPTIME_MIN;$PROC_COUNT" >> "$LOGFILE"
    ((CICLO++))
    sleep 60
  done

  echo "[✔] Monitoreo post-sincronización completado. Archivo generado: $LOGFILE"
}


#========== MENU PERFILES ==========#

function completa() {
  perfil_nombre="estandar"
  configurar_perfil_estandar
  
  echo "[+] Perfil aplicado: $perfil_nombre"
  systemctl restart bitcoind
  if [[ "$log" == "1" ]]; then
    iniciar_monitoreo_log "$perfil_nombre"
  else
    iniciar_monitoreo
  fi
}


function menu_perfiles() {
  echo -e "\nSeleccione un perfil:"
  echo "1) Validador/Operador"
  echo "2) Analista de datos"
  echo "3) dApp / Wallet Developer"
  echo "4) Lightning Operator"
  echo "5) Educador / Estudiante"
  echo "6) Volver"
  echo "0) Configuración estándar (valores por defecto)"

  read -p "Opción: " perfil
  export perfil
  case $perfil in
    0)
      perfil_nombre="estandar"
      configurar_perfil_estandar
      ;;
    1)
      perfil_nombre="validador"
      configurar_perfil_validador
      ;;
    2)
      perfil_nombre="analista"
      configurar_perfil_analista
      ;;
    3)
      perfil_nombre="dapps"
      configurar_perfil_dapps
      ;;
    4)
      perfil_nombre="lightning"
      configurar_perfil_lightning
      ;;
    5)
      perfil_nombre="educador"
      configurar_perfil_educador
      ;;
    6)
      menu_inicio
      return
      ;;
    *)
      echo "Opción inválida"
      return
      ;;
  esac

  export perfil_nombre
  echo "[+] Perfil aplicado: $perfil_nombre"
  systemctl restart bitcoind
  if [[ "$log" == "1" ]]; then
    iniciar_monitoreo_log "$perfil_nombre"
  else
    iniciar_monitoreo
  fi
}


#========== MENUS ==========#

function logo() {
  clear
  echo -e "\e[1;32m"
  echo "==================================================================="
  echo "         🚀 Script de Instalación y Monitoreo de Bitcoin Core"
  echo "==================================================================="
  echo " Proyecto de Trabajo Fin de Máster (TFM) - Ingeniería Informática"
  echo "            Universidad de Valladolid - 2025"
  echo "-------------------------------------------------------------------"
  echo " Desarrollado por: José Ulloa"
  echo " Licencia: MIT"
  echo -e "\e[0m"
  echo ""
  sleep 2
}


function menu_inicio() {
  logo
  verificar_root
  verificar_requisitos

  if detectar_instalacion_bitcoin; then
    detectar_perfil_actual
    echo -e "\n¿Qué desea hacer ahora?"
    echo "1) Cambiar perfil de configuración"
    echo "2) Desinstalar Bitcoin Core"
    echo "3) Salir"
    read -p "Seleccione una opción: " opcion
    case $opcion in
      1) menu_perfiles;;
      2) desinstalar_bitcoin;;
      3) exit 0;;
      *) echo "Opción inválida.";;
    esac
  else
    echo -e "\nBitcoin Core no está instalado. ¿Qué desea hacer?"
    echo "1) Instalación completa"
    echo "2) Instalación por perfil"
    echo "3) Salir"
    read -p "Seleccione una opción: " opcion
    case $opcion in
      1) instalar_dependencias; crear_usuario_y_directorio; compilar_bitcoin; configurar_servicio; generar_rpc_auth; completa; systemctl start bitcoind;;
      2) instalar_dependencias; crear_usuario_y_directorio; compilar_bitcoin; configurar_servicio; generar_rpc_auth; menu_perfiles;;
      3) exit 0;;
      *) echo "Opción inválida.";;
    esac
  fi
}

#========== EJECUCIÓN ==========#
if [[ "$1" == "-log" ]]; then
  # Ejecutar solo el monitoreo (por ejemplo, para nodos ya sincronizados o pruebas)
  mkdir -p /var/log/bitcoin-monitor
  log=1
  menu_inicio
else
  log=0
  menu_inicio
fi