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

exit 0