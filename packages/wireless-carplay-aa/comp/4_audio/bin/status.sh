#!/system/bin/sh
. ./scripts/common.sh
echo "libCarPlayAudio=$(audio_state) $(file_md5 $AUDIO 2>/dev/null)"
echo "libCarPlayUtils=$(utils_state) $(file_md5 $UTILS 2>/dev/null)"
if sum_eq "$CONV" "$SUM_CONV"; then echo "libleafia=present"; else echo "libleafia=absent"; fi
if [ -d "$BACKUP_DIR" ]; then echo "backup=$BACKUP_DIR"; else echo "backup=none"; fi
exit 0
