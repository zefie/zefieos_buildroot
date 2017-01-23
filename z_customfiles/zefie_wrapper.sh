#!/bin/bash

export DIALOGRC="/etc/zefie/dialogrc"

REBOOT_TYPE=""
DOHALT=0

# Turn off console logging
dmesg -n 1

# Enable volume and power keys for menu
loadkeys -c -s /etc/zefie/keymap

# Clear Screen
clear

/sbin/zefie
CODE=$?
case $CODE in
	69)
		# Custom code to restart script
		# Just exit cleanly, inittab will respawn
		exit 0
		;;
	70)
		# User requested reboot, proceed without error
		REBOOT_TYPE=""
		;;
	71)
		# User requested halt, proceed without error
		DOHALT=1
		;;
	72)
		# User requested reboot to recovery, proceed without error
		REBOOT_TYPE="recovery"
		;;
	73)
		# User requested reboot to bootloader, proceed without error
		REBOOT_TYPE="bootloader"
		;;
	*)
		echo "Process failed with error code ${CODE}"
		;;
esac

if [ "${DOHALT}" == "1" ]; then
	echo -n "Shutting down in "
else
	echo -n "Rebooting in "
fi
for i in 5 4 3 2 1; do
	echo -n "${i} "
	sleep 1
done
echo "..."

if [ "${DOHALT}" == "1" ]; then
	/sbin/halt
else
	/sbin/reboot ${REBOOT_TYPE}
fi

