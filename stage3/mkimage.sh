#!/usr/bin/env bash
# gentoo verified docker deployment
# (c) 2014 Daniel Golle
#
# requirements: wget, GnuPG, OpenSSL, docker.io ;)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DOCKER_NAMESPACE=${DOCKER_NAMESPACE:-aegypius}
PGPKEYSERVER=pgp.mit.edu
PGPPUBKEYFINGERPRINT=13EBBDBEDE7A12775DFDB1BABB572E0E2D182910

set -e

for checkme in docker wget gpg openssl; do
	req="$(which $checkme)"
	if [ ! "$req" ]; then
		echo "no $checkme" 1>&2
		exit 1
	fi
done

buildsdirurl() {
	local mirror="$1"
	local arch="$2"
	echo "${mirror}/releases/${arch}/autobuilds"
}

snapshotdirurl() {
	local mirror="$1"
	local arch="$2"
	local flavor="$3"
	local buildsdir="$( buildsdirurl "$mirror" "$arch" )"
	echo "$buildsdir/current-stage3-${arch}${flavor:+"-"}${flavor}"
}

getversion() {
	local mirror="$1"
	local arch="$2"
	local flavor="$3"
	local buildsdir="$( buildsdirurl "$mirror" "$arch" )"
	local url="${buildsdir}/latest-stage3-${arch}${flavor:+"-"}${flavor}.txt"
	wget -q -O/dev/stdout "$url" | grep -v "#" | sed 's/\/.*//'
}

getstage3() {
	local mirror="$1"
	local arch="$2"
	local snapshotver="$3"
	local target="$4"
	local flavor="$5"

	local snapshotdirurl="$( snapshotdirurl "$mirror" "$arch" "$flavor" )"
	local stage3name="stage3-${arch}${flavor:+"-"}${flavor}-${snapshotver}.tar.bz2"
	local digestfile="${target}/${stage3name}.DIGESTS.asc"

	# download DIGEST file
	wget -c -q -O"$digestfile" "${snapshotdirurl}/${stage3name}.DIGESTS.asc"
	if [ ! -e "$digestfile" ]; then
		echo "wget: can't download checksum file" 1>&2
		return
	fi

	# PGP signature check of checksum file
	# start with empty pgp homedir
	local pgpsession="$( mktemp --tmpdir -d mkimage-gentoo.pgp.XXXXXXXXXX )"
	if [ ! "$pgpsession" -o ! -d "$pgpsession" -o ! -w "$pgpsession" ]; then
		echo "gpg: can't create session" 1>&2
		rm "$digestfile"
		return
	fi
	# import Gentoo Linux Release Engineering (Automated Weekly Release Key)
	if ! gpg -q --homedir "$pgpsession" --keyserver $PGPKEYSERVER \
		--recv-keys $PGPPUBKEYFINGERPRINT; then
		echo "gpg: cannot import public key from keyserver" 1>&2
		rm "$digestfile"
		rm "$pgpsession"/* || true
		rmdir "$pgpsession"
		return
	fi
	# set owner-trust for this RSA public key
	if ! echo "$PGPPUBKEYFINGERPRINT:6:" |
		gpg -q --homedir "$pgpsession" --import-ownertrust; then
		echo "gpg: cannot set ownertrust for key" 1>&2
		rm "$digestfile"
		rm "$pgpsession"/*
		rmdir "$pgpsession"
		return
	fi
	# verify signature
	if ! gpg -q --homedir "$pgpsession" --verify "$digestfile"; then
		echo "gpg: signature verification of checksum file failed!" 1>&2
		rm "$digestfile"
		rm "$pgpsession"/*
		rmdir "$pgpsession"
		return
	fi
	rm "$pgpsession"/*
	rmdir "$pgpsession"

	# use only signed part of asc file
	local copy=0
	local skip=0
	local checkedfile="${target}/${stage3name}.DIGESTS.checked"
	cat "$digestfile" | while read line; do
		case "$line" in
			"-----BEGIN PGP SIGNED MESSAGE"*)
				copy=1
			;;
			"-----BEGIN PGP SIGNATURE"*)
				skip=1
			;;
		esac
		[ "$copy" = "1" -a "$skip" = "0" ] && echo "$line" >> "$checkedfile"
	done || true
	rm "$digestfile"

	# extracting SHA512 and WHIRLPOOL sums from signed part
	local sha512sum1=$( \
		grep -A 1 SHA512 "$checkedfile" | \
		grep -v "#" | grep -v "CONTENTS" | grep -v "\-\-" | sed 's/ .*//' \
	)
	local whirlpoolsum1=$( \
		grep -A 1 WHIRLPOOL "$checkedfile" | \
		grep -v "#" | grep -v "CONTENTS" | grep -v "\-\-" | sed 's/ .*//' \
	)
	rm "$checkedfile"

	if [ ! "$sha512sum1" -o ! "$whirlpoolsum1" -o \
	     ! "${#sha512sum1}" = "128" -o ! "${#whirlpoolsum1}" = "128" ]; then
		echo "error: cannot parse digest file" 1>&2
		return
	fi

	# alright, now download stage3 tarball
	echo "wget: downloading $stage3name" 1>&2
	wget -q -c -O"${target}/${stage3name}" "${snapshotdirurl}/${stage3name}"

	# verifying checksums
	echo "openssl: verifying digest" 1>&2
	local checksumsok=0
	local sha512sum2=$( \
		openssl dgst -r -sha512 "${target}/${stage3name}" | \
		sed 's/ .*//' \
	)
	if [ "$sha512sum1" = "$sha512sum2" ]; then
		echo "openssl: sha512 ok" 1>&2
		checksumsok=$(( $checksumsok + 1 ))
	fi

	local whirlpoolsum2=$( \
		openssl dgst -r -whirlpool "${target}/${stage3name}" | \
		sed 's/ .*//' \
	)
	if [ "$whirlpoolsum1" = "$whirlpoolsum2" ]; then
		echo "openssl: whirlpool ok" 1>&2
		checksumsok=$(( $checksumsok + 1 ))
	fi

	if [ "$checksumsok" != "2" ]; then
		echo "openssl: checksums failed!" 1>&2
		rm "${target}/${stage3name}"
		return
	fi

	echo "${stage3name}"
}

