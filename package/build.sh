#!/usr/bin/env bash
set -euo pipefail
trap 'echo "::error::Packaging failed at line $LINENO: $BASH_COMMAND"' ERR
root=$PWD
out=$root/out
mkdir -p "$out" stock ramfs outer android
release=6.9.9-zenith
echo "b1c513a53fbf2586a6506bbf941076f4a2369bbc27071339a5cb482869a3bed8  base.iso" | sha256sum -c -
7z e -y base.iso -ostock kernel initrd.img system.efs >/dev/null
(cd stock && sha256sum -c ../package/stock.sha256)
rm base.iso
sudo mount -t erofs -o ro,loop stock/system.efs outer
sudo mount -t ext4 -o ro,noload,loop outer/system.img android
stock_modules="android/system/lib/modules/$release"
test -s "$stock_modules/modules.dep"
for driver in i2c-hid-acpi i2c-hid hid-multitouch wacom; do
  module=$(find "$stock_modules" -name "$driver.ko" -print -quit)
  test -n "$module"
  magic=$(modinfo -F vermagic "$module")
  test "${magic%% *}" = "$release"
  echo "$driver: $magic" >> "$out/stock-driver-versions.txt"
done
sha256sum outer/system.img | awk '{print $1 "  system.img"}' > "$out/system-image.sha256"
sudo umount android outer
# Preserve the stock archive's entries and permissions, including its BusyBox.
(cd ramfs && gzip -dc ../stock/initrd.img | sudo cpio -idu --quiet)
sudo python3 package/patch-init.py ramfs/init
sudo cp "$out/system-image.sha256" ramfs/system-image.sha256
sudo sh -n ramfs/init
(cd ramfs && sudo find . -print0 | sudo cpio --null -o -H newc --quiet | gzip -2) > "$out/initrd.img"
cp stock/kernel "$out/kernel"
truncate -s 2G blank-data.img
mkfs.ext4 -q -F -m 0 -L GalaxyBookTest -O ^orphan_file,^metadata_csum_seed blank-data.img
gzip -1c blank-data.img > "$out/data.img.gz"
cp package/windows/* package/stock.sha256 "$out/"
cp package/candidate-module-gap.txt "$out/"
{
  echo "Hardware: Samsung Galaxy Book 12 LTE SM-W727"
  echo "Reference: Bliss-Zenith-v16.9.6-x86_64-OFFICIAL-gapps-20240715"
  echo "Boot kernel and modules: matching original July release; touchscreen preload in initrd"
  echo "Separate experimental kernel build: https://github.com/davewerner82/galaxy-book-android/actions/runs/46002582645"
  echo "Integration commit: $GITHUB_SHA"
  echo "Integration run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
} > "$out/build-manifest.txt"
(cd "$out" && sha256sum kernel initrd.img data.img.gz test-grub.cfg.in > payload.sha256)

