#!/usr/bin/env bash
# ============================================================================
#  Pisagem: random loop routes for Portugal. All-in-one installer for Proxmox VE.
#
#  Run on the Proxmox host shell, as root:
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsacosta4/pisagem/main/pisagem.sh)"
#  or, with the file copied over:   bash pisagem.sh
#
#  First run : creates a Debian 12 LXC (tag "pisagem") with Docker, and inside it
#              OpenRouteService (routes), Overpass (map data), Photon (search) and
#              nginx serving the Pisagem page, all on one address.
#  Next runs : finds the Pisagem container and updates it in place. The route
#              network, map data and search index are kept.
#  Old setup : a container that already runs OpenRouteService in /opt/ors (the
#              hand-made one) is converted, keeping its built route network.
#
#  Any value can be preset, e.g.  CTID=130 MEMORY=10240 bash pisagem.sh
#  GITHUB_TOKEN is optional (only needed if the repository is made private again).
# ============================================================================
set -Eeuo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8
unset LANGUAGE

PISAGEM_VERSION="0.1.0"
TAG="pisagem"
REPO="${REPO:-danielsacosta4/pisagem}"
REF="${REF:-main}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
# Where the code comes from (a tarball of the repository); overridable for tests.
PISAGEM_SOURCE="${PISAGEM_SOURCE:-https://api.github.com/repos/$REPO/tarball/$REF}"
MAP_URL="${MAP_URL:-https://download.geofabrik.de/europe/portugal-latest.osm.pbf}"
BASE="${BASE:-/opt/pisagem}"

CTID="${CTID:-}"
HOSTNAME_CT="${HOSTNAME_CT:-pisagem}"
CORES="${CORES:-4}"
MEMORY="${MEMORY:-8192}"      # MB. Routes ~5 GB, map data ~1.5 GB, search ~1 GB
SWAP="${SWAP:-4096}"
DISK_GB="${DISK_GB:-60}"
STORAGE="${STORAGE:-}"
TEMPLATE_STORE="${TEMPLATE_STORE:-}"
BRIDGE="${BRIDGE:-}"

# ---------- look ----------
B=$'\e[1m'; D=$'\e[2m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'
step() { printf '\n%s\n' "${B}${C}==>${N} ${B}$*${N}"; }
ok()   { printf '  %s %s\n' "${G}✓${N}" "$*"; }
warn() { printf '  %s %s\n' "${Y}!${N}" "$*"; }
die()  { printf '\n  %s %s\n\n' "${R}✗${N}" "${B}$*${N}" >&2; exit 1; }
trap 'die "Something failed on line $LINENO. Copy the output above and send it over."' ERR

yesno() { # yesno "Question" Y|N   (no terminal: the default)
  local a=""
  if { true </dev/tty; } 2>/dev/null; then read -r -p "  $1 ${D}[$( [[ $2 == Y ]] && echo Y/n || echo y/N )]${N}: " a </dev/tty || true; fi
  a=${a:-$2}; [[ $a =~ ^[Yy] ]]
}
is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

banner() {
  printf '%s\n' "${B}"
  printf '         _\n'
  printf '   ___  (_) ___ ___ ___ ____ ___ __ _\n'
  printf '  / _ \\/ /(_-</ _ `/ _ `/ -_)  '"'"'  \\\n'
  printf ' / .__/_//___/\\_,_/\\_, /\\__/_/_/_/ %s\n' "${N}${D}v${PISAGEM_VERSION} · routes for Portugal${N}"
  printf '/_/               /___/\n\n'
}

