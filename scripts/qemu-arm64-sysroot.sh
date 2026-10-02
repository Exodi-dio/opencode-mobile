#!/usr/bin/env bash
# qemu-arm64-sysroot.sh - build a runnable aarch64/Bionic sysroot for
# qemu-user from a public waydroid arm64 system image. CI-only (downloads
# ~1 GB). Produces <out>/sysroot with system/bin/linker64 and
# system/lib64/* from the real device libraries, so that
#   qemu-aarch64 -L <out>/sysroot <binary>
# can execute the linux-arm64-android opencode binary at link level.
#
# Usage: qemu-arm64-sysroot.sh <out-dir>
set -euo pipefail

out="${1:?usage: qemu-arm64-sysroot.sh <out>}"
mkdir -p "$out"
work="$out/work"
mkdir -p "$work"

meta=$(curl -sL --max-time 30 "https://ota.waydro.id/system/lineage/waydroid_arm64/VANILLA.json")
url=$(printf '%s' "$meta" | python3 -c "import json,sys; print(json.load(sys.stdin)['response'][0]['url'])")
sha=$(printf '%s' "$meta" | python3 -c "import json,sys; print(json.load(sys.stdin)['response'][0]['id'])")
size=$(printf '%s' "$meta" | python3 -c "import json,sys; print(json.load(sys.stdin)['response'][0]['size'])")
echo "waydroid arm64 system zip: $url ($size bytes, sha256 $sha)"

zip="$work/system-arm64.zip"
curl -fL --retry 3 -o "$zip" "$url"
python3 - "$zip" "$sha" <<'EOF'
import hashlib, sys
p, want = sys.argv[1], sys.argv[2]
h = hashlib.sha256()
with open(p, 'rb') as f:
    for b in iter(lambda: f.read(1 << 20), b''):
        h.update(b)
if h.hexdigest() != want:
    print(f"sha256 mismatch: got {h.hexdigest()}", file=sys.stderr)
    sys.exit(1)
print("sha256 ok")
EOF

unzip -q -o "$zip" -d "$work/zip"
img=$(find "$work/zip" -name 'system.img' | head -1)
[ -n "$img" ] || { echo "::error::no system.img in waydroid zip"; exit 1; }

# Waydroid images are normally raw ext4; convert android-sparse if needed.
raw="$work/system-raw.img"
cp "$img" "$raw"
magic=$(od -An -tx1 -N4 "$raw" | tr -d ' \n')
if [ "$magic" = "3aff26ed" ]; then
  echo "android sparse image; converting"
  command -v simg2img >/dev/null || sudo apt-get install -y android-sdk-ext4-utils
  simg2img "$raw" "$work/system-raw2.img" && mv "$work/system-raw2.img" "$raw"
fi
sudo mkdir -p /mnt/sysroot-img
if ! sudo mount -o loop,ro "$raw" /mnt/sysroot-img 2>/dev/null; then
  # The zip may carry a verity/erofs payload; carve with binwalk.
  command -v binwalk >/dev/null || sudo apt-get install -y binwalk
  sudo binwalk -Me "$raw" -C "$work/carve"
  ext=$(find "$work/carve" -name '*.img' | head -1)
  [ -n "$ext" ] || { echo "::error::cannot mount or carve system.img"; exit 1; }
  sudo mount -o loop,ro "$ext" /mnt/sysroot-img
fi
mp=/mnt/sysroot-img

echo "mounted at $mp"; ls "$mp" > /dev/null || true; ls "$mp" | head -20 || true

# Collect libs and linker into the sysroot. Android 12+ keeps linker64 and
# libc in com.android.runtime.apex; older images have them in system/bin64.
sysroot="$out/sysroot"
mkdir -p "$sysroot/system/bin" "$sysroot/system/lib64"
apices=$(find "$mp" -path '*com.android.runtime*.apex' 2>/dev/null)
echo "runtime apexes: $apices"
for ap in $apices; do
  sudo mkdir -p /mnt/runtime-apex
  if sudo mount -o loop,ro "$ap" /mnt/runtime-apex 2>/dev/null; then
    echo "apex mounted directly"
    sudo mkdir -p "$sysroot/apex/com.android.runtime"
    sudo cp -a /mnt/runtime-apex/. "$sysroot/apex/com.android.runtime/"
    sudo cp -a /mnt/runtime-apex/bin/. "$sysroot/system/bin/" || true
    sudo cp -a /mnt/runtime-apex/lib64/. "$sysroot/system/lib64/" || true
    sudo umount /mnt/runtime-apex
  else
    sudo apt-get install -y binwalk && sudo binwalk -Me "$ap" -C "$work/apex" || {
      echo "::error::cannot extract $ap (harness fault)"; exit 1; }
    rootdir=$(find "$work/apex" -maxdepth 4 -type d -name bin | head -1 | xargs -r dirname)
    if [ -n "$rootdir" ]; then
      sudo mkdir -p "$sysroot/apex/com.android.runtime"
      sudo cp -a "$rootdir/." "$sysroot/apex/com.android.runtime/"
      sudo cp -a "$rootdir/bin/." "$sysroot/system/bin/" || true
      sudo cp -a "$rootdir/lib64/." "$sysroot/system/lib64/" || true
    fi
    sudo umount /mnt/runtime-apex 2>/dev/null || true
    continue
  fi
done
# Fallbacks from the system tree itself (covers images with legacy layout).
for cand in $(find "$mp" \( -name linker64 -o -name 'libc.so' \) 2>/dev/null); do
  case "$cand" in
    *linker64) sudo cp -a "$cand" "$sysroot/system/bin/linker64" ;;
    *libc.so)  sudo cp -a "$(dirname "$cand")/." "$sysroot/system/lib64/" 2>/dev/null || true ;;
  esac
done
sudo chown -R "$(id -u):$(id -g)" "$sysroot" 2>/dev/null || true

test -x "$sysroot/system/bin/linker64" || { echo "::error::no linker64 found in system image"; exit 1; }
test -s "$sysroot/system/lib64/libc.so" || { echo "::error::no libc.so found in system image"; exit 1; }

sudo umount "$mp" 2>/dev/null || true
ls -la "$sysroot/system/bin" "$sysroot/system/lib64" | head -20
echo "sysroot ready at $sysroot"
