#!/bin/bash
USBMNT="/usb"
USBPART=1
DESTMNT="/dest"
IMGROOTDIR="${USBMNT}/data"
BLOCKSIZE=4096
TWRP_TAR_FLAGS="--strip-components=1 -xp"
DIAGHEIGHT=24
DIAGWIDTH=80

LOGFILE="/zefie.log"

KERNEL_SUPPORT_REBOOT_TARGET=0
DORESTORE=0
DOPARTITION=0
DOWIPE=0
ISERROR=0
ISEMMC=0
VERIFYYES=0
NODEVS=0

set IMGDIR
set TXTPART
set SGDPART
set IMGNAME

format_disk() {
	/sbin/make_ext4fs -L "${2}" -a "/${2}" "${3}" 2>>${LOGFILE} 1>>${LOGFILE}
}


logd() {
    printf '[%s] %s\n' "$(date "+%Y-%m-%d_%H:%M:%S.%N")" "$@" >> "${LOGFILE}"
}

logn() {
    printf '%s' "$@" > /dev/console
    logd "$@"
}

log() {
    printf '%s\n' "$@" > /dev/console
    logd "$@"
}

progress_dialog() {
	echo "${3}" | dialog --keep-window --backtitle "${1}" --gauge "${2}" 10 "${DIAGWIDTH}" 0
}

mount_usb() {
	logd "Searching for USB device at ${1}..."
	while [ ! -b "${1}" ]; do
	  sleep 1
	done;


	logd "Mounting USB Device ${1} to ${2}"
	mkdir -p "${2}" 2>>${LOGFILE} 1>>${LOGFILE}
	MOUNTOPTS=${3}
	if [ -z "${MOUNTOPTS}" ]; then
		MOUNTOPTS="ro"
	fi
	mount -o ${MOUNTOPTS} -t vfat "${1}" "${2}"
}

umount_dev() {
	logd "Unmounting device ${1}"
	umount "${1}" 2>>${LOGFILE} 1>>${LOGFILE}
}

verify_md5() {
	unset SRCMD5;
	unset DATMD5;
	if [ -f "${1}.md5" ]; then
		SRCMD5=$(cut -d' ' -f1 < "${1}.md5")
		DATMD5=$(md5sum "${1}" | cut -d' ' -f1)
		logd "Source MD5: ${SRCMD5}"
		logd "  Data MD5: ${DATMD5}"
		if [ "$SRCMD5" != "$DATMD5" ]; then
			if [ -z "${2}" ]; then
				logd "[BAD MD5] ${1}"
			fi
			echo 0;
			return 0;
		fi
		if [ -z "${2}" ]; then
			logd "[Good MD5] ${1}"
		fi
		echo 1;
		return 1;
	fi
	if [ -z "${2}" ]; then
		logd "[No MD5] ${1}"
	fi
	echo 2;
	return 2;
}

restore_tar() {
	case "${1}" in
		"gz")
			cat ${2} | gzip -dc | tar ${TWRP_TAR_FLAGS} -C ${DESTMNT} 2>>${LOGFILE} 1>>${LOGFILE}
			;;
		"tar")
			cat ${2} | tar ${TWRP_TAR_FLAGS} -C ${DESTMNT} 2>>${LOGFILE} 1>>${LOGFILE}
			;;
	esac
}


write_image() {
	case "${1}" in
		"gz")
			gzip -dc "${2}" | dd of="${3}" bs=${BLOCKSIZE} 2>>${LOGFILE} 1>>${LOGFILE}
			;;
		"xz")
			xz -dc "${2}" | dd of="${3}" bs=${BLOCKSIZE} 2>>${LOGFILE} 1>>${LOGFILE}
			;;
		"bz2")
			bz2 -dc "${2}" | dd of="${3}" bs=${BLOCKSIZE} 2>>${LOGFILE} 1>>${LOGFILE}
			;;
		"raw")
			cat "${2}" | dd of="${3}" bs=${BLOCKSIZE} 2>>${LOGFILE} 1>>${LOGFILE}
			;;
	esac
}