fetch() { # fetch URL OUT  (sends GITHUB_TOKEN to GitHub if one is set)
  local auth=()
  if [[ -n "$GITHUB_TOKEN" && "$1" =~ ^https://(api\.github\.com|raw\.githubusercontent\.com)/ ]]; then
    auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  curl -fsSL -m 600 --retry 3 "${auth[@]}" "$1" -o "$2"
}

# ============================================================================
#  Inside the container
# ============================================================================
in_container() { # in_container install|update
  local mode=$1
  step "Pisagem $PISAGEM_VERSION inside the container"

  # --- Docker ---
  if ! command -v docker >/dev/null 2>&1; then
    step "Installing Docker"
    apt-get update -qq >/dev/null
    apt-get install -y -qq curl ca-certificates >/dev/null
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1 || die "Docker didn't install. Check the container's internet access."
  fi
  docker compose version >/dev/null 2>&1 || die "Docker Compose is missing. Run: apt-get install -y docker-compose-plugin"
  ok "Docker is ready"

  # --- the code ---
  step "Getting Pisagem ($REF)"
  local tmp; tmp=$(mktemp -d)
  fetch "$PISAGEM_SOURCE" "$tmp/src.tgz" || die "Couldn't download Pisagem from GitHub. Check the internet access; nothing was changed."
  tar xzf "$tmp/src.tgz" -C "$tmp" --strip-components=1 || die "The download from GitHub was damaged. Try again; nothing was changed."
  [[ -f $tmp/web/pisagem.html && -f $tmp/server/docker-compose.yml ]] || die "The download is missing files. Nothing was changed."
  ok "Downloaded"

  # --- the old hand-made setup (/opt/ors) moves in, with its built route network ---
  if [[ -d /opt/ors && ! -d $BASE/ors ]]; then
    step "Moving your existing OpenRouteService into $BASE"
    (cd /opt/ors && docker compose down >/dev/null 2>&1) || true
    mkdir -p "$BASE"
    mv /opt/ors "$BASE/ors"
    rm -f "$BASE/ors/docker-compose.yml"
    ok "Kept the route network you already built"
  fi

  # --- files ---
  mkdir -p "$BASE"/{web,overpass,photon,ors/config,ors/files} /etc/pisagem
  cp -r "$tmp"/web/. "$BASE/web/"
  cp "$tmp/server/docker-compose.yml" "$tmp/server/nginx.conf" "$BASE/"
  # the routing config is yours once it exists (profiles you added, e.g. bikes, are kept)
  [[ -f $BASE/ors/config/ors-config.yml ]] || cp "$tmp/server/ors-config.yml" "$BASE/ors/config/ors-config.yml"
  umask 077
  printf 'REPO=%q\nREF=%q\nGITHUB_TOKEN=%q\nBASE=%q\n' "$REPO" "$REF" "$GITHUB_TOKEN" "$BASE" > /etc/pisagem/pisagem.env
  umask 022
  ok "Files in $BASE"

  # --- the Portugal map (routes use it; Overpass downloads its own copy) ---
  if [[ ! -s $BASE/ors/files/portugal-latest.osm.pbf ]]; then
    step "Downloading the Portugal map (about 400 MB)"
    fetch "$MAP_URL" "$BASE/ors/files/portugal-latest.osm.pbf.part" || die "Couldn't download the Portugal map from Geofabrik. Run the installer again in a while."
    mv "$BASE/ors/files/portugal-latest.osm.pbf.part" "$BASE/ors/files/portugal-latest.osm.pbf"
    ok "Map downloaded"
  fi

  # --- commands: update, pisagem ---
  install -m 755 "$0" /usr/local/lib/pisagem.sh 2>/dev/null || cp "$0" /usr/local/lib/pisagem.sh
  cat > /usr/local/bin/update <<'EOF'
#!/usr/bin/env bash
# Update Pisagem to the latest version. Route network, map data and search index are kept.
set -Eeuo pipefail
set -a; . /etc/pisagem/pisagem.env; set +a
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
AUTH=(); [[ -n "${GITHUB_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
curl -fsSL "${AUTH[@]}" "${PISAGEM_SOURCE:-https://api.github.com/repos/$REPO/tarball/$REF}" -o "$TMP/src.tgz"
tar xzf "$TMP/src.tgz" -C "$TMP" --strip-components=1
bash "$TMP/pisagem.sh" --in-container update
EOF
  chmod 755 /usr/local/bin/update
  cat > /usr/local/bin/pisagem <<'EOF'
#!/usr/bin/env bash
# pisagem status | logs SERVICE | restart
set -a; . /etc/pisagem/pisagem.env; set +a
cd "$BASE"
case "${1:-status}" in
  status)
    check() { if curl -fsS -m 5 -o /dev/null "$2"; then printf '  \e[32m✓\e[0m %-16s ready\n' "$1"; else printf '  \e[33m…\e[0m %-16s starting or importing (see: pisagem logs %s)\n' "$1" "$3"; fi; }
    check "Page"   "http://127.0.0.1/" web
    check "Routes" "http://127.0.0.1/ors/v2/health" ors
    curl -fsS -m 5 http://127.0.0.1/ors/v2/health 2>/dev/null | grep -q '"ready"' || printf '    routes not ready yet: the first build takes 20–60 minutes\n'
    check "Map data" "http://127.0.0.1/overpass/status" overpass
    check "Search" "http://127.0.0.1/photon/api/?q=Porto&limit=1" photon ;;
  logs)    docker logs --tail 40 -f "${2:-ors}" ;;
  restart) docker compose restart ;;
  *) echo "pisagem status | logs ors|overpass|photon|web | restart" ;;
esac
EOF
  chmod 755 /usr/local/bin/pisagem

  # --- console: log in automatically, show the address ---
  mkdir -p /etc/systemd/system/container-getty@1.service.d /etc/systemd/system/console-getty.service.d
  printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%%I 115200,38400,9600 $TERM\n' \
    > /etc/systemd/system/container-getty@1.service.d/override.conf
  printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear --keep-baud console 115200,38400,9600 $TERM\n' \
    > /etc/systemd/system/console-getty.service.d/override.conf
  cat > /etc/profile.d/pisagem.sh <<'EOF'
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
printf '\n  Pisagem is running.\n  Open in a browser:  http://%s\n  Check services:     pisagem status\n  Update Pisagem:     update\n\n' "${IP:-<container-ip>}"
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true

  # --- start ---
  step "Starting the services"
  (cd "$BASE" && docker compose pull -q && docker compose up -d --remove-orphans) || die "Docker couldn't start the services. See: cd $BASE && docker compose logs"
  ok "Started"
  rm -rf "$tmp"

  step "Pisagem is $( [[ $mode == update ]] && echo updated || echo installed )"
  echo "  The first start builds everything from the Portugal map:"
  echo "    routes 20–60 min · map data 30–90 min · search 10–30 min"
  echo "  Until then the page uses the public services. Check with:  pisagem status"
}

