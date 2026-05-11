#!/bin/bash

STATION_USER="station-blanche"
SCAN_SCRIPT="/usr/local/bin/scan_usb.sh"
LOGDIR="/home/$STATION_USER/logs"
LOCKFILE="/tmp/usb_scan.lock"

mkdir -p "$LOGDIR"

# Nettoyage du lockfile au démarrage
cleanup() {
    rm -f "$LOCKFILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') — Watcher arrêté."
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT   # Nettoyage à l'arrêt du script

echo "$(date '+%Y-%m-%d %H:%M:%S') — Surveillance USB démarrée. PID=$$" 

# Vérification de la présence de udevadm
if ! command -v udevadm >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') — ERREUR : udevadm introuvable."
    exit 1
fi

# Vérification de la présence du script de scan
echo "$(date '+%Y-%m-%d %H:%M:%S') — En attente de clés USB... (Ctrl+C pour arrêter)" | tee -a "$LOGDIR/watcher.log"

ACTION=""
DEVTYPE=""
DEVNAME=""
ID_BUS=""
