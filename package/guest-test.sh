#!/usr/bin/env bash
set -euo pipefail
key=12345678123456781234567812345678
mkdir -p guest
truncate -s 7G sata.raw
sgdisk -n 1:2048:0 -t 1:0700 sata.raw >/dev/null
loop=$(sudo losetup -Pf --show sata.raw)
part="${loop}p1"
sudo mkntfs -Q -F -L WINTST "$part" >/dev/null
sudo mount -t ntfs3 "$part" guest
sudo mkdir guest/GalaxyBookTest
sudo cp stock/system.efs out/modules.sfs blank-data.img guest/GalaxyBookTest/
sudo mv guest/GalaxyBookTest/blank-data.img guest/GalaxyBookTest/data.img
echo "$key" | sudo tee guest/GalaxyBookTest/stage.key >/dev/null
sudo umount guest
sudo losetup -d "$loop"
accel=tcg
cpu=max
if [ -c /dev/kvm ]; then sudo chmod a+rw /dev/kvm; accel=kvm; cpu=host; fi
qemu-system-x86_64 -machine "q35,accel=$accel" -cpu "$cpu" -m 3072 -smp 2 \
  -nic none -display none -serial file:serial.log -monitor none -no-reboot \
  -drive file=sata.raw,if=ide,index=0,format=raw -kernel out/kernel -initrd out/initrd.img \
  -append "console=tty0 console=ttyS0 root=/dev/ram0 GBROOT=/dev/sda1 GBKEY=$key SRC=GalaxyBookTest panic=5" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
for ((n=0;n<150;n++)); do
  if grep -q GB_ANDROID_INIT_HANDOFF serial.log; then break; fi
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 2
done
grep -F 'GB_MODULES_READY 6.9.9-zenith' serial.log
grep -F GB_ANDROID_INIT_HANDOFF serial.log
sleep 15
if grep -q 'Kernel panic - not syncing' serial.log; then exit 1; fi
kill "$pid" 2>/dev/null || true
wait "$pid" || true
trap - EXIT

