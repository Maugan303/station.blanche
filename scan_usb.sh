#!/bin/bash
 
STATION_USER="station-blanche"
LOGDIR="/home/$STATION_USER/logs"
QUARANTAINE="/home/$STATION_USER/quarantaine"
 

 
# Détection automatique de la clé USB ou récupération du périphérique passé en argument
DEVICE=""
if [[ -n "$1" ]]; then
    DEVICE=$(basename "$1") 
    if [[ ! -b "/dev/$DEVICE" ]]; then          # Vérification que le périphérique existe et est un bloc
        echo "Périphérique invalide : /dev/$DEVICE"
        exit 1
    fi
else
    # Recherche du périphérique USB connecté (en prenant la première clé trouvée)
    for dev in /sys/block/sd*; do
        if readlink -f "$dev" | grep -qi "usb"; then # Vérifie si le périphérique est connecté via USB
            BASE=$(basename "$dev")
            PART=$(lsblk -lno NAME "/dev/$BASE" | grep -v "^$BASE$" | head -1) # On prend la première partition trouvée, sinon le disque lui-même
            if [[ -n "$PART" ]]; then
                DEVICE="$PART"
            else
                DEVICE="$BASE"
            fi
            break
        fi
    done
fi

# Si aucun périphérique n'est trouvé, on affiche une erreur
if [[ -z "$DEVICE" ]]; then
    echo "Aucune clé USB détectée. Branchez une clé et relancez le script."
    exit 1
fi

echo "Clé USB détectée : $DEVICE"

MOUNTPOINT="/media/$DEVICE"
 
# Création des dossiers nécessaires
mkdir -p "$LOGDIR" "$MOUNTPOINT" "$QUARANTAINE"
 
# Horodatage
TS=$(date +"%Y-%m-%d %H:%M:%S")
TS_FILE=$(date +%Y%m%d_%H%M%S)

# 1) LOG_USB.LOG
 
USB_COUNTER_FILE="$LOGDIR/usb_counter.txt"
LOG_USB="$LOGDIR/log_usb.log"
 
 
if [[ ! -f "$USB_COUNTER_FILE" ]]; then
    echo 0 > "$USB_COUNTER_FILE"
fi

LAST_USB=$(cat "$USB_COUNTER_FILE")
NEXT_USB=$((LAST_USB + 1))
echo "$NEXT_USB" > "$USB_COUNTER_FILE"
ID_USB="$NEXT_USB"
 
NOM_USB="$DEVICE"
FILESYSTEM=$(lsblk -no FSTYPE "/dev/$DEVICE" 2>/dev/null || echo "inconnu")
DATE_INSERTION="$TS"

# démontage uniquement si le point de montage est actif
if mountpoint -q "$MOUNTPOINT"; then
    umount "$MOUNTPOINT"
fi

exit 0