#!/usr/bin/env bash
set -euo pipefail

FRP_NAME="frpc"
FRP_VERSION="${FRP_VERSION:-0.68.1}"
FRP_PATH="/usr/local/frp"
SERVICE_FILE="/etc/systemd/system/${FRP_NAME}.service"
CONFIG_FILE="${FRP_PATH}/${FRP_NAME}.toml"

# 国内优先镜像，可自行替换
GITHUB_PROXY="${GITHUB_PROXY:-https://ghfast.top/}"

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Font="\033[0m"

info()  { echo -e "${Green}[INFO]${Font} $*"; }
warn()  { echo -e "${Yellow}[WARN]${Font} $*"; }
error() { echo -e "${Red}[ERR ]${Font} $*" >&2; }

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    error "请用 root 执行，或 sudo bash install-frpc.sh"
    exit 1
  fi
}

install_pkg() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y wget curl tar
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wget curl tar
  elif command -v yum >/dev/null 2>&1; then
    yum install -y wget curl tar
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache wget curl tar
  else
    error "未识别包管理器，请手动安装 wget curl tar"
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) PLATFORM="amd64" ;;
    aarch64|arm64) PLATFORM="arm64" ;;
    armv7|armv7l|armhf) PLATFORM="arm" ;;
    *)
      error "不支持的架构: $(uname -m)"
      exit 1
      ;;
  esac
  info "当前架构: ${PLATFORM}"
}

check_installed() {
  if [ -f "${FRP_PATH}/${FRP_NAME}" ] || [ -f "${CONFIG_FILE}" ] || [ -f "${SERVICE_FILE}" ]; then
    warn "检测到已安装 frpc"
    warn "如需重装，可先执行："
    echo "systemctl stop ${FRP_NAME} || true"
    echo "rm -rf ${FRP_PATH}"
    echo "rm -f ${SERVICE_FILE}"
    echo "systemctl daemon-reload"
    exit 0
  fi
}

download_with_fallback() {
  FILE_NAME="frp_${FRP_VERSION}_linux_${PLATFORM}"
  OFFICIAL_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz"
  MIRROR_URL="${GITHUB_PROXY}${OFFICIAL_URL}"
  TMP_DIR="$(mktemp -d)"

  info "下载地址优先走镜像: ${GITHUB_PROXY}"
  if wget -O "${TMP_DIR}/${FILE_NAME}.tar.gz" "${MIRROR_URL}"; then
    info "镜像下载成功"
  else
    warn "镜像下载失败，回退 GitHub 官方地址"
    wget -O "${TMP_DIR}/${FILE_NAME}.tar.gz" "${OFFICIAL_URL}"
  fi

  tar -zxf "${TMP_DIR}/${FILE_NAME}.tar.gz" -C "${TMP_DIR}"
  mkdir -p "${FRP_PATH}"
  install -m 755 "${TMP_DIR}/${FILE_NAME}/${FRP_NAME}" "${FRP_PATH}/${FRP_NAME}"
  rm -rf "${TMP_DIR}"
}

write_config() {
  cat > "${CONFIG_FILE}" <<'EOF'
serverAddr = "8.134.148.109"
serverPort = 5443

auth.method = "token"
auth.token = "lCWtjLgMyq8VEYZz"

log.to = "console"
log.level = "info"
log.maxDays = 3

transport.tcpMux = true

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 35281
EOF

  info "已写入配置文件: ${CONFIG_FILE}"
}

write_service() {
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=frp client service
After=network.target

[Service]
Type=simple
WorkingDirectory=${FRP_PATH}
ExecStart=${FRP_PATH}/${FRP_NAME} -c ${CONFIG_FILE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${FRP_NAME}"
  systemctl restart "${FRP_NAME}" || systemctl start "${FRP_NAME}"
}

show_result() {
  echo
  info "frpc 安装完成"
  echo "二进制: ${FRP_PATH}/${FRP_NAME}"
  echo "配置文件: ${CONFIG_FILE}"
  echo "服务文件: ${SERVICE_FILE}"
  echo
  echo "常用命令："
  echo "  systemctl status frpc"
  echo "  systemctl restart frpc"
  echo "  journalctl -u frpc -f"
}

main() {
  require_root
  check_installed
  install_pkg
  detect_arch
  download_with_fallback
  write_config
  write_service
  show_result
}

main "$@"