#!/bin/bash
# PostgreSQL 自动安装和配置脚本

# 严格模式设置，提高脚本健壮性
set -euo pipefail

# 全局变量定义
readonly VERSION="12.8"
readonly PG_INSTALL_BASE_DIR="/data/postgres"
readonly PG_INSTALL_DIR="${PG_INSTALL_BASE_DIR}/${VERSION}"
readonly PG_SRC_DIR="${PG_INSTALL_DIR}/pgsql-source"
readonly PG_DATA_DIR="${PG_INSTALL_DIR}/data"
readonly PG_BIN_DIR="${PG_INSTALL_DIR}/bin"
readonly PG_LOG_DIR="/home/postgres"
readonly PG_USER="postgres"
readonly PG_GROUP="${PG_USER}"

# 日志记录函数
log() {
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*"
}

# 错误处理函数 (添加行号信息)
error_exit() {
    local lineno="$1"
    shift
    log "错误 (第 ${lineno} 行): $*"
    exit 1
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit ${LINENO} "必须以 root 权限运行此脚本。"
    fi
}

# 安装必要的依赖包
install_dependencies() {
    log "正在安装依赖包..."
    yum -y install gcc automake autoconf libtool make \
        readline-devel openssl openssl-devel wget tar gzip perl || \
        error_exit ${LINENO} "依赖包安装失败"
}

# 创建 PostgreSQL 用户和组
create_postgres_user() {
    log "创建 PostgreSQL 用户和组..."
    groupadd -f "${PG_GROUP}"
    useradd -r -g "${PG_GROUP}" -s /bin/bash "${PG_USER}" || \
        error_exit ${LINENO} "创建用户失败"
}

# 设置用户密码（交互式）
set_user_password() {
    log "设置 PostgreSQL 用户密码..."
    passwd "${PG_USER}"
    # 设置密码（建议使用更安全的方式，例如通过脚本生成随机密码并存储在安全的地方）
    # echo "${PG_USER}:YourStrongPassword" | chpasswd # 替换 YourStrongPassword 为实际密码
    #echo "${PG_USER}:${PG_USER}" | chpasswd
}

# 创建目录并设置权限
prepare_directories() {
    log "创建安装目录并设置权限..."
    # mkdir -p "${PG_INSTALL_DIR}" "${PG_LOG_DIR}" "${PG_SRC_DIR} ${PG_DATA_DIR}"
    # chown -R "${PG_USER}:${PG_GROUP}" "${PG_INSTALL_DIR}" "${PG_LOG_DIR}" "${PG_SRC_DIR} ${PG_DATA_DIR}"
    install_dirs=("${PG_INSTALL_DIR}" "${PG_LOG_DIR}" "${PG_SRC_DIR}" "${PG_DATA_DIR}")
    for dir in "${install_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log "创建目录: $dir"
        fi
        chown -R "${PG_USER}:${PG_GROUP}" "$dir"
    done
}

# 下载并安装 PostgreSQL
install_postgresql() {
    log "开始下载和安装 PostgreSQL ${VERSION}..."
    su - "${PG_USER}" << EOF
        # 下载并解压 PostgreSQL 源代码
        cd "${PG_SRC_DIR}" || exit 1 
        wget "https://ftp.postgresql.org/pub/source/v${VERSION}/postgresql-${VERSION}.tar.gz" --no-check-certificate || exit 1
        tar -xvf "postgresql-${VERSION}.tar.gz" || exit 1
        cd "postgresql-${VERSION}" || exit 1
        
        # 配置、编译和安装 PostgreSQL
        ./configure --prefix="${PG_INSTALL_DIR}" --with-openssl || exit 1
        # 使用多核编译，提高速度
        # make -j$(nproc) world || exit 1
        # make install-world || exit 1
        make -j$(nproc)  || exit 1
        make install || exit 1
        
        # 初始化数据库并启动
        "${PG_INSTALL_DIR}/bin/initdb" -D "${PG_DATA_DIR}" || exit 1
        "${PG_INSTALL_DIR}/bin/pg_ctl" -D "${PG_DATA_DIR}" -l "${PG_LOG_DIR}/pg.log" start || exit 1
EOF
}


