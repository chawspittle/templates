#!/bin/bash

set -euo pipefail

# 设置只读的全局变量
readonly DOCKER_VERSION="20.10.10"
readonly DOCKER_DOWNLOAD_URL="https://onlyoudockerimages.oss-cn-shenzhen.aliyuncs.com/deploy/rancher/docker-${DOCKER_VERSION}.tgz"
readonly DOCKER_PACKAGE="docker-${DOCKER_VERSION}.tgz"
readonly DOCKER_BIN_DIR="/usr/bin"
readonly DOCKER_SYSTEMD_SERVICE="/etc/systemd/system/docker.service"
readonly DOCKER_CONFIG_DIR="/etc/docker"
readonly DOCKER_USER="docker"
readonly DOCKER_GROUP="docker"
readonly INSECURE_REGISTRY="178.156.2.172:5000"
readonly REGISTRY_MIRRORS=("https://docker.m.daocloud.io" "https://0tjdc2om.mirror.aliyuncs.com" "https://docker.mirror.oyoh.top")
readonly LOG_FILE="/var/log/docker_install.log"


# 日志记录函数
log() {
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" | tee -a "$LOG_FILE"
}

# 错误处理函数 (添加行号信息)
error_exit() {
    local lineno="$1"
    shift
    log "错误 (第 ${lineno} 行): $*"
    exit 1
}

# 检查命令是否存在
require_command() {
    command -v "$1" >/dev/null 2>&1 || error_exit "${LINENO}" "Command '$1' not found."
}

# 检查网络
check_network() {
    log "检查网络连接..."
    require_command curl
    curl -sSf --max-time 5 "$DOCKER_DOWNLOAD_URL" >/dev/null || error_exit "${LINENO}" "下载链接不可用"
}

# 检查并下载 Docker tar 包
download_docker() {
    log "检查 Docker 安装包是否存在..."
    if [[ ! -f "$DOCKER_PACKAGE" ]]; then
        log "正在下载 Docker $DOCKER_VERSION..."
        require_command wget
        wget -O "$DOCKER_PACKAGE" "$DOCKER_DOWNLOAD_URL" || error_exit "${LINENO}" "下载失败"
    else
        log "Docker 安装包已存在，跳过下载"
    fi
}

# 解压 Docker 二进制文件
extract_docker() {
    log "解压 Docker 二进制文件..."
    tar -zxvf "$DOCKER_PACKAGE" || error_exit "${LINENO}" "解压失败"
}

# 创建 Docker 用户和用户组
create_docker_user() {
    log "创建 docker 用户和用户组..."
    if ! getent group "$DOCKER_GROUP" &>/dev/null; then
        groupadd "$DOCKER_GROUP" || error_exit "${LINENO}" "创建 $DOCKER_GROUP 用户组失败"
    fi

    if ! id "$DOCKER_USER" &>/dev/null; then
        useradd -g "$DOCKER_GROUP" "$DOCKER_USER" || error_exit "${LINENO}" "创建 $DOCKER_USER 用户失败"
        # echo "$DOCKER_USER:dockerpassword" | chpasswd
        # 建议使用其他方式设置密码
        log "请手动为 $DOCKER_USER 用户设置密码，例如：passwd $DOCKER_USER"
    fi
}

# 安装 Docker 二进制文件
install_docker_binaries() {
    log "安装 Docker 二进制文件..."
    [[ -d docker ]] || error_exit "${LINENO}" "未找到 Docker 二进制文件目录"
    cp docker/* "$DOCKER_BIN_DIR" || error_exit "${LINENO}" "复制二进制文件失败"
}

# 创建 Docker daemon 配置文件
create_docker_daemon_config() {
    log "创建 Docker 配置文件..."

    # 确保 目录存在
    mkdir -p "$DOCKER_CONFIG_DIR"
    local mirrors=$(printf '"%s",' "${REGISTRY_MIRRORS[@]}" | sed 's/,$//')

    # 生成 daemon.json 文件
    cat > "$DOCKER_CONFIG_DIR/daemon.json" <<-EOF
{
  "registry-mirrors": [$mirrors],
  "log-driver": "json-file",
  "log-opts": {
    "max-size":"1g",
    "max-file":"2"
  },
  "insecure-registries": ["$INSECURE_REGISTRY"]
}
EOF

    # 设置正确的文件权限
    chmod 644 "$DOCKER_CONFIG_DIR/daemon.json"
    log "Docker 配置文件创建完成"
}

# 创建 systemd 服务文件
create_docker_service() {
    log "创建 Docker systemd 服务文件..."
    cat > "$DOCKER_SYSTEMD_SERVICE" <<-EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd --selinux-enabled=false
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process
Restart=on-failure
RestartSec=5s
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$DOCKER_SYSTEMD_SERVICE"
    log "Docker systemd 服务文件创建完成"
}

# 启动并启用 Docker 服务
start_docker_service() {
    log "启动并设置 Docker 服务自启动..."
    systemctl daemon-reload
    systemctl start docker || error_exit "${LINENO}" "Docker 服务启动失败"
    systemctl enable docker.service || error_exit "${LINENO}" "Docker 服务自启动设置失败"
    log "Docker 服务启动并设置为自启动成功"
}

# 主安装流程
main() {
    log "Docker 开始安装..."
    
    check_network
    download_docker
    extract_docker
    create_docker_user
    install_docker_binaries
    create_docker_daemon_config
    create_docker_service
    start_docker_service

    log "Docker 安装完成！"
}

# 执行主安装流程
main