# ============================================================================
#  On the Proxmox host
# ============================================================================
pick_storage() { # first active storage of a content type, preferring a name
  local list
  list="$(pvesm status -content "$1" | awk 'NR>1 && $3=="active" {print $1}')"
  if grep -qx "$2" <<<"$list"; then echo "$2"; else head -n 1 <<<"$list"; fi
}
pick_bridge() {
  local list; list="$(ls "${NET_DIR:-/sys/class/net}" 2>/dev/null | grep '^vmbr' || true)"
  if grep -qx vmbr0 <<<"$list"; then echo vmbr0; else head -n 1 <<<"$list"; fi
}
find_tagged() { # the container tagged pisagem, if any
  local f
  for f in /etc/pve/lxc/*.conf; do
    [[ -f $f ]] && grep -q "^tags:.*\b$TAG\b" "$f" && { basename "$f" .conf; return; }
  done
  true
}
find_handmade() { # a container with OpenRouteService in /opt/ors
  local f id
  for f in /etc/pve/lxc/*.conf; do
    [[ -f $f ]] || continue
    id=$(basename "$f" .conf)
    pct status "$id" 2>/dev/null | grep -q running || continue
    pct exec "$id" -- test -d /opt/ors 2>/dev/null && { echo "$id"; return; }
  done
  true
}
run_inside() { # run_inside ID MODE
  local id=$1 script
  script=$(mktemp)
  cp "$0" "$script" 2>/dev/null || fetch "https://raw.githubusercontent.com/$REPO/$REF/pisagem.sh" "$script"
  pct push "$id" "$script" /root/pisagem.sh
  rm -f "$script"
  pct exec "$id" -- env REPO="$REPO" REF="$REF" GITHUB_TOKEN="$GITHUB_TOKEN" PISAGEM_SOURCE="$PISAGEM_SOURCE" MAP_URL="$MAP_URL" BASE="$BASE" \
    bash /root/pisagem.sh --in-container "$2"
}
show_address() {
  local id=$1 ip=""
  for _ in $(seq 1 60); do
    ip="$(pct exec "$id" -- hostname -I 2>/dev/null | awk '{print $1}' || true)"
    [[ -n "$ip" ]] && break; sleep 2
  done
  printf '\n  %s\n' "${B}Open in a browser:  http://${ip:-<container-ip>}${N}"
  echo "  Console:            pct enter $id   (logs in automatically)"
  echo "  Services:           pct exec $id -- pisagem status"
  echo "  Update:             pct exec $id -- update   (or run this installer again)"
  echo "  Data:               $BASE inside the container; include it in Proxmox backups"
  echo
}

on_host() {
  banner
  [[ $EUID -eq 0 ]] || die "Run as root on the Proxmox host."
  local cmd
  for cmd in pct pveam pvesh pvesm; do command -v "$cmd" >/dev/null || die "$cmd not found. Run this on a Proxmox VE host."; done

  # --- update an existing one ---
  local id; id="$(find_tagged)"
  if [[ -n "$id" ]]; then
    step "Updating Pisagem in container $id"
    run_inside "$id" update
    show_address "$id"; return
  fi
  id="$(find_handmade)"
  if [[ -n "$id" ]]; then
    step "Found OpenRouteService in container $id (/opt/ors)"
    if yesno "Turn container $id into the Pisagem container? Your built route network is kept" Y; then
      pct set "$id" --tags "$TAG" >/dev/null
      local mem; mem=$(pct config "$id" | awk '/^memory:/ {print $2}')
      if (( ${mem:-0} < MEMORY )); then
        warn "Container $id has ${mem:-?} MB of memory; Pisagem needs $MEMORY MB with map data and search."
        if yesno "Raise it to $MEMORY MB now?" Y; then pct set "$id" --memory "$MEMORY" >/dev/null; ok "Memory set to $MEMORY MB"; fi
      fi
      run_inside "$id" update
      show_address "$id"; return
    fi
  fi

  # --- a new container ---
  step "Choosing where it goes"
  [[ -n "$CTID" ]] || CTID="$(pvesh get /cluster/nextid)"
  [[ -n "$STORAGE" ]] || STORAGE="$(pick_storage rootdir local-lvm)"
  [[ -n "$TEMPLATE_STORE" ]] || TEMPLATE_STORE="$(pick_storage vztmpl local)"
  [[ -n "$BRIDGE" ]] || BRIDGE="$(pick_bridge)"
  [[ -n "$STORAGE" ]] || die "No active storage found for containers."
  [[ -n "$TEMPLATE_STORE" ]] || die "No active storage found for templates."
  [[ -n "$BRIDGE" ]] || die "No network bridge found (expected vmbr0)."
  for v in CTID CORES MEMORY SWAP DISK_GB; do is_number "${!v}" || die "$v must be a number."; done
  pct status "$CTID" >/dev/null 2>&1 && die "Container $CTID already exists. Choose another: CTID=… bash pisagem.sh"
  ok "Container $CTID on $STORAGE, network $BRIDGE, $CORES cores, $MEMORY MB, ${DISK_GB} GB"

  local avail; avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' "${MEMINFO:-/proc/meminfo}" 2>/dev/null || echo 0)
  if (( avail > 0 && avail < MEMORY )); then
    warn "The host has about $avail MB free, and Pisagem wants $MEMORY MB."
    yesno "Create it anyway? (Proxmox lends memory, but the host may slow down)" N || die "Stopped; nothing was created. Free some memory or run with MEMORY=…"
  fi

  step "Preparing the container"
  pveam update >/dev/null 2>&1 || true
  local template
  template="$(pveam available --section system | awk '/debian-12-standard_.*_amd64\.tar\.zst/ {print $2}' | sort -V | tail -n 1)"
  [[ -n "$template" ]] || die "No Debian 12 template found. Check the host's internet access."
  pveam list "$TEMPLATE_STORE" 2>/dev/null | grep -q "$template" || pveam download "$TEMPLATE_STORE" "$template" >/dev/null
  ok "Template $template"

  pct create "$CTID" "$TEMPLATE_STORE:vztmpl/$template" \
    --hostname "$HOSTNAME_CT" --tags "$TAG" \
    --cores "$CORES" --memory "$MEMORY" --swap "$SWAP" \
    --rootfs "$STORAGE:$DISK_GB" \
    --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp" \
    --features nesting=1,keyctl=1 \
    --unprivileged 1 --onboot 1 --start 1 >/dev/null \
    || die "Proxmox couldn't create container $CTID. Nothing else was changed."
  trap 'die "Something failed on line $LINENO. Container '"$CTID"' exists: to start over, pct destroy '"$CTID"' and run again."' ERR
  ok "Container $CTID created and started"

  run_inside "$CTID" install
  show_address "$CTID"
}

if [[ "${1:-}" == "--in-container" ]]; then
  in_container "${2:-install}"
else
  on_host
fi
