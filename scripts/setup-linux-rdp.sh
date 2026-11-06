#!/usr/bin/env bash
# ============================================================================
#  setup-linux-rdp.sh — Multi-Mode Linux Cloud Server & Desktop
#  - Mode "desktop" : Ubuntu XFCE4 GUI + XRDP :3389 + OpenSSH :22 + PulseAudio On-Mic
#  - Mode "polos"   : Linux Polos Tanpa XFCE4 (Headless SSH Server :22 & :3389 Kilat)
# ============================================================================
set -e

STAGE_MODE="${1:---all}"

log() {
  printf "[%s UTC][XyRDP:linux] %s\n" "$(date -u +%H:%M:%S)" "$*"
}

if [ -f /tmp/xyrdp-linux.env ] && [ "$STAGE_MODE" != "--setup-only" ] && [ "$STAGE_MODE" != "--all" ]; then
  # shellcheck disable=SC1091
  . /tmp/xyrdp-linux.env
fi

DUR="${DUR:-342}"
DUR="$(echo "$DUR" | tr -cd '0-9')"
[ -z "$DUR" ] && DUR=342
[ "$DUR" -lt 10 ] && DUR=342
[ "$DUR" -gt 342 ] && DUR=342

LINUX_MODE="$(echo "${LINUX_MODE:-desktop}" | tr '[:upper:]' '[:lower:]')"
if [ "$LINUX_MODE" != "polos" ] && [ "$LINUX_MODE" != "headless" ]; then
  LINUX_MODE="desktop"
else
  LINUX_MODE="polos"
fi

RDP_USER="${RDP_USER:-xyadmin}"
HOST_BASE="$(echo "${HOSTNAME:-rdpfree}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
[ -z "$HOST_BASE" ] && HOST_BASE="rdpfree"
FULL_HOST="${FULL_HOST:-${HOST_BASE}-${GITHUB_RUN_NUMBER:-1}}"
OS_NAME="${OS_NAME:-$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Ubuntu Linux}" || echo "Ubuntu Linux")}"

restore_linux_state() {
  if [ -z "${GITHUB_TOKEN:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then return 0; fi
  local api="https://api.github.com/repos/${GITHUB_REPOSITORY}"
  local asset_id
  asset_id="$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" "$api/releases/tags/xyrdp-state-latest" | jq -r '.assets[]? | select(.name=="xyrdp-linux-state.zip") | .id' | head -n1)"
  if [ -n "$asset_id" ] && [ "$asset_id" != "null" ]; then
    log "Memulihkan state Linux dari Release xyrdp-state-latest (asset $asset_id)..."
    mkdir -p /tmp/xyrdp-restore
    if curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/octet-stream" \
      "$api/releases/assets/${asset_id}" -o /tmp/xyrdp-restore/state.zip; then
      7z x /tmp/xyrdp-restore/state.zip -o/tmp/xyrdp-restore/ext -y >/dev/null 2>&1 || true
      for d in Desktop Documents Downloads .config/google-chrome .config/chromium .mozilla; do
        if [ -d "/tmp/xyrdp-restore/ext/$d" ]; then
          mkdir -p "/home/${RDP_USER}/$d"
          cp -rf "/tmp/xyrdp-restore/ext/$d/." "/home/${RDP_USER}/$d/" 2>/dev/null || true
        fi
      done
      if [ -d "/tmp/xyrdp-restore/ext/_persist" ]; then
        cp -rf "/tmp/xyrdp-restore/ext/_persist/." "/persist/" 2>/dev/null || true
      fi
      if [ -d "/tmp/xyrdp-restore/ext/_tailscale" ]; then
        sudo mkdir -p /var/lib/tailscale
        sudo cp -rf /tmp/xyrdp-restore/ext/_tailscale/. /var/lib/tailscale/ 2>/dev/null || true
      fi
      sudo chown -R "${RDP_USER}:${RDP_USER}" "/home/${RDP_USER}" "/persist"
      log "State Linux (termasuk sesi browser & file) berhasil dipulihkan."
    fi
    rm -rf /tmp/xyrdp-restore
  fi
}

