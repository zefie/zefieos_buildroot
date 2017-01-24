#!/bin/bash
BRDIR="$(realpath $(dirname "$(dirname "$(readlink "$0")")"))"
ZROOT="${BRDIR}/z_customfiles"
CWD="$(pwd)"
COMP="gzip -9"
COMPEXT="gz"

# Build custom initrds

for l in $(ls -1 "${ZROOT}/"); do
	if [ -f "${ZROOT}/${l}/config.txt" ]; then
		echo "* Generating ${l}.cpio.${COMPEXT}"
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
				cp -v "${SRCFILE}" "${OUTFILE}"
				chmod "${FILEMOD}" "${OUTFILE}"
			fi
		done;
		cd "${TMPDIR}"
		find . | cpio --create --format='newc' -R "root:root" > "${BRDIR}/output/images/${l}.cpio"
		${COMP} -c "${BRDIR}/output/images/${l}.cpio" > "${BRDIR}/output/images/${l}.cpio.${COMPEXT}"
		cd "${CWD}"
		rm -rf "${TMPDIR}"
	fi
done;
exit 0;


