#!/usr/bin/env bash
# Runs pisagem.sh against a fake Proxmox: fresh install, update, and converting the hand-made ORS container.
# Run as root in a throwaway environment:  bash test/installer.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
mkdir -p "$W/net/vmbr0"; echo "MemAvailable: 16000000 kB" > "$W/meminfo"; export MEMINFO="$W/meminfo" NET_DIR="$W/net" PATH="$ROOT/test/fakepve:$PATH" BASE="$W/base" MAP_URL="file://$W/map.pbf" PISAGEM_SOURCE="file://$W/src.tgz"
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
reset() { rm -rf /etc/pve/lxc /opt/ors "$BASE" /tmp/fake*.log; mkdir -p /etc/pve/lxc; }

# the repository as GitHub would serve it (a top folder inside the tarball)
mkdir -p "$W/repo/Pisagem-main" && cp -r "$ROOT/web" "$ROOT/server" "$ROOT/pisagem.sh" "$W/repo/Pisagem-main/"
tar czf "$W/src.tgz" -C "$W/repo" Pisagem-main
echo "fake map" > "$W/map.pbf"

echo "== fresh install"; reset
bash "$ROOT/pisagem.sh" </dev/null > "$W/out1.txt" 2>&1; rc=$?
check "installer finished" "[[ $rc == 0 ]]"
check "container created with the pisagem tag" "grep -q '^tags: pisagem' /etc/pve/lxc/125.conf"
check "Docker features on (nesting, keyctl)" "grep -q 'nesting=1,keyctl=1' /etc/pve/lxc/125.conf"
check "8 GB memory" "grep -q '^memory: 8192' /etc/pve/lxc/125.conf"
check "newest Debian 12 template chosen" "grep -q 'debian-12-standard_12.12-1' /tmp/fakepct.log"
check "page in place" "[[ -f $BASE/web/pisagem.html ]]"
check "compose, nginx, routing config in place" "[[ -f $BASE/docker-compose.yml && -f $BASE/nginx.conf && -f $BASE/ors/config/ors-config.yml ]]"
check "Portugal map downloaded" "[[ -s $BASE/ors/files/portugal-latest.osm.pbf ]]"
check "services started" "grep -q 'compose up -d' /tmp/fakedocker.log"
check "update and pisagem commands" "[[ -x /usr/local/bin/update && -x /usr/local/bin/pisagem ]]"
check "console logs in automatically" "grep -q autologin /etc/systemd/system/container-getty@1.service.d/override.conf"
check "token file private" "[[ \$(stat -c %a /etc/pisagem/pisagem.env) == 600 ]]"
check "prints the address" "grep -q 'Open in a browser' $W/out1.txt"

echo "== run again: updates in place"
echo "  bikes: yes" >> "$BASE/ors/config/ors-config.yml"
rm -f /tmp/fakepct.log
bash "$ROOT/pisagem.sh" </dev/null > "$W/out2.txt" 2>&1; rc=$?
check "update finished" "[[ $rc == 0 ]]"
check "no second container" "! grep -q '^pct create' /tmp/fakepct.log"
check "says it's updating" "grep -q 'Updating Pisagem in container 125' $W/out2.txt"
check "your routing config is kept" "grep -q 'bikes: yes' $BASE/ors/config/ors-config.yml"

echo "== the hand-made container from before (126, /opt/ors)"; reset
printf 'hostname: ors\nmemory: 6144\n' > /etc/pve/lxc/126.conf
mkdir -p /opt/ors/graphs /opt/ors/config /opt/ors/files && echo built > /opt/ors/graphs/marker && echo old > /opt/ors/docker-compose.yml
bash "$ROOT/pisagem.sh" </dev/null > "$W/out3.txt" 2>&1; rc=$?
check "conversion finished" "[[ $rc == 0 ]]"
check "no new container" "! grep -q '^pct create' /tmp/fakepct.log"
check "126 now tagged pisagem" "grep -q '^tags: pisagem' /etc/pve/lxc/126.conf"
check "126 memory raised to 8192" "grep -q '^memory: 8192' /etc/pve/lxc/126.conf"
check "built route network kept" "[[ -f $BASE/ors/graphs/marker && ! -d /opt/ors ]]"
check "old compose file replaced" "[[ ! -f $BASE/ors/docker-compose.yml ]] && grep -q nginx $BASE/docker-compose.yml"

echo "== stops cleanly on a bad download"; reset
printf 'hostname: p\nmemory: 8192\ntags: pisagem\n' > /etc/pve/lxc/125.conf
PISAGEM_SOURCE="file://$W/missing.tgz" bash "$ROOT/pisagem.sh" </dev/null > "$W/out4.txt" 2>&1; rc=$?
check "fails" "[[ $rc != 0 ]]"
check "says nothing was changed" "grep -q 'nothing was changed' $W/out4.txt"

echo; echo "$pass passed, $fail failed"; [[ $fail == 0 ]]
