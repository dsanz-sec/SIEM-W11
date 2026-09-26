#!/usr/bin/env bash
# instalar-wazuh-manager.sh
# Instala Wazuh 4.14 todo-en-uno (indexer + server + dashboard) en Parrot OS,
# abre los puertos necesarios y copia las reglas del proyecto.
#
# Uso (desde la raíz del repositorio):
#   sudo bash manager/instalar-wazuh-manager.sh [IFACE_INTERNA]
#
# IFACE_INTERNA (opcional): interfaz del segmento aislado (ej. eth1). Si se indica
# y ufw está activo, 1514/1515 solo se abren en esa interfaz.

set -euo pipefail

WAZUH_VERSION="4.14"
IFACE_INTERNA="${1:-}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "[!] Ejecuta este script con sudo." >&2
  exit 1
fi

echo "[1/5] Descargando el instalador de Wazuh ${WAZUH_VERSION}..."
cd /root
curl -sO "https://packages.wazuh.com/${WAZUH_VERSION}/wazuh-install.sh"

echo "[2/5] Instalando indexer + server + dashboard (tarda varios minutos)..."
bash ./wazuh-install.sh -a

echo "[3/5] Configurando el firewall (si ufw está activo)..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  if [[ -n "$IFACE_INTERNA" ]]; then
    ufw allow in on "$IFACE_INTERNA" to any port 1514 proto tcp   # agente -> manager
    ufw allow in on "$IFACE_INTERNA" to any port 1515 proto tcp   # enrolamiento
  else
    ufw allow 1514/tcp
    ufw allow 1515/tcp
  fi
  ufw allow 443/tcp   # dashboard (restringir a la interfaz de gestión si es posible)
else
  echo "    ufw no está activo; no se cambia nada."
fi

echo "[4/5] Copiando las reglas del proyecto..."
cp /var/ossec/etc/rules/local_rules.xml "/var/ossec/etc/rules/local_rules.xml.bak.$(date +%s)" 2>/dev/null || true
install -o wazuh -g wazuh -m 660 "${REPO_DIR}/manager/local_rules.xml" /var/ossec/etc/rules/local_rules.xml
systemctl restart wazuh-manager

echo "[5/5] Datos necesarios para el siguiente paso:"
echo
echo "--- Credenciales del dashboard (usuario admin) ---"
tar -O -xf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt | grep -A1 "'admin'" || true
echo
echo "--- Contraseña de enrolamiento de agentes ---"
echo "(Cambia cada vez que se reinicia wazuh-manager: cópiala justo antes de instalar el agente)"
sleep 5
grep "Random password" /var/ossec/logs/ossec.log | tail -n 1 || echo "No encontrada todavía; repite: sudo grep 'Random password' /var/ossec/logs/ossec.log"
echo
echo "--- IPs de este equipo (usa la del segmento interno como WAZUH_MANAGER) ---"
ip -brief -4 addr show | grep -v "^lo"
echo
echo "Dashboard: https://<IP-de-Parrot> (certificado autofirmado: el aviso del navegador es normal)"