# 配置环境变量
configure_environment() {
    log "配置环境变量..."
    su - "${PG_USER}" -c "
    if ! grep -q 'PGDATA' ~/.bash_profile; then
        cat >> ~/.bash_profile <<-EOF
PATH=\$PATH:\$HOME/.local/bin:\$HOME/bin:${PG_BIN_DIR}
export PATH
PGDATA=${PG_DATA_DIR}
export PGDATA
EOF
    fi
    source ~/.bash_profile
    "
}

# 配置数据库访问权限
configure_database_access() {
    log "配置数据库访问权限..."
    cat >> "${PG_DATA_DIR}/pg_hba.conf" << EOF
host    all             all             127.0.0.1/32            trust # 本地连接信任
host    all             all             0.0.0.0/0               md5
EOF

    # 修改配置文件
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "${PG_DATA_DIR}/postgresql.conf"
    sed -i "s/#max_connections = 100/max_connections = 1000/g"          "${PG_DATA_DIR}/postgresql.conf"

    # 重启数据库
    su - "${PG_USER}" -c "${PG_BIN_DIR}/pg_ctl restart -m fast" || \
    error_exit ${LINENO} "重启 PostgreSQL 失败"
}

# 创建 PostgreSQL statement 日志目录
create_statement_log_dir() {
    log "创建 PostgreSQL statement 日志目录..."
    local log_dir="${PG_DATA_DIR}/pg_log"
    
    # 创建日志目录
    mkdir -p "${log_dir}"
    
    # 设置目录权限
    chown -R "${PG_USER}:${PG_GROUP}" "${log_dir}"
    
    # 设置目录权限为 750，保证只有 postgres 用户和同组用户可以访问
    chmod 750 "${log_dir}"
}

# 开启 PostgreSQL statement 日志记录
enable_statement_logging() {
    # 检查 statement 日志目录
    create_statement_log_dir

    log "配置 PostgreSQL statement 日志参数..."
    
    # 配置日志收集器
    sed -i "s/#logging_collector = off/logging_collector = on/g" "${PG_DATA_DIR}/postgresql.conf"
    sed -i "s/#log_directory = 'log'/log_directory = 'pg_log'/g" "${PG_DATA_DIR}/postgresql.conf"
    sed -i "s/#log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'/log_filename = 'postgresql-%Y-%m-%d.log'/g" "${PG_DATA_DIR}/postgresql.conf"
    
    # 配置需要记录的语句类型
    sed -i "s/#log_statement = 'none'/log_statement = 'all'/g" "${PG_DATA_DIR}/postgresql.conf"
    
    # 记录语句执行时间
    sed -i "s/#log_duration = off/log_duration = on/g" "${PG_DATA_DIR}/postgresql.conf"
    sed -i "s/#log_min_duration_statement = -1/log_min_duration_statement = 1000/g" "${PG_DATA_DIR}/postgresql.conf"
    
    # 可选：额外的日志参数，根据需要调整
    sed -i "s/#log_min_messages = warning/log_min_messages = log/g" "${PG_DATA_DIR}/postgresql.conf"
    sed -i "s/#log_connections = off/log_connections = on/g" "${PG_DATA_DIR}/postgresql.conf"
    sed -i "s/#log_disconnections = off/log_disconnections = on/g" "${PG_DATA_DIR}/postgresql.conf"

    # 重启数据库
    su - "${PG_USER}" -c "${PG_BIN_DIR}/pg_ctl restart -m fast" || \
    error_exit ${LINENO} "重启 PostgreSQL 失败"
}

# 检查PostgreSQL安装是否成功
check_install_info() {
    log "验证 PostgreSQL 安装是否成功..."
    su - "${PG_USER}" -c "${PG_BIN_DIR}/psql -V"
}

# 主函数
main() {
    check_root
    install_dependencies
    create_postgres_user
    set_user_password
    prepare_directories
    install_postgresql
    configure_environment
    configure_database_access

    # 测试环境启用日志
#    enable_statement_logging

    # 检查安装信息
    check_install_info

    log "PostgreSQL ${VERSION} 安装并配置完成！"
}

# 执行主函数
main