initial_scan_image_folder() {
	mount_usb "${USBDEV}${SPL}${USBPART}" "${USBMNT}" 2>>${LOGFILE} 1>>${LOGFILE}
	for f in $(ls --sort=time -1 "${IMGROOTDIR}/"); do
		if [ -d "${IMGROOTDIR}/${f}" ] && [ -f "${IMGROOTDIR}/${f}/restore.txt" ]; then
			IMGNAME="${f}"
			IMGDIR="${IMGROOTDIR}/${IMGNAME}/images"
			SGDPART="${IMGROOTDIR}/${IMGNAME}/table/sgdisk.bin"
			TXTPART="${IMGROOTDIR}/${IMGNAME}/restore.txt"
			break;
		fi
	done;
	umount_dev "${USBDEV}${SPL}${USBPART}"
}

select_image_folder() {
	unset DIAGOPTS_BROWSE;

	mount_usb "${USBDEV}${SPL}${USBPART}" "${USBMNT}"
	for f in $(ls -1 "${IMGROOTDIR}/"); do
		if [ -d "${IMGROOTDIR}/${f}" ] && [ -f "${IMGROOTDIR}/${f}/restore.txt" ]; then
			if [ -f "${IMGROOTDIR}/${f}/info.txt" ]; then
				DIAGOPTS_BROWSE+=("${f}" "$(cat "${IMGROOTDIR}/${f}/info.txt")");
			else
				DIAGOPTS_BROWSE+=("${f}" "No Description");
			fi
		fi
	done;
	if [ -z "${DIAGOPTS_BROWSE}" ]; then
		dialog --backtitle "Zefie's Ares8 eMMC Recovery System" --msgbox "No backup folders available\n\nPlease see README.txt" 10 45
	else
		DIAGTITLE="Select Backup Image"
		DIAGMENU="Please select the image you wish to restore"
		exec 3>&1
		RESULT=$(dialog --nocancel --backtitle "${DIAGTITLE}" --menu "${DIAGMENU}" "${DIAGHEIGHT}" "${DIAGWIDTH}" "${DIAGHEIGHT}" "${DIAGOPTS_BROWSE[@]}" 2>&1 1>&3)
		exec 3>&-;
		IMGNAME="${RESULT}"
		IMGDIR="${IMGROOTDIR}/${IMGNAME}/images"
		SGDPART="${IMGROOTDIR}/${IMGNAME}/table/sgdisk.bin"
		TXTPART="${IMGROOTDIR}/${IMGNAME}/restore.txt"
	fi
	umount_dev "${USBDEV}${SPL}${USBPART}"
}

set_usb_dev() {
	USBDEV="${1}"
	if [ "$(echo "${USBDEV}" | /usr/bin/grep -c mmc)" == "1" ]; then
		SPL="p";
	else
		SPL="";
	fi
}

set_dest_dev() {
	DESTDEV="${1}"
	if [ "$(echo "${DESTDEV}" | /usr/bin/grep -c mmc)" == "1" ]; then
		PL="p";
		ISEMMC=1
	else
		PL="";
	fi
}
browse_devices() {
	unset DIAGOPTS_BROWSE;

	for f in $(find /dev | /usr/bin/grep -Eo '\/dev\/[shm][dm][a-z](blk[0-9])?(?!0-9)*' | sort -u); do
		if [ -b "${f}" ]; then
			DIAGOPTS_BROWSE+=("${f}" "${f}");
		fi
	done;
	if [ "${1}" == "usb" ]; then
		DIAGTITLE="Select USB Root Device"
		DIAGMENU="Please select the root device of your USB"
	fi
	if [ "${1}" == "dest" ]; then
		DIAGTITLE="Select Destination Root Device"
		DIAGMENU="Please select the root device of your destination drive"
	fi
	exec 3>&1
	RESULT=$(dialog --nocancel --backtitle "${DIAGTITLE}" --menu "${DIAGMENU}" "${DIAGHEIGHT}" "${DIAGWIDTH}" "${DIAGHEIGHT}" "${DIAGOPTS_BROWSE[@]}" 2>&1 1>&3)
	exec 3>&-;
	if [ "${1}" == "usb" ]; then
		set_usb_dev "${RESULT}"
	fi
	if [ "${1}" == "dest" ]; then
		set_dest_dev "${RESULT}"
	fi
	if [ -b "$DESTDEV" ] && [ -b "$USBDEV" ] && [ "$NODEVS" == "1" ]; then
		NODEVS=0;
	fi
}


