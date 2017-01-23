#!/bin/bash
OUTDIR="${1}"
BRDIR=$(dirname "${0}")

rm -rf "${OUTDIR}/etc/zefie"

for l in $(cat "${BRDIR}/z_customfiles/config.txt"); do
	if [ $(echo "${l}" | grep ':' -c) -gt 0 ]; then
		SRCFILE="${BRDIR}/z_customfiles/$(echo "${l}" | cut -d':' -f1)"
		OUTFILE="${OUTDIR}$(echo "${l}" | cut -d':' -f2)"
		FILEMOD="$(echo "${l}" | cut -d':' -f3)"
		mkdir -p "${OUTDIR}$(echo "${l}" | cut -d':' -f2 | rev | cut -d'/' -f2- | rev)"
		cp -v "${SRCFILE}" "${OUTFILE}"
		chmod "${FILEMOD}" "${OUTFILE}"
	fi
done;

## FOR TESTING IN QEMU ##
rm -rf "${OUTDIR}/lib/modules/*"

KERND="$(uname -r)"

mkdir -p "${OUTDIR}/lib/modules/${KERND}/kernel/fs/fat"
cp -v "/lib/modules/${KERND}/kernel/fs/fat/msdos.ko" "${OUTDIR}/lib/modules/${KERND}/kernel/fs/fat/msdos.ko"
mkdir -p "${OUTDIR}/lib/modules/${KERND}/kernel/fs/nls"
cp -v "/lib/modules/${KERND}/kernel/fs/nls/nls_iso8859-1.ko" "${OUTDIR}/lib/modules/${KERND}/kernel/fs/nls/nls_iso8859-1.ko"

cp -v "/lib/modules/${KERND}/modules.dep" "${OUTDIR}/lib/modules/${KERND}/modules.dep"


exit 0;


