#!/usr/bin/env bash
set -euo pipefail
root=$PWD
out=$root/out
mkdir -p "$out" stock ramfs outer android
release=$(cat candidate/candidate-version.txt)
[[ "$release" == 6.9.9-zenith ]]
sha256sum -c candidate/candidate-sha256.txt
echo "b1c513a53fbf2586a6506bbf941076f4a2369bbc27071339a5cb482869a3bed8  base.iso" | sha256sum -c -
7z e -y base.iso -ostock kernel initrd.img system.efs >/dev/null
(cd stock && sha256sum -c ../package/stock.sha256)
sudo mount -t erofs -o ro,loop stock/system.efs outer
sudo mount -t ext4 -o ro,noload,loop outer/system.img android
stock_modules=android/system/lib/modules
mods="candidate/lib/modules/$release"
test -d "$mods/kernel"
test -d "$stock_modules/kernel"
test -z "$(find "$mods" -type l -print -quit)"
depmod -b "$root/candidate" "$release"
python3 - "$mods" "$stock_modules" <<'PY'
from pathlib import Path
import subprocess, sys
mods, stock = map(Path, sys.argv[1:])
def name(p):
    return p.name.split(".ko", 1)[0].replace("-", "_")
candidate = {name(p) for p in mods.rglob("*.ko*")}
builtins = {name(Path(p)) for p in (mods/"modules.builtin").read_text().splitlines()}
stock_files = list(stock.rglob("*.ko*"))
missing = {name(p) for p in stock_files} - candidate - builtins
print("Stock modules:",len(stock_files),"candidate loadable:",len(candidate),"built-in:",len(builtins),flush=True)
if missing:
    raise SystemExit("Missing stock modules: "+", ".join(sorted(missing)))
for required in ["hid_multitouch","wacom","i2c_hid_acpi","i2c_hid","drm"]:
    assert required in builtins, required
PY
# Preserve release-specific Android module lists and SELinux labels.
for f in "$stock_modules"/modules.load* "$stock_modules"/modules.blocklist* "$stock_modules"/modules.options*; do
  [ ! -f "$f" ] || cp "$f" "$mods/"
done
sudo python3 - "$stock_modules" "$mods" <<'PY'
import os, sys
from pathlib import Path
src, dst = map(Path,sys.argv[1:])
for target in [dst, *dst.rglob("*")]:
    ref=src/target.relative_to(dst)
    if not ref.exists():
        ref=src if target.is_dir() else next(src.rglob("*.ko"))
    if "security.selinux" in os.listxattr(ref):
        os.setxattr(target,"security.selinux",os.getxattr(ref,"security.selinux"))
PY
ln -s . "$mods/$release"
sudo mksquashfs "$mods" "$out/modules.sfs" -noappend -comp gzip -all-root -quiet
sudo umount android outer
# Preserve the stock archive's entries and permissions, including its BusyBox.
(cd ramfs && gzip -dc ../stock/initrd.img | sudo cpio -idu --quiet)
sudo python3 package/patch-init.py ramfs/init
sudo sh -n ramfs/init
(cd ramfs && sudo find . -print0 | sudo cpio --null -o -H newc --quiet | gzip -2) > "$out/initrd.img"
cp candidate/kernel "$out/kernel"
truncate -s 2G blank-data.img
mkfs.ext4 -q -F -m 0 -L GalaxyBookTest -O ^orphan_file,^metadata_csum_seed blank-data.img
gzip -1c blank-data.img > "$out/data.img.gz"
cp package/windows/* package/stock.sha256 "$out/"
cp candidate/{candidate-version.txt,source-commit.txt,source-provenance.txt} "$out/"
(cd "$out" && sha256sum kernel initrd.img modules.sfs data.img.gz > payload.sha256)