check_result() {
	if [ "${1}" -ne 0 ]; then
		ISERROR=1
		logd "Previous operation exited with error code ${1}"
	fi
}

confirm_menu() {
	dialog --defaultno --backtitle "Confirm Data Destruction" \
		--yesno "The action you have selected will cause permanent data loss.\n\nAre you sure you wish to continue?" 10 50
	CODE=$?
	if [ "$CODE" == "0" ]; then
		VERIFYYES=1;
	else
		VERIFYYES=0;
	fi
}

do_log_copy() {
	mount_usb "${USBDEV}${SPL}${USBPART}" "${USBMNT}" "rw"
	rm -f /usb/zefie.log
	cp "${LOGFILE}" /usb/zefie.log
	if [ -f "/usb/zefie.log" ]; then
		USBSUCCESS=1
	fi
	umount_dev "${USBDEV}${SPL}${USBPART}"
	if [ "$USBSUCCESS" == "1" ]; then
		dialog --backtitle "Zefie's Ares8 eMMC Recovery System" --msgbox "Log files copied to USB" 5 30
	else
		dialog --backtitle "Zefie's Ares8 eMMC Recovery System" --msgbox "There was an error copying the log files to USB" 5 50
	fi
}

do_start_menu() {
	mount_usb "${USBDEV}${SPL}${USBPART}" "${USBMNT}" 2>>${LOGFILE} 1>>${LOGFILE}
	if [ "$NODEVS" == "1" ]; then
		DIAGOPTS=("View Log" "View the log from the restore process"
			  "Copy Log to USB" "Copies the log files to the root of the USB"
			  "" ""
			  "Define USB Dev" "Requires keyboard. Current value: ${USBDEV}"
			  "Define Destination Dev" "Requires keyboard. Current value: ${DESTDEV}"
			  "Enter Shell" "Keyboard required."
			  "" ""
			  "Reboot" "Cancel and do not touch eMMC"
			  "Shutdown" "Cancel and do not touch eMMC")
		DIAGTITLE="Zefie's Ares8 eMMC Recovery System - No Devices Configured"
	elif [ ! -d "${IMGDIR}" ] || [ ! -f "${TXTPART}" ]; then
		DIAGOPTS=("Change Backup" "Select backup folder. Current: none"
			  "Wipe Only" "Wipe, but do not restore data"
			  "" ""
			  "View Log" "View the log from the restore process"
			  "Copy Log to USB" "Copies the log files to the root of the USB"
			  "" ""
			  "Define USB Dev" "USB Source Device. Current value: ${USBDEV}"
			  "Define Dest Dev" "Restore Target. Current value: ${DESTDEV}"
			  "Enter Shell" "Keyboard required."
			  "" ""
			  "Reboot" "Cancel and do not touch eMMC"
			  "Shutdown" "Cancel and do not touch eMMC")
		DIAGTITLE="Zefie's Ares8 eMMC Recovery System"

	else
		DIAGOPTS=("Change Backup" "Select backup folder. Current: ${IMGNAME}"
		          "" ""
			  "Full Restore" "Completely erase target and restore partitions"
			  "Data Restore" "Restore partitions, but do not reparititon"
			  "Custom Restore" "Select what to restore"
			  "Wipe Only" "Wipe, but do not restore data"
			  "Partition Only" "Wipe and partition, but do not restore data"
			  "" ""
			  "View Log" "View the log from the restore process"
			  "Copy Log to USB" "Copies the log files to the root of the USB"
			  "" ""
			  "Define USB Dev" "USB Source Device. Current value: ${USBDEV}"
			  "Define Dest Dev" "Restore Target. Current value: ${DESTDEV}"
			  "Enter Shell" "Keyboard required."
			  "" ""
			  "Reboot" "Cancel and do not touch eMMC"
			  "Shutdown" "Cancel and do not touch eMMC")
		DIAGTITLE="Zefie's Ares8 eMMC Recovery System"
	fi
	umount_dev "${USBDEV}${SPL}${USBPART}"
	exec 3>&1
	RESULT=$(dialog --nocancel --backtitle "${DIAGTITLE}" --menu "Please select an action" "${DIAGHEIGHT}" "${DIAGWIDTH}" "${DIAGHEIGHT}" "${DIAGOPTS[@]}" 2>&1 1>&3)
	exec 3>&-;

	case "$RESULT" in
		"")
			do_start_menu
			;;
		"Define USB Dev")
			browse_devices usb
			do_start_menu
			;;
		"Change Backup")
			select_image_folder
			do_start_menu
			;;
		"Custom Restore")
			# DOSHIT
			;;
		"Define Dest Dev")
			browse_devices dest
			do_start_menu
			;;
		"Full Restore")
			confirm_menu
			if [ "${VERIFYYES}" != "1" ]; then
				do_start_menu;
			fi
			DORESTORE=1
			DOWIPE=1
			DOPARTITION=1
			;;
		"Data Restore")
			confirm_menu
			if [ "${VERIFYYES}" != "1" ]; then
				do_start_menu;
			fi
			DORESTORE=1
			DOWIPE=0
			DOPARTITION=0
			;;
		"Reboot")
			exit 70;
			;;
		"Shutdown")
			exit 71;
			;;
		"View Log")
			dialog --exit-label "Back" --backtitle "Zefie's Ares8 eMMC Recovery System" --textbox "${LOGFILE}" "${DIAGHEIGHT}" "${DIAGWIDTH}"
			do_start_menu
			;;
		"Copy Log to USB")
			do_log_copy
			do_start_menu
			;;
		"Enter Shell")
			umount_dev "${USBDEV}${SPL}${USBPART}"
			/bin/bash
			exit 69;
			;;
		"Wipe Only")
			confirm_menu
			if [ "${VERIFYYES}" != "1" ]; then
				do_start_menu;
			fi
			DORESTORE=0
			DOWIPE=1
			DOPARTITION=0
			;;
		"Partition Only")
			confirm_menu
			if [ "${VERIFYYES}" != "1" ]; then
				do_start_menu;
			fi
			DORESTORE=0
			DOWIPE=1
			DOPARTITION=1
			;;
	esac
}