persist_linux_state() {
  if [ -z "${GITHUB_TOKEN:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then return 0; fi
  mkdir -p /tmp/xyrdp-persist/stage
  for d in Desktop Documents Downloads .config/google-chrome .config/chromium .mozilla; do
    if [ -d "/home/${RDP_USER}/$d" ]; then
      mkdir -p "/tmp/xyrdp-persist/stage/$d"
      rsync -a --exclude='*Cache*' --exclude='*cache*' --exclude='*Crash*' "/home/${RDP_USER}/$d/" "/tmp/xyrdp-persist/stage/$d/" 2>/dev/null || cp -rf "/home/${RDP_USER}/$d/." "/tmp/xyrdp-persist/stage/$d/" 2>/dev/null || true
    fi
  done
  if [ -d "/persist" ]; then
    mkdir -p "/tmp/xyrdp-persist/stage/_persist"
    cp -rf "/persist/." "/tmp/xyrdp-persist/stage/_persist/" 2>/dev/null || true
  fi
  if [ -d "/var/lib/tailscale" ]; then
    mkdir -p "/tmp/xyrdp-persist/stage/_tailscale"
    sudo cp -rf /var/lib/tailscale/*.state /tmp/xyrdp-persist/stage/_tailscale/ 2>/dev/null || true
  fi
  rm -f /tmp/xyrdp-persist/xyrdp-linux-state.zip
  (cd /tmp/xyrdp-persist/stage && 7z a -tzip -mx=1 -mmt=on /tmp/xyrdp-persist/xyrdp-linux-state.zip . >/dev/null 2>&1) || true
  if [ ! -f /tmp/xyrdp-persist/xyrdp-linux-state.zip ]; then return 0; fi

  local api="https://api.github.com/repos/${GITHUB_REPOSITORY}"
  local rel_id
  rel_id="$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" "$api/releases/tags/xyrdp-state-latest" | jq -r '.id // empty')"
  if [ -z "$rel_id" ]; then
    rel_id="$(curl -s -X POST -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Content-Type: application/json" \
      "$api/releases" -d '{"tag_name":"xyrdp-state-latest","name":"XyRDP Persistent Session State (Auto-Save)","prerelease":true}' | jq -r '.id // empty')"
  fi
  if [ -n "$rel_id" ]; then
    local old_asset
    old_asset="$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" "$api/releases/tags/xyrdp-state-latest" | jq -r '.assets[]? | select(.name=="xyrdp-linux-state.zip") | .id' | head -n1)"
    if [ -n "$old_asset" ] && [ "$old_asset" != "null" ]; then
      curl -s -X DELETE -H "Authorization: Bearer ${GITHUB_TOKEN}" "$api/releases/assets/${old_asset}" >/dev/null 2>&1 || true
    fi
    curl -s -X POST -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Content-Type: application/zip" \
      "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${rel_id}/assets?name=xyrdp-linux-state.zip" \
      --data-binary @/tmp/xyrdp-persist/xyrdp-linux-state.zip >/dev/null 2>&1 || true
    log "State Linux berhasil disimpan ke Release xyrdp-state-latest."
  fi
  rm -rf /tmp/xyrdp-persist
}

publish_linux_status() {
  local active_flag="$1"
  local now_iso
  now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local start_ref="${START_ISO:-$now_iso}"
  local exp_ref="${EXP_ISO:-$now_iso}"
  local ts_ref="${TS_IP:-}"
  local cpu_cores ram_total_gb ram_used_gb disk_total_gb disk_free_gb disk_used_gb uptime_min
  cpu_cores="$(nproc)"
  ram_total_gb="$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)"
  ram_used_gb="$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f", (t-a)/1024/1024}' /proc/meminfo)"
  disk_total_gb="$(df -BG / | awk 'NR==2 {gsub("G","",$2); print $2}')"
  disk_free_gb="$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')"
  disk_used_gb="$(df -BG / | awk 'NR==2 {gsub("G","",$3); print $3}')"
  uptime_min="$(( ( $(date -u +%s) - $(date -u -d "$start_ref" +%s) ) / 60 ))"

  mkdir -p out
  local default_port=3389
  local os_label="$OS_NAME (XFCE4 Desktop)"
  local os_style="Linux XFCE4 Desktop"
  local listen_label="LISTENING :3389 (xrdp) + :22 (ssh)"
  if [ "$LINUX_MODE" = "polos" ]; then
    default_port=22
    os_label="$OS_NAME (Linux Polos · SSH Server)"
    os_style="Linux Polos (SSH Server)"
    listen_label="LISTENING :22 & :3389 (sshd)"
  fi

  local connect_host="$ts_ref"
  local connect_port="$default_port"
  fi

  jq -n \
    --argjson active "$active_flag" \
    --arg hostname "$FULL_HOST" \
    --arg os "$os_label" \
    --arg os_style "$os_style" \
    --arg linux_mode "$LINUX_MODE" \
    --arg listen_label "$listen_label" \
    --arg rdp_user "$RDP_USER" \
    --arg started_at "$start_ref" \
    --arg expires_at "$exp_ref" \
    --arg heartbeat_at "$now_iso" \
    --arg run_id "${GITHUB_RUN_ID:-0}" \
    --arg run_attempt "${GITHUB_RUN_ATTEMPT:-1}" \
    --arg run_number "${GITHUB_RUN_NUMBER:-1}" \
    --arg run_url "https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" \
    --arg akses_mode "${AKSES:-tailscale}" \
    --arg ts_ip "$ts_ref" \
    --arg connect_host "$connect_host" \
    --argjson connect_port "${connect_port:-$default_port}" \
    --argjson default_port "$default_port" \
    --argjson dur "$DUR" \
    --argjson cpu_cores "$cpu_cores" \
    --argjson ram_total "$ram_total_gb" \
    --argjson ram_used "$ram_used_gb" \
    --argjson disk_total "$disk_total_gb" \
    --argjson disk_free "$disk_free_gb" \
    --argjson disk_used "$disk_used_gb" \
    --argjson uptime_min "$uptime_min" \
    '{
      active: $active,
      hostname: $hostname,
      os: $os,
      os_style: $os_style,
      linux_mode: $linux_mode,
      rdp_port: $default_port,
      ssh_port: 22,
      rdp_user: $rdp_user,
      rdp_listen: $listen_label,
      started_at: $started_at,
      expires_at: $expires_at,
      heartbeat_at: $heartbeat_at,
      duration_menit: $dur,
      run_id: $run_id,
      run_attempt: $run_attempt,
      run_number: $run_number,
      run_url: $run_url,
      hardware: {
        cpu_threads: $cpu_cores,
        cpu_cores: $cpu_cores,
        cpu_load_pct: 5,
        ram_gb: $ram_total,
        ram_total_gb: $ram_total,
        ram_used_gb: $ram_used,
        disk_total_gb: $disk_total,
        disk_free_gb: $disk_free,
        disk_used_gb: $disk_used,
        uptime_minutes: $uptime_min
      },
      akses: {
        mode: $akses_mode,
        tailscale: {
          status: (if $ts_ip != "" then "ok" else "pending" end),
          ip: $ts_ip,
          hostname: $hostname,
          port: $default_port,
          ssh_port: 22,
          connect: (if $ts_ip != "" then ($ts_ip + ":" + ($default_port|tostring)) else "" end)
        },
        tunnel: {
          status: (if $connect_host != "" then "ok" else "pending" end),
          type: $akses_mode,
          host: $connect_host,
          port: $connect_port,
          address: (if $connect_host != "" then ($connect_host + ":" + ($connect_port|tostring)) else "" end),
          connect: ($connect_host + ":" + ($connect_port|tostring))
        }
      }
    }' > out/rdp-status.json

  local tmp_git="/tmp/xyrdp-status-branch"
  rm -rf "$tmp_git"
  mkdir -p "$tmp_git/out"
  cp out/rdp-status.json "$tmp_git/rdp-status.json"
  cp out/rdp-status.json "$tmp_git/out/rdp-status.json"
  (
    cd "$tmp_git"
    git init -q
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git checkout -B status -q
    git add rdp-status.json out/rdp-status.json
    git commit -q -m "status: linux rdp (${LINUX_MODE}) update"
    git push -f -q "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" status:status || true
  )
}

if [ "$STAGE_MODE" = "--finalize-only" ]; then
  log "Menyimpan state Linux akhir & membersihkan status sesi..."
  persist_linux_state || true
  publish_linux_status false || true
  exit 0
fi

if [ "$STAGE_MODE" = "--keepalive-only" ]; then
  log "Menjalankan keepalive sesi Linux (${LINUX_MODE}) — ${TS_IP:-} (user: ${RDP_USER})..."
  i=0
  while [ "$(date -u +%s)" -lt "$(( ${EXP_EPOCH:-0} - 180 ))" ]; do
    sleep 60
    i=$((i + 1))
    if [ "$LINUX_MODE" = "desktop" ]; then
      if ! pgrep -x xrdp >/dev/null 2>&1; then
        sudo systemctl restart xrdp-sesman xrdp || true
      fi
    else
      if ! pgrep -x sshd >/dev/null 2>&1; then
        sudo systemctl restart ssh >/dev/null 2>&1 || sudo systemctl restart sshd >/dev/null 2>&1 || true
      fi
    fi
    if [ $((i % 3)) -eq 0 ]; then
      publish_linux_status true || true
    fi
    if [ $((i % 15)) -eq 0 ]; then
      persist_linux_state || true
    fi
  done
  log "Durasi sesi Linux selesai."
  exit 0
fi

if [ -z "${RDP_PASSWORD:-}" ] || [ "${#RDP_PASSWORD}" -lt 8 ]; then
  log "ERROR: secret RDP_PASSWORD belum di-set / kurang dari 8 karakter."
  exit 1
fi

log "Menyiapkan Linux Cloud (${LINUX_MODE}) | host=$FULL_HOST | user=$RDP_USER | durasi=${DUR}m"

# 1. Buat user sudo + konfigurasi grup
if ! id "$RDP_USER" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$RDP_USER"
fi
echo "${RDP_USER}:${RDP_PASSWORD}" | sudo chpasswd
echo "root:${RDP_PASSWORD}" | sudo chpasswd || true
sudo usermod -aG sudo,adm,audio,video "$RDP_USER" || true
echo "${RDP_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/xyrdp-${RDP_USER}" >/dev/null
sudo chmod 0440 "/etc/sudoers.d/xyrdp-${RDP_USER}"
sudo mkdir -p "/persist" "/home/${RDP_USER}/Desktop" "/home/${RDP_USER}/Documents" "/home/${RDP_USER}/Downloads"
sudo chown -R "${RDP_USER}:${RDP_USER}" "/persist" "/home/${RDP_USER}"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq

if [ "$LINUX_MODE" = "polos" ]; then
  # ==========================================================================
  # MODE LINUX POLOS (TANPA XFCE4 / HEADLESS SSH VPS SERVER)
  # ==========================================================================
  log "Mode Linux Polos dipilih (Tanpa XFCE4 GUI) — memasang OpenSSH Server & CLI tools..."
  sudo apt-get install -y -qq \
    openssh-server p7zip-full curl wget jq git unzip zip \
    htop tmux screen python3 python3-pip net-tools iproute2 ca-certificates

  sudo mkdir -p /run/sshd /etc/ssh/sshd_config.d
  cat << 'EOF' | sudo tee /etc/ssh/sshd_config.d/99-xyrdp.conf >/dev/null
Port 22
Port 3389
PasswordAuthentication yes
KbdInteractiveAuthentication yes
ChallengeResponseAuthentication yes
PermitRootLogin yes
UsePAM yes
X11Forwarding yes
PrintMotd no
EOF
  sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
  sudo sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config || true
  sudo systemctl enable ssh >/dev/null 2>&1 || sudo systemctl enable sshd >/dev/null 2>&1 || true
  sudo systemctl restart ssh >/dev/null 2>&1 || sudo systemctl restart sshd >/dev/null 2>&1 || true
  log "OpenSSH Server aktif di port :22 dan :3389 (siap untuk Tailscale)."
else
  # ==========================================================================
  # MODE LINUX DESKTOP (XFCE4 + XRDP :3389 + OpenSSH :22 + PulseAudio On-Mic)
  # ==========================================================================
  log "Mode Linux Desktop dipilih — memasang XFCE4 + XRDP :3389 + OpenSSH :22 + Audio/On-Mic..."
  sudo apt-get install -y -qq \
    openssh-server \
    xfce4 xfce4-goodies xfce4-terminal \
    xrdp xorgxrdp dbus-x11 \
    p7zip-full curl wget jq git unzip zip htop tmux \
    pulseaudio pavucontrol alsa-utils \
    mesa-utils libgl1-mesa-dri

  if [ "${MINECRAFT_JAVA:-tidak}" = "ya" ]; then
    log "Memasang OpenJDK 21 & OpenJDK 8 untuk Minecraft Java..."
    sudo apt-get install -y -qq openjdk-21-jre openjdk-8-jre || true
  fi

  if [ "${SAMP:-tidak}" = "ya" ]; then
    log "Memasang Wine untuk kompatibilitas aplikasi/game Windows di Linux..."
    sudo apt-get install -y -qq wine64 wine || true
  fi

  sudo mkdir -p /run/sshd /etc/ssh/sshd_config.d
  cat << 'EOF' | sudo tee /etc/ssh/sshd_config.d/99-xyrdp.conf >/dev/null
Port 22
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitRootLogin yes
UsePAM yes
EOF
  sudo systemctl enable ssh >/dev/null 2>&1 || sudo systemctl enable sshd >/dev/null 2>&1 || true
  sudo systemctl restart ssh >/dev/null 2>&1 || sudo systemctl restart sshd >/dev/null 2>&1 || true

  sudo mkdir -p /etc/pulse/default.pa.d
  cat << 'EOF' | sudo tee /etc/pulse/default.pa.d/xyrdp-onmic.pa >/dev/null
load-module module-null-sink sink_name=XyDesk_Speaker sink_properties=device.description="XyDesk_Remote_Audio"
load-module module-Null-sink sink_name=XyDesk_Mic_Backing sink_properties=device.description="XyDesk_Mic_Bus"
load-module module-virtual-source source_name=XyDesk_Virtual_Mic master=XyDesk_Mic_Backing.monitor source_properties=device.description="XyDesk_OnMic_Input"
set-default-sink XyDesk_Speaker
set-default-source XyDesk_Virtual_Mic
EOF

  sudo adduser xrdp ssl-cert || true
  echo "xfce4-session" | sudo -u "$RDP_USER" tee "/home/${RDP_USER}/.xsession" >/dev/null
  sudo chmod +x "/home/${RDP_USER}/.xsession"
  sudo sed -i 's/^tcp_nodelay=.*/tcp_nodelay=true/' /etc/xrdp/xrdp.ini || true
  sudo sed -i 's/^max_bpp=.*/max_bpp=32/' /etc/xrdp/xrdp.ini || true
  sudo systemctl enable xrdp xrdp-sesman || true
  sudo systemctl restart xrdp-sesman xrdp
fi

restore_linux_state
sudo ln -sfn /persist "/home/${RDP_USER}/Desktop/Folder-Permanen-AntiReset" || true
sudo ln -sfn /persist "/home/${RDP_USER}/persist" || true
sudo chown -h "${RDP_USER}:${RDP_USER}" "/home/${RDP_USER}/Desktop/Folder-Permanen-AntiReset" "/home/${RDP_USER}/persist" 2>/dev/null || true

# 4. Hubungkan Tailscale
TS_IP=""
log "Menyiapkan akses Tailscale..."
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
sudo systemctl enable --now tailscaled
sudo tailscale up --authkey="${TAILSCALE_AUTH_KEY}" --hostname="${FULL_HOST}" --accept-routes --reset
for _ in $(seq 1 20); do
  TS_IP="$(tailscale ip -4 2>/dev/null | head -n1 | tr -d '[:space:]')"
  [ -n "$TS_IP" ] && break
  sleep 2
done
log "Tailscale terhubung: IP=${TS_IP}"

START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXP_EPOCH="$(( $(date -u +%s) + DUR * 60 ))"
EXP_ISO="$(date -u -d "@${EXP_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)"

cat << EOF > /tmp/xyrdp-linux.env
DUR="${DUR}"
LINUX_MODE="${LINUX_MODE}"
RDP_USER="${RDP_USER}"
FULL_HOST="${FULL_HOST}"
TS_IP="${TS_IP}"
START_ISO="${START_ISO}"
EXP_EPOCH="${EXP_EPOCH}"
EXP_ISO="${EXP_ISO}"
OS_NAME="${OS_NAME}"
EOF

publish_linux_status true
log "SESI LINUX (${LINUX_MODE}) SIAP — ${TS_IP} (user: ${RDP_USER})"

if [ "$STAGE_MODE" = "--setup-only" ]; then
  exit 0
fi

cleanup_on_exit() {
  log "Menyimpan state Linux akhir & membersihkan status sesi..."
  persist_linux_state || true
  publish_linux_status false || true
}
trap cleanup_on_exit EXIT INT TERM

i=0
while [ "$(date -u +%s)" -lt "$(( EXP_EPOCH - 180 ))" ]; do
  sleep 60
  i=$((i + 1))
  if [ "$LINUX_MODE" = "desktop" ]; then
    if ! pgrep -x xrdp >/dev/null 2>&1; then
      sudo systemctl restart xrdp-sesman xrdp || true
    fi
  else
    if ! pgrep -x sshd >/dev/null 2>&1; then
      sudo systemctl restart ssh >/dev/null 2>&1 || sudo systemctl restart sshd >/dev/null 2>&1 || true
    fi
  fi
  if [ $((i % 3)) -eq 0 ]; then
    publish_linux_status true || true
  fi
  if [ $((i % 15)) -eq 0 ]; then
    persist_linux_state || true
  fi
done

log "Durasi sesi Linux selesai."
