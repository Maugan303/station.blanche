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

# Surveillance des événements udev pour les périphériques de type bloc (disques, partitions)
udevadm monitor --udev --subsystem-match=block --property | while IFS= read -r line; do
    if [[ -z "$line" ]]; then
        if [[ "$ACTION" == "add" ]] && [[ "$ID_BUS" == "usb" ]] && [[ -n "$DEVNAME" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ACTION=$ACTION DEVTYPE=$DEVTYPE DEVNAME=$DEVNAME ID_BUS=$ID_BUS"

            # On doit attendre que les partitions soient créées pour les disques, sinon on risque de scanner le disque lui-même sans les partitions, ce qui n'est pas souhaitable. Donc on vérifie si c'est une partition ou un disque, et dans le cas d'un disque on attend que les partitions soient créées avant de lancer le scan.
            # Si c'est une partition, on peut lancer le scan immédiatement. Si c'est un disque, on vérifie s'il a des partitions : s'il n'en a pas, on lance le scan immédiatement, sinon on attend que les événements de création de partitions soient traités avant de lancer le scan.
            BASEDEV=$(basename "$DEVNAME")
            SHOULD_SCAN=false
            if [[ "$DEVTYPE" == "partition" ]]; then
                SHOULD_SCAN=true
            elif [[ "$DEVTYPE" == "disk" ]]; then
                # Count lines from lsblk for this device: >1 means there are partitions
                parts_count=$(lsblk -ln -o NAME "/dev/$BASEDEV" 2>/dev/null | wc -l || true)
                if [[ -z "$parts_count" ]] || [[ "$parts_count" -le 1 ]]; then
                    SHOULD_SCAN=true
                else
                    SHOULD_SCAN=false
                fi
            fi

            # Si l'événement ne doit pas déclencher de scan (ex: périphérique non pertinent), on l'ignore
            if [[ "$SHOULD_SCAN" != true ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Événement ignoré pour $DEVNAME (attente de partition si applicable)."
            else
                # Vérifie si un scan est déjà en cours grâce au lockfile
                if [[ -f "$LOCKFILE" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Scan déjà en cours, événement ignoré."
                else
                    # Aucun scan en cours : on pose le verrou immédiatement pour bloquer tout scan concurrent
                    touch "$LOCKFILE"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Clé USB détectée ($DEVNAME), lancement du scan..."

                    # Démonte la partition si elle est déjà montée
                    # Nécessaire pour que ClamAV puisse scanner le périphérique en accès direct
                    if mount | grep -q "/dev/$DEVNAME"; then
                        echo "$(date '+%Y-%m-%d %H:%M:%S') - Démontage de /dev/$DEVNAME avant scan..."
                        umount "/dev/$DEVNAME" 2>/dev/null || true
                    fi

                    # Lancement du script de scan en arrière-plan pour ne pas bloquer la surveillance des événements udev
                    bash "$SCAN_SCRIPT" "$DEVNAME" 2>&1 &
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Scan terminé. En attente d'une nouvelle clé USB..."
                    rm -f "$LOCKFILE"
                    sleep 1
                fi
            fi
        fi
        ACTION=""
        DEVTYPE=""
        DEVNAME=""
        ID_BUS=""
        continue
    fi

        if [[ "$line" == "UDEV"* ]]; then
        ACTION=""
        DEVTYPE=""
        DEVNAME=""
        ID_BUS=""
        continue
    fi

    # Extraction des propriétés de l'événement udev
    case "$line" in
        ACTION=*) ACTION="${line#ACTION=}" ;;
        DEVTYPE=*) DEVTYPE="${line#DEVTYPE=}" ;;
        DEVNAME=*) DEVNAME="${line#DEVNAME=}" ;;
        ID_BUS=*) ID_BUS="${line#ID_BUS=}" ;;
    esac

done