do_end_menu() {
	unset STRTITLE
	unset DIAGOPTS
	DIAGOPTS=("View Log" "View the log from the restore process" \
        "Copy Log to USB" "Copies the log files to the root of the USB"
 	"" "");
	case "${1}" in
		"0")
			STRTITLE="Successfully completed - What would you like to do?"
			DIAGOPTS+=("Restart Restore" "Relaunch this script");
			;;
		"1")
			STRTITLE="There was an error during the restore process"
			DIAGOPTS+=("Retry Restore" "Relaunch this script and try again");
			;;
	esac

	DIAGOPTS+=("Reboot System" "Boot into your restored system")
	if [ "${KERNEL_SUPPORT_REBOOT_TARGET}" == "1" ]; then
		DIAGOPTS+=("Reboot Recovery" "Boot into recovery" \
			   "Reboot Bootloader" "Boot into Fastboot");
	fi

	DIAGOPTS+=("" "" \
		   "Enter Shell" "Keyboard required");
	exec 3>&1
	RESULT=$(dialog --no-cancel --backtitle "Zefie's Ares8 eMMC Recovery System" \
		--menu "${STRTITLE}" "${DIAGHEIGHT}" "${DIAGWIDTH}" "${DIAGHEIGHT}" \
		"${DIAGOPTS[@]}" 2>&1 1>&3)
	exec 3>&-;


	case "$RESULT" in
		"")
			do_end_menu "${1}"
			;;
		"View Log")
			dialog --exit-label "Back" --backtitle "Zefie's Ares8 eMMC Recovery System" --textbox "${LOGFILE}" "${DIAGHEIGHT}" "${DIAGWIDTH}"
			do_end_menu "${1}"
			;;
		"Copy Log to USB")
			do_log_copy
			do_end_menu "${1}"
			;;
		"Retry Restore" | "Restart Restore")
			exit 69;
			;;
		"Reboot System")
			exit 0;
			;;
		"Reboot Recovery")
			exit 71;
			;;
		"Reboot Bootloader")
			exit 72;
			;;
		"Enter Shell")
			umount_dev "${USBDEV}${SPL}${USBPART}"
			/bin/bash
			do_end_menu "${1}"
			;;
	esac
}


