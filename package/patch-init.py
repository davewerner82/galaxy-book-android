"""Patch the pinned stock /init. Refuse an unexpected base layout."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
init = path.read_text()

def replace(old, new):
    global init
    if init.count(old) != 1:
        raise SystemExit(f"Expected exactly one stock init fragment: {old[:60]}")
    init = init.replace(old, new)

start = init.index("cd /\nwhile :; do\n\tfor device in ")
stop = init.index("\nif ! grep 'sse4_2'", start)
init = init[:start] + r'''cd /
fail_test()
{
    echo "Galaxy Book test stopped: $*" > /dev/console
    sync
    sleep 3
    reboot -f
    while :; do sleep 60; done
}
SRC=GalaxyBookTest
case "$GBROOT" in /dev/sda[1-9]|/dev/sda[1-9][0-9]) ;; *) fail_test "invalid SSD partition";; esac
case "$GBKEY" in ''|*[!0-9a-f]*) fail_test "invalid stage key";; esac
[ "${#GBKEY}" -eq 32 ] || fail_test "missing stage key"
for attempt in $(seq 1 30); do [ -b "$GBROOT" ] && break; sleep 1; done
device_path=$(readlink -f "/sys/class/block/${GBROOT##*/}")
case "$device_path" in */usb*|*/mmc*) fail_test "removable device";; */ata*/*) ;; *) fail_test "not the expected SATA disk";; esac
mount.ntfs-3g -o ro,norecover "$GBROOT" /mnt || fail_test "SSD unavailable"
[ "$(cat /mnt/$SRC/stage.key)" = "$GBKEY" ] || fail_test "stage identifier mismatch"
umount /mnt || fail_test "cannot release read-only check"
mount.ntfs-3g -o rw,norecover "$GBROOT" /mnt || fail_test "Windows volume is not clean and writable"
base=/mnt/$SRC
[ "$(cat "$base/stage.key")" = "$GBKEY" ] || fail_test "unexpected stage"
mkdir -p "$base/logs"
exec 2>>"$base/logs/initrd.log"
# Keep an open kernel-log reader across the Android init handoff. Bound disk use.
if [ -c /dev/kmsg ]; then
    (cat /dev/kmsg | head -c 2097152) > "$base/logs/kernel-through-android.txt" 2>/dev/null &
fi
mount -t erofs -o loop,ro "$base/system.efs" /sfs || fail_test "stock system container"
mount -o loop,ro /sfs/system.img /android || fail_test "stock Android system"
[ -s /android/system/lib/modules/modules.dep ] || fail_test "module index"
''' + init[stop:]
start = init.index("ln -s ../system/lib/firmware ../system/lib/modules /lib")
end = init.index("\nif [ -d system/apex/", start)
init = init[:start] + r'''ln -s ../system/lib/firmware /lib/firmware
release=$(uname -r)
mkdir -p "/lib/modules/$release" || fail_test "module search path"
mount -o bind /android/system/lib/modules "/lib/modules/$release" || fail_test "module search bind"
for driver in i2c_hid_acpi hid_multitouch wacom; do
    busybox modprobe "$driver" || fail_test "unable to load $driver"
    [ -d "/sys/module/$driver" ] || fail_test "$driver did not register"
done
echo "GB_MODULES_READY $release" | tee -a "$base/logs/initrd.log" /dev/console
''' + init[end:]
replace("load_modules\nmount_data\nmount_sdcard\nmount_grub", r'''load_modules
mount -t ext4 -o loop,noatime "$base/data.img" /android/data || fail_test "isolated test data"
{
    echo "Kernel: $(uname -r)"
    cat /proc/cmdline
    cat /proc/bus/input/devices
    for dev in /sys/bus/i2c/devices/*SYNP1234* /sys/bus/i2c/devices/*WCOM0027*; do
        [ -d "$dev" ] && ls -l "$dev/driver"
    done
    cat /proc/modules
} > "$base/logs/input-before-android.txt"
dmesg > "$base/logs/kernel-before-android.txt"
sync''')
replace('exec ${SWITCH:-switch_root} /android /init', '''echo "GB_ANDROID_INIT_HANDOFF" | tee -a "$base/logs/initrd.log" /dev/console
sync
exec ${SWITCH:-switch_root} /android /init''')
path.write_text(init)

