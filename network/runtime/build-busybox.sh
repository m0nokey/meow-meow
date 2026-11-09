#!/bin/sh
set -eux

git init aports
git -C aports remote add origin https://github.com/alpinelinux/aports.git
git -C aports sparse-checkout set main/busybox
git -C aports fetch --depth 1 --filter=blob:none origin "${APORTS_COMMIT}"
git -C aports checkout --detach FETCH_HEAD
test "$(git -C aports rev-parse HEAD)" = "${APORTS_COMMIT}"
cd aports/main/busybox
pkgver="$(sed -n 's/^pkgver=//p' APKBUILD)"
archive="busybox-${pkgver}.tar.bz2"
curl -fsS --retry 3 --retry-all-errors -o "${archive}" "https://busybox.net/downloads/${archive}"
awk -v archive="${archive}" '$2 == archive' APKBUILD | sha512sum -c -
tar -xf "${archive}"
for item in $(awk '/^sha512sums=/ { checksums = 1 } checksums && $2 ~ /[.]patch$/ { print $2 }' APKBUILD); do
    patch -d "busybox-${pkgver}" -p1 < "${item}"
done
cp busyboxconfig "busybox-${pkgver}/.config"
cd "busybox-${pkgver}"
python3 /build-config/minimize-busybox.py /build-config/busybox-applets.txt
make silentoldconfig
make -j2
install -D -m 0755 busybox /out/busybox
/out/busybox --list > /tmp/applets
grep -qx sh /tmp/applets
sort /tmp/applets > /tmp/actual-applets
sort /build-config/busybox-applets.txt > /tmp/expected-applets
diff -u /tmp/expected-applets /tmp/actual-applets