restore_data() {
	IMGEXT=$(echo "${3}" | rev | cut -d'.' -f1 | rev)
	if [ "${IMGEXT}" == "win" ]; then
		WINTYPE=$(echo "${3}" | rev | cut -d'.' -f2 | rev)
		if [ "${WINTYPE}" == "emmc" ]; then
			logd "Restoring TWRP eMMC image to ${2}"
			progress_dialog "Restoring data" "Restoring TWRP eMMC image to ${2}" "${4}"
			MD5RES=$(verify_md5 "${IMGDIR}/${3}")
			if [ "${MD5RES}" == "1" ] || [ "${MD5RES}" == "2" ]; then
				write_image raw "${IMGDIR}/${3}" "${DESTDEV}${PL}${1}"
				check_result $?
			else
				ISERROR=1
			fi
		fi
		if [ "$WINTYPE" == "ext2" ] || [ "$WINTYPE" == "ext3" ] || [ "$WINTYPE" == "ext4" ]; then
			format_disk "${WINTYPE}" "${2}" "${DESTDEV}${PL}${1}"
			mkdir -p "${DESTMNT}" 2>>${LOGFILE} 1>>${LOGFILE}
			mount -t "${WINTYPE}" "${DESTDEV}${PL}${1}" ${DESTMNT}
			if [ -f "${IMGDIR}/${3}" ]; then
				ISGZ=$(file "${IMGDIR}/${3}" | /usr/bin/grep gzip -c)
				if [ "$ISGZ" == "1" ]; then
					logd "Restoring TWRP compressed ${WINTYPE} image to ${2}"
					progress_dialog "Restoring data" "Restoring TWRP compressed ${WINTYPE} image to ${2}" "${4}"
					RESTYPE=gz
				else
					logd "Restoring TWRP ${WINTYPE} image to ${2}"
					progress_dialog "Restoring data" "Restoring TWRP ${WINTYPE} image to ${2}" "${4}"
					RESTYPE=tar
				fi
				MD5RES=$(verify_md5 "${IMGDIR}/${3}")
				if [ "${MD5RES}" == "1" ] || [ "${MD5RES}" == "2" ]; then
					restore_tar $RESTYPE "${IMGDIR}/${3}"
					check_result $?
				else
					ISERROR=1
				fi
			elif [ -f "${IMGDIR}/${3}000" ]; then
				ISGZ=$(file "${IMGDIR}/${3}000" | /usr/bin/grep -c gzip)
				if [ "$ISGZ" == "1" ]; then
					logd "Restoring TWRP compressed split ${WINTYPE} image to ${2}"
					progress_dialog "Restoring data" "Restoring TWRP compressed split ${WINTYPE} image to ${2}" "${4}"
					RESTYPE=gz
				else
					logd "Restoring TWRP split ${WINTYPE} image to ${2}"
					progress_dialog "Restoring data" "Restoring TWRP split ${WINTYPE} image to {2}" "${4}"
					RESTYPE=tar
				fi
				for w in $(ls -1 ${IMGDIR}/${3}*); do
					if [ -f "${w}" ]; then
						EXT=$(echo "${w}" | rev | cut -d'.' -f1 | rev)
						if [ "$EXT" != "md5" ]; then
							WINFILESU="${WINFILESU} ${w}"
							MD5RES=$(verify_md5 "${w}" 1)
							if [ "${MD5RES}" == "1" ] || [ "${MD5RES}" == "2" ]; then
								WINFILES="${WINFILES} ${w}"
								if [ "${MD5RES}" == "1" ]; then
									WINFILESM="${WINFILESM} ${w}"
								fi
							fi
						fi
					fi
				done;
				if [ "$WINFILESM" != "$WINFILES" ]; then
					logd "[Good MD5] ${WINFILES}"
				elif [ "$WINFILESU" != "$WINFILES" ]; then
					ISERROR=1
					SKIPPART=1
					logd "[BAD MD5] ${WINFILES}"
				else
					logd "[No MD5] ${WINFILES}"
				fi
				if [ -z "$SKIPPART" ]; then
					ISGZ=$(file "${IMGDIR}/${3}000" | /usr/bin/grep -c gzip)
					restore_tar $RESTYPE "${WINFILES}"
					check_result $?
					logd "Syncronizing data to disk..."
					sync
				else
					ISERROR=1
				fi
				umount_dev "${DESTDEV}${PL}${1}"
			fi
		fi
	elif [ "$IMGEXT" == "xz" ]; then
		logd "Restoring xz compressed raw image to ${2}"
		progress_dialog "Restoring data" "Restoring xz compressed raw image to ${2}" "${4}"
		MD5RES=$(verify_md5 "${IMGDIR}/${3}")
		if [ "${MD5RES}" == "1" ] || [ "${MD5RES}" == "2" ]; then
			write_image xz "${IMGDIR}/${3}" "${DESTDEV}${PL}${3}"
			check_result $?
		else
			ISERROR=1
			logd "Partition ${1} Restore Failed (Backup File MD5 Error)"
		fi
	elif [ "$IMGEXT" == "gz" ]; then
		logd "Restoring gz compressed raw image to ${2}"
		progress_dialog "Restoring data" "Restoring gz compressed raw image to ${2}" "${4}"
		MD5RES=$(verify_md5 "${IMGDIR}/${3}")
		if [ "${MD5RES}" == "1" ] || [ "${MD5RES}" == "2" ]; then
			write_image gz "${IMGDIR}/${3}" "${DESTDEV}${PL}${1}"
			check_result $?
		else
			ISERROR=1
			logd "Partition ${1} Restore Failed (Backup File MD5 Error)"
		fi
	elif [ "$IMGEXT" == "bz2" ]; then
		logd "Restoring bz2 compressed raw image to ${2}"
		progress_dialog "Restoring data" "Restoring bz2 compressed raw image to ${2}" "${4}"
		MD5RES=$(verify_md5 "${IMGDIR}/${3}")
		if [ "${MD5RES}" == "1" ] || [ "${MD5RES}" == "2" ]; then
			write_image bz2 "${IMGDIR}/${3}" "${DESTDEV}${PL}${1}"
			check_result $?
		else
			ISERROR=1
			logd "Partition ${1} Restore Failed (Backup File MD5 Error)"
		fi
	elif [ "$IMGEXT" == "raw" ] || [ "$IMGEXT" == "img" ]; then
		logd "Restoring raw image to ${2}"
		progress_dialog "Restoring data" "Restoring raw image to ${2}" "${4}"
		MD5RES=$(verify_md5 "${IMGDIR}/${3}")
		if [ "${MD5RES}" == "1" ] || [ "${MD5RES}" == "2" ]; then
			write_image raw "${IMGDIR}/${3}" "${DESTDEV}${PL}${1}"
		else
			ISERROR=1
			logd "Partition ${1} Restore Failed (Backup File MD5 Error)"
		fi
	else
		log ""
		log "Unsupported image: ${3}"
		log "Please read the README"
		ISERROR=1
	fi
}

