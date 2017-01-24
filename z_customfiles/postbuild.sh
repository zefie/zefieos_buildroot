#!/bin/bash
BRDIR="$(realpath $(dirname "$(dirname "$(readlink "$0")")"))"
ZROOT="${BRDIR}/z_customfiles"
CWD="$(pwd)"

# Read build config file
eval "$(cat "${BRDIR}/.config" | sed -e 's/(/{/g' | sed -e 's/)/}/g')"

if [ "${BR2_TARGET_ROOTFS_CPIO}" == "y" ]; then
	if [ "${BR2_TARGET_ROOTFS_CPIO_GZIP}" == "y" ]; then
		COMP="gzip -9"
		COMPEXT="gz"
	fi

	if [ "${BR2_TARGET_ROOTFS_CPIO_XZ}" == "y" ]; then
		COMP="xz -9"
		COMPEXT="xz"
	fi

	if [ "${BR2_TARGET_ROOTFS_CPIO_BZIP2}" == "y" ]; then
		COMP="bzip2 -9"
		COMPEXT="bz2"
	fi

	# Build custom initrds

	for l in $(ls -1 "${ZROOT}/"); do
		if [ -f "${ZROOT}/${l}/config.txt" ]; then
			FAILED=0
			if [ ! -z "${COMP}" ]; then
				echo -n "* Generate ${l}.cpio.${COMPEXT}:"
			else
				echo -n "* Generate ${l}.cpio:"
			fi
			if [ "$l" == "qemu" ]; then
				KERND="$(uname -r)"
			fi
			TMPDIR="$(mktemp -d)"
			for f in $(cat "${BRDIR}/z_customfiles/${l}/config.txt"); do
				if [ $(echo "${f}" | grep ':' -c) -gt 0 ]; then
					SRCFILE="$(eval echo ${f} | cut -d':' -f1)"
					if [ "${SRCFILE:0:1}" != "/" ]; then
						# If it has a starting / we want something from an absolute path
						# Otherwise we want it from the local directory
						SRCFILE="${BRDIR}/z_customfiles/${l}/${SRCFILE}"
					fi
					OUTFILENAM="$(eval echo "${f}" | cut -d':' -f2)"
					OUTFILE="${TMPDIR}${OUTFILENAM}" # no / in between
					FILEMOD="$(echo "${f}" | cut -d':' -f3)"
					mkdir -p "${TMPDIR}$(echo "${OUTFILENAM}" | cut -d':' -f2 | rev | cut -d'/' -f2- | rev)"
					cp "${SRCFILE}" "${OUTFILE}"
					chmod "${FILEMOD}" "${OUTFILE}"
				fi
			done;
			cd "${TMPDIR}"
			find . | cpio --create --format='newc' -R "root:root" 2>/dev/null > "${BRDIR}/output/images/${l}.cpio"
			if [ ! -z "${COMP}" ]; then
				${COMP} -c "${BRDIR}/output/images/${l}.cpio" > "${BRDIR}/output/images/${l}.cpio.${COMPEXT}"
			fi
			cd "${CWD}"
			rm -rf "${TMPDIR}"
			if [ ! -f "${BRDIR}/output/images/${l}.cpio" ]; then
				FAILED=1
			else
				if [ ! -z "${COMP}" ]; then
					if [ ! -f "${BRDIR}/output/images/${l}.cpio.${COMPEXT}" ]; then
						FAILED=1
					fi
				fi
			fi

			if [ ${FAILED} -ne 0 ]; then
				echo " Failed.";
				exit 1;
			else
				echo " Success.";
			fi
		fi
	done;
	exit 0;
else
	# This script requires cpio support enabled.
	# If it isn't there is point in including this script to run
	# So tell the user and fail
	echo "*** BR2_TARGET_ROOTFS_CPIO not enabled in build config! Enable it or remove this script from post build."
	exit 1;
fi

