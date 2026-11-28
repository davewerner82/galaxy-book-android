#!/usr/bin/env bash
set -euo pipefail
key=12345678123456781234567812345678
mkdir -p guest esp
truncate -s 12G sata.raw
sgdisk -n 1:2048:+128M -t 1:ef00 -n 2:0:0 -t 2:0700 sata.raw >/dev/null
loop=$(sudo losetup -Pf --show sata.raw)
sudo mkfs.vfat -F32 "${loop}p1" >/dev/null
sudo mount "${loop}p1" esp
sudo mkdir -p esp/EFI/BOOT
cat > boot.cfg <<'EOF'
serial --unit=0 --speed=115200
terminal_output serial
echo "GB_EFI_LOADER $cmdpath"
set root=hd0,gpt1
source /EFI/BOOT/grub.cfg
echo "GB_EFI_CONFIG_RETURNED"
reboot
EOF
grub-mkimage -O x86_64-efi -p /EFI/BOOT -c boot.cfg -o test-loader.efi part_gpt fat ntfs search search_fs_file serial terminal normal configfile linux boot reboot test echo
sudo cp test-loader.efi esp/EFI/BOOT/BOOTX64.EFI
sed -e 's/PARTNUM/2/g' -e "s/STAGEKEY/$key/g" -e 's/CONSOLEARGS/console=tty0 console=ttyS0/' package/windows/test-grub.cfg.in | sudo tee esp/EFI/BOOT/grub.cfg >/dev/null
grub-script-check esp/EFI/BOOT/grub.cfg
sudo umount esp
part="${loop}p2"
sudo mkntfs -Q -F -L WINTST "$part" >/dev/null
sudo mount -t ntfs3 "$part" guest
sudo mkdir guest/GalaxyBookTest
sudo cp stock/system.efs out/kernel out/initrd.img blank-data.img guest/GalaxyBookTest/
sudo mv guest/GalaxyBookTest/blank-data.img guest/GalaxyBookTest/data.img
echo "$key" | sudo tee guest/GalaxyBookTest/stage.key >/dev/null
sudo cp guest/GalaxyBookTest/stage.key "guest/GalaxyBookTest/id-$key"
sudo umount guest
sudo losetup -d "$loop"
accel=tcg
cpu=max
if [ -c /dev/kvm ]; then sudo chmod a+rw /dev/kvm; accel=kvm; cpu=host; fi
cp /usr/share/OVMF/OVMF_VARS_4M.fd vars.fd
qemu-system-x86_64 -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,unit=1,file=vars.fd -machine "q35,accel=$accel" -cpu "$cpu" -m 3072 -smp 2 \
  -nic none -display none -serial file:serial.log -monitor none -no-reboot \
  -drive file=sata.raw,if=ide,index=0,format=raw &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
for ((n=0;n<150;n++)); do
  if grep -q GB_ANDROID_INIT_HANDOFF serial.log; then break; fi
  if grep -Eq 'grub>|GB_EFI_CONFIG_RETURNED|Galaxy Book test stopped:' serial.log; then break; fi
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 2
done
tail -30 serial.log
grep -F 'GB_MODULES_READY 6.9.9-zenith' serial.log
grep -F GB_DIRECT_SYSTEM_READY serial.log
grep -F GB_ANDROID_INIT_HANDOFF serial.log
sleep 90
kill -0 "$pid"
if grep -Ei 'Kernel panic - not syncing|z_erofs_read_folio: read error|Buffer I/O error' serial.log; then exit 1; fi
kill "$pid" 2>/dev/null || true
wait "$pid" || true
trap - EXIT