logd "Process started at $(date)"

for f in $(cat /proc/cmdline); do
	if [ ! -z "$(echo "${f}" | /usr/bin/grep zefie)" ]; then
		ZTY=$(echo "${f}" | cut -d'.' -f2 | cut -d'=' -f1)
		ZPM=$(echo "${f}" | cut -d'.' -f2 | cut -d'=' -f2)
		if [ "$ZTY" == "usb" ]; then
			set_usb_dev "$ZPM"
		fi
		if [ "$ZTY" == "dest" ]; then
			set_dest_dev "$ZPM"
		fi
	fi
done;

if [ ! -b "$DESTDEV" ] || [ ! -b "$USBDEV" ]; then
	log "Could not read device data from kernel command line"
	NODEVS=1
fi

if [ -b "${USBDEV}" ]; then
	initial_scan_image_folder
fi

do_start_menu


logd "Searching for eMMC device at ${DESTDEV}..."
progress_dialog "Preparing devices" "Searching for eMMC device at ${DESTDEV}" 0
if [ ! -b "${DESTDEV}" ]; then
	log " Failed."
	exit 1;
fi

logd "Found eMMC device"

if [ "${DORESTORE}" == "1" ] || [ "${DOPARTITION}" == "1" ]; then
	progress_dialog "Preparing devices" "Mounting USB device ${USBDEV}${SPL}${USBPART}..." 25
	mount_usb "${USBDEV}${SPL}${USBPART}" "${USBMNT}"
fi

