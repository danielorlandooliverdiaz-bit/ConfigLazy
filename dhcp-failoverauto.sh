#!/bin/bash

# ===================================================================================
# Script de Automatización para DHCP Failover
# Autor: Daniel O.
# Versión: 1.1 (Enfocado solo en DHCP)
#
# Uso:
# 1. Configura las variables en la sección de CONFIGURACIÓN.
# 2. Copia este script a ambos servidores DHCP.
# 3. Dale permisos de ejecución: chmod +x setup_dhcp_failover.sh
# 4. En el servidor primario, ejecuta: ./setup_dhcp_failover.sh primary
# 5. En el servidor secundario, ejecuta: ./setup_dhcp_failover.sh secondary
# ===================================================================================

# Salir inmediatamente si un comando falla
set -e

# --- SECCIÓN DE CONFIGURACIÓN (Modifica estas variables según tu entorno) ---

# IPs de los servidores DHCP
PRIMARY_IP="192.168.50.2"
SECONDARY_IP="192.168.50.3"

# Configuración de red y dominio
DOMAIN_NAME="4vdanielo.edu"
DNS_SERVER_IPS="192.168.50.2, 192.168.50.3" # IPs de tus servidores DNS (pueden ser los mismos)
NETWORK="192.168.50.0"
NETMASK="255.255.255.0"
GATEWAY="192.168.50.1"
DHCP_RANGE_START="192.168.50.10"
DHCP_RANGE_END="192.168.50.19"

# Reserva estática (opcional)
RESERVED_IP="192.168.50.100"
RESERVED_HOSTNAME="win-vm"
RESERVED_MAC="00:0c:29:1a:2b:3c"

# Interfaz de red interna donde escuchará el servicio DHCP
DHCP_INTERFACE="ens37"

# --- FIN DE LA SECCIÓN DE CONFIGURACIÓN ---


# Función para imprimir mensajes informativos
log() {
    echo "---------------------------------------------------------"
    echo "--> $1"
    echo "---------------------------------------------------------"
}

# Función para instalar dependencias
install_dependencies() {
    log "Actualizando repositorios e instalando isc-dhcp-server..."
    apt-get update > /dev/null
    apt-get install -y isc-dhcp-server > /dev/null
    log "Dependencia instalada."
}

# Función para configurar el DHCP Failover
configure_dhcp() {
    ROLE=$1
    if [ "$ROLE" == "primary" ]; then
        MY_IP=$PRIMARY_IP
        PEER_IP=$SECONDARY_IP
        FAILOVER_ROLE="primary"
    else
        MY_IP=$SECONDARY_IP
        PEER_IP=$PRIMARY_IP
        FAILOVER_ROLE="secondary"
    fi

    log "Generando fichero de configuración DHCP para el rol: $FAILOVER_ROLE"

    # Configurar la interfaz de escucha
    log "Configurando la interfaz de escucha en /etc/default/isc-dhcp-server"
    echo "INTERFACESv4=\"$DHCP_INTERFACE\"" > /etc/default/isc-dhcp-server

    # Usamos un "here document" para escribir el fichero de configuración completo
    cat > /etc/dhcp/dhcpd.conf << EOF
# Fichero de configuración para isc-dhcp-server (generado automáticamente)
# Rol de este servidor: $FAILOVER_ROLE

# --- Bloque de Failover ---
failover peer "dhcp-failover" {
  $FAILOVER_ROLE;
  address $MY_IP;
  port 647;
  peer address $PEER_IP;
  peer port 647;
  max-response-delay 60;
  max-unacked-updates 10;
  mclt 3600;
  split 128;
  load balance max seconds 3;
}

# --- Configuración Global ---
authoritative;
option domain-name "$DOMAIN_NAME";
option domain-name-servers $DNS_SERVER_IPS;

# --- Definición de Subred con Pool de Failover ---
subnet $NETWORK netmask $NETMASK {
  option subnet-mask $NETMASK;
  option routers $GATEWAY;

  pool {
    failover peer "dhcp-failover";
    range $DHCP_RANGE_START $DHCP_RANGE_END;
  }
}

# --- Reservas Estáticas ---
host $RESERVED_HOSTNAME {
  hardware ethernet $RESERVED_MAC;
  fixed-address $RESERVED_IP;
}
EOF

    log "Fichero /etc/dhcp/dhcpd.conf generado."
}

# Función para reiniciar y verificar servicios
restart_services() {
    log "Reiniciando el servicio ISC DHCP Server..."
    systemctl restart isc-dhcp-server

    log "Verificando el estado del servicio..."
    # Damos un par de segundos para que el servicio estabilice
    sleep 2
    systemctl is-active isc-dhcp-server

    echo ""
    log "¡Configuración de DHCP completada con éxito!"
}


# --- SCRIPT PRINCIPAL ---

# Comprobar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root o con sudo."
  exit 1
fi

# Comprobar si se ha pasado el rol (primary o secondary)
if [ -z "$1" ]; then
    echo "Error: Debes especificar un rol."
    echo "Uso: $0 [primary|secondary]"
    exit 1
fi

ROLE=$1

if [ "$ROLE" != "primary" ] && [ "$ROLE" != "secondary" ]; then
    echo "Error: El rol debe ser 'primary' o 'secondary'."
    exit 1
fi


# Ejecutar las funciones en orden
install_dependencies
configure_dhcp $ROLE
restart_services

if [ "$ROLE" == "primary" ]; then
    echo "Ahora, ejecuta este mismo script en el servidor secundario con el parámetro 'secondary'."
else
    echo "Ambos servidores están configurados. ¡Ya puedes realizar la prueba de conmutación!"
fi

