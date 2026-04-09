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

# 2) LOG_SCAN.LOG
 
SCAN_COUNTER_FILE="$LOGDIR/scan_counter.txt"
LOG_SCAN="$LOGDIR/log_scan.log"
 
if [[ ! -f "$SCAN_COUNTER_FILE" ]]; then
    echo 0 > "$SCAN_COUNTER_FILE"
fi
 
LAST_SCAN=$(cat "$SCAN_COUNTER_FILE")
NEXT_SCAN=$((LAST_SCAN + 1))
echo "$NEXT_SCAN" > "$SCAN_COUNTER_FILE"
ID_SCAN="$NEXT_SCAN"
 
ETAT_SCAN="OK"
 
# Montage de la clé USB (si pas déjà montée)
if ! mountpoint -q "$MOUNTPOINT"; then
 
    mount "/dev/$DEVICE" "$MOUNTPOINT"
    
    if [[ $? -ne 0 ]]; then
        notify "Erreur" "Impossible de monter /dev/$DEVICE"
        ETAT_SCAN="ERREUR_MONTAGE"
        echo "{\"id_scan\": $ID_SCAN, \"id_usb\": $ID_USB, \"date_scan\": \"$TS\", \"nb_fichier\": 0, \"etat_scan\": \"$ETAT_SCAN\", \"infecte\": 0, \"duree\": \"0s\"}" >> "$LOG_SCAN"
        exit 1
    fi
fi
 
# Volume utilisé sur la clé
TAILLE=$(df -k "$MOUNTPOINT" 2>/dev/null | awk 'NR==2 {printf "%d", $3}' || echo "inconnu")
 
# Écriture du log USB
echo "{\"id_usb\": $ID_USB, \"nom\": \"$NOM_USB\", \"filesystem\": \"$FILESYSTEM\", \"taille\": \"$TAILLE\", \"date_insertion\": \"$DATE_INSERTION\"}" >> "$LOG_USB"
 
# Fichier log brut ClamAV
CLAMAV_RAW="$LOGDIR/clamav_raw_${TS_FILE}.log"

# Timer
START_TIME=$(date +%s)
 
# Scan ClamAV
clamscan \
    --recursive \
    --move="$QUARANTAINE" \
    --log="$CLAMAV_RAW" \
    --allmatch \
    --detect-pua=yes \
    --max-scansize=100M \
    --max-filesize=100M \
    --max-recursion=20 \
    --max-files=100000 \
    --max-dir-recursion=20 \
    --heuristic-scan-precedence=yes \
    --cross-fs=yes \
    --verbose \
    "$MOUNTPOINT"
 
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
 
# Extraction des résultats ClamAV
NB_FICHIER=$(grep "Scanned files:" "$CLAMAV_RAW" 2>/dev/null | awk '{print $3}')
INFECTE=$(grep "Infected files:" "$CLAMAV_RAW" 2>/dev/null | awk '{print $3}')
 
# valeurs par défaut si grep ne trouve rien
NB_FICHIER=${NB_FICHIER:-0}
INFECTE=${INFECTE:-0}
 
if [[ "$NB_FICHIER" -eq 0 ]] && ! grep -q "Scanned files:" "$CLAMAV_RAW" 2>/dev/null; then
    ETAT_SCAN="ERREUR_SCAN"
fi
 
if [[ "$INFECTE" -gt 0 ]]; then
    ETAT_SCAN="INFECTE"
fi
 
# Écriture du log scan
echo "{\"id_scan\": $ID_SCAN, \"id_usb\": $ID_USB, \"date_scan\": \"$TS\", \"nb_fichier\": $NB_FICHIER, \"etat_scan\": \"$ETAT_SCAN\", \"infecte\": $INFECTE, \"duree\": \"${DURATION}s\"}" >> "$LOG_SCAN"
 
 # 3) LOG_FICHIER.LOG
 
# Fichier texte servant de compteur auto-incrémenté pour les IDs fichiers
FILE_COUNTER_FILE="$LOGDIR/file_counter.txt"

# Fichier de sortie : une ligne JSON par fichier analysé
LOG_FICHIER="$LOGDIR/log_fichier.log"

# Initialise le compteur à 0 s'il n'existe pas encore
if [[ ! -f "$FILE_COUNTER_FILE" ]]; then
    echo 0 > "$FILE_COUNTER_FILE"
fi

# Vérifie que le log brut ClamAV est bien présent avant de le traiter
if [[ ! -f "$CLAMAV_RAW" ]]; then
    echo "AVERTISSEMENT: log ClamAV introuvable : $CLAMAV_RAW"
else
    sed -i 's/\r//' "$CLAMAV_RAW"
 
    # Lecture ligne par ligne du log ClamAV brut
    while IFS= read -r line; do

        if [[ "$line" == "Scanning "* ]]; then
            FILE_PATH="${line#Scanning }"
            [[ -d "$FILE_PATH" ]] && continue
            STATUT="non_infecte"
        elif [[ "$line" == /* ]] && echo "$line" | grep -qE ' FOUND$'; then
            # FIX: sed plutôt que rev/cut pour les chemins contenant ":"
            FILE_PATH=$(echo "$line" | sed 's/:[^:]*$//' | sed 's/[[:space:]]*$//')
            STATUT="infecte"
        else
            continue
        fi
 
        FILE_NAME=$(basename "$FILE_PATH")
        
        
        if [[ -f "$FILE_PATH" ]]; then
            FILE_SIZE=$(stat -c%s "$FILE_PATH" 2>/dev/null || echo 0)
        else
            FILE_SIZE=$(stat -c%s "$QUARANTAINE/$FILE_NAME" 2>/dev/null || echo 0)
        fi

        # Incrémentation du compteur d'ID
        LAST_FILE=$(cat "$FILE_COUNTER_FILE")       # Lit l'ID courant
        NEXT_FILE=$((LAST_FILE + 1))                # Calcule le prochain ID
        echo "$NEXT_FILE" > "$FILE_COUNTER_FILE"    # Persiste le nouvel ID

 
        # Écrit une ligne JSON dans le log fichier avec toutes les données
        echo "{\"id_fichier\": $NEXT_FILE, \"id_scan\": $ID_SCAN, \"nom\": \"$FILE_NAME\", \"chemin\": \"$FILE_PATH\", \"taille\": $FILE_SIZE, \"statut\": \"$STATUT\"}" >> "$LOG_FICHIER"
 
    done < "$CLAMAV_RAW"
fi

# démontage uniquement si le point de montage est actif
if mountpoint -q "$MOUNTPOINT"; then
    umount "$MOUNTPOINT"
fi

exit 0