if [ "${DOPARTITION}" == "1" ] || [ "${DOWIPE}" == "1" ] ; then
	if [ "$ISEMMC" == "1" ]; then
		logd "Securely erasing all data on eMMC..."
		progress_dialog "Preparing devices" "Secure erasing eMMC..." 50
		DISKSIZE=$(fdisk --bytes -l "${DESTDEV}" | /usr/bin/grep Disk | /usr/bin/grep bytes | cut -d' ' -f5)
		re='^[0-9]+$'
		if ! [[ $DISKSIZE =~ $re ]] ; then
			ISERROR=1
			logd "Error getting size of ${DESTDEV} (got ${DISKSIZE}), expected size in bytes"
		else
			blkdiscard -o 0 -l "${DISKSIZE}" -s "${DESTDEV}" 2>>${LOGFILE} 1>>${LOGFILE}
			check_result $?
		fi
	else
		logd "Clearing partition table on disk..."
		progress_dialog "Preparing devices" "Clearing partition table on disk..." 50
		sgdisk --zap-all "${DESTDEV}" 2>>${LOGFILE} 1>>${LOGFILE}
		check_result $?
	fi
	logd "Refreshing partitions..."
	progress_dialog "Preparing devices" "Refreshing partititon table..." 75
	blockdev --flushbufs --rereadpt "${DESTDEV}" 2>>${LOGFILE} 1>>${LOGFILE}
fi

if [ "${DOPARTITION}" == "1" ]; then
	logd "Restoring partition table from ${SGDPART}"
	progress_dialog "Preparing devices" "Restoring partititon table with sgdisk binary table..." 85
	sgdisk -l "${SGDPART}" "${DESTDEV}" 2>>${LOGFILE} 1>>${LOGFILE}

	logd "Refreshing partitions..."
	progress_dialog "Preparing devices" "Refreshing partititon table..." 100
	partprobe "${DESTDEV}" 2>>${LOGFILE} 1>>${LOGFILE}
fi

if [ "${DORESTORE}" == "1" ]; then
	logd "Begin restore routine"
	NUMPARTS=$(wc -l < "${TXTPART}")
	CURPART=0
	progress_dialog "Restoring data" "Processing restore configuration ($TXTPART)..." 0
	for l in $(cat $TXTPART); do
		CURPART=$((CURPART + 1))
		PERCENT=$(($(awk "BEGIN { pc=100*${CURPART}/${NUMPARTS}; i=int(pc); print (pc-i<0.5)?i:i+1 }") - 1))
		PARTNUM=$(echo "${l}" | cut -d':' -f1 2>>${LOGFILE})
		PARTNAM=$(echo "${l}" | cut -d':' -f2 2>>${LOGFILE})
		PARTCMD=$(echo "${l}" | cut -d':' -f3 2>>${LOGFILE})
		PARTARG=$(echo "${l}" | cut -d':' -f4 2>>${LOGFILE})

		unset MD5RES;
		unset SKIPPART;
		unset WINFILESM;
		unset WINFILESU;
		unset WINFILES;
		unset RESTYPE;

		## Workaround for issue with partitions not appearing...
		if [ ! -b "${DESTDEV}${PL}${PARTNUM}" ]; then
			while [ ! -b "${DESTDEV}${PL}${PARTNUM}" ]; do
				blockdev --flushbufs --rereadpt "${DESTDEV}"
				sleep 1
			done;
		fi
		## End workaround

		if [ ! -z "${PARTCMD}" ]; then
			if [ "${PARTCMD}" == "format" ]; then
				if [ "${PARTARG}" == "ext2" ] || [ "${PARTARG}" == "ext3" ] || [ "${PARTARG}" == "ext4" ]; then
					logd "Formatting ${PARTNAM} as ${PARTARG}..."
					progress_dialog "Restoring data" "Formatting ${PARTNAM} as ${PARTARG}..." "${PERCENT}"
					format_disk "${PARTARG}" "${PARTNAM}" "${DESTDEV}${PL}${PARTNUM}"
					check_result $?
				fi
			fi
			if [ "${PARTCMD}" == "restore" ]; then
				restore_data "${PARTNUM}" "${PARTNAM}" "${PARTARG}" "${PERCENT}"

			fi
		fi
	done;
fi

umount_dev "${USBDEV}${SPL}${USBPART}"
logd "Process ended at $(date)"

do_end_menu $ISERROR

exit 0;