if echo $1 | grep -q "/"; then
	flavor=""
else
	flavor="$1"
	shift || true;
fi
mirror="${1:-"http://mirror.ovh.net/gentoo-distfiles"}"

# Docker is amd64 only
arch="amd64"

tag="gentoo${flavor:+"-"}${flavor}"

version=$( getversion "$mirror" "$arch" "$flavor" )
if [ ! "$version" ]; then
	echo "can't get latest build version of $tag" 1>&2
	exit 1;
fi

tag=$( echo $tag | sed "s/\+/-/" )
vertag="${tag}:${version}"

# check for existing docker image tagged with current build version
docker images $DOCKER_NAMESPACE/$tag | while read _repo extag _id _rest; do
	if [ "$extag" = "$version" ]; then
		echo "$DOCKER_NAMESPACE/$vertag exists, not rebuilding" 1>&2
		exit 1
	fi
done

target="$( mktemp --tmpdir -d mkimage-gentoo.target.XXXXXXXXXX )"
if [ ! -d "$target" ]; then
	echo "cannot mktemp -d" 1>&2
	exit 1;
fi

stage3=$( getstage3 "$mirror" "$arch" "$version" "$target" "$flavor" )
if [ ! "$stage3" -o ! -e "${target}/${stage3}" ]; then
	echo "no stage3" 1>&2
	rmdir "$target"
	exit 1;
fi

echo "importing ${stage3}" 1>&2
dockerimage=$( bzip2 -cd "${target}/${stage3}" | docker import - )

rm "${target}/${stage3}"
rmdir "$target"

docker tag "$dockerimage" $DOCKER_NAMESPACE/$vertag
docker tag "$dockerimage" $DOCKER_NAMESPACE/${tag}:latest

# docker push $DOCKER_NAMESPACE/$vertag
