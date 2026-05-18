#!/bin/bash
# =====================================================
# DIY 脚本第二部分 - 最终修复版（保留 docker-compose）
# 在 feeds install 之后、make defconfig 之前执行
# =====================================================

# =====================================================
# 1. 修改路由器默认主机名
# =====================================================
sed -i 's/OpenWrt/WH3000/g' package/base-files/files/bin/config_generate 2>/dev/null || true

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/01-hostname << 'HOSTNAME_EOF'
#!/bin/sh
uci set system.@system[0].hostname='WH3000'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
exit 0
HOSTNAME_EOF
chmod +x files/etc/uci-defaults/01-hostname
echo ">>> [1/7] 主机名设置完成"

# =====================================================
# 2. 修改默认 LuCI 主题为 Design
# =====================================================
if [ -f package/lean/default-settings/files/zzz-default-settings ]; then
    sed -i 's/luci-theme-bootstrap/luci-theme-design/g' \
        package/lean/default-settings/files/zzz-default-settings
fi
find feeds/luci -name "Makefile" 2>/dev/null \
    | xargs grep -l "bootstrap" 2>/dev/null \
    | while read f; do
        sed -i 's/luci-theme-bootstrap/luci-theme-design/g' "$f"
    done
echo ">>> [2/7] 默认主题改为 luci-theme-design"

# =====================================================
# 3. 修复 docker-compose 编译失败（降级到 v2.27.1）
# =====================================================
COMPOSE_MK="feeds/packages/utils/docker-compose/Makefile"
if [ -f "$COMPOSE_MK" ]; then
    echo ">>> [3/7] 修复 docker-compose 版本（降级）..."
    cp "$COMPOSE_MK" "${COMPOSE_MK}.bak"
    sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=2.27.1/' "$COMPOSE_MK"
    sed -i 's/^PKG_HASH:=.*/PKG_HASH:=skip/' "$COMPOSE_MK"
    sed -i '/^PKG_MIRROR_HASH/d' "$COMPOSE_MK"
    echo ">>> docker-compose 已锁定为 v2.27.1"
    grep "^PKG_VERSION" "$COMPOSE_MK"
else
    echo "⚠️  [3/7] 未找到 docker-compose Makefile，跳过"
fi

# =====================================================
# 4. 修复 Lucky 执行权限
# =====================================================
echo ">>> [4/7] 修复 Lucky 执行权限..."
find feeds/lucky/ -type f \( -name "lucky" -o -name "lucky*" \) \
    -exec chmod +x {} \; 2>/dev/null || true
find package/ -path "*/lucky/files*" -type f \
    -exec file {} \; 2>/dev/null \
    | grep -i "ELF\|executable" \
    | cut -d: -f1 \
    | xargs chmod +x 2>/dev/null || true
echo ">>> Lucky 权限修复完成"

# =====================================================
# 5. ★ WiFi 修复：只设置 SSID / 密码，不手动 wifi up ★
# =====================================================
cat > files/etc/uci-defaults/99-wifi-setup << 'WIFI_EOF'
#!/bin/sh
# WiFi 初始设置（不调用 wifi up，避免破坏网络启动流程）

# 确保 radio 开启
uci set wireless.radio0.disabled='0' 2>/dev/null || true
uci set wireless.radio1.disabled='0' 2>/dev/null || true

# 设置 5G WiFi
uci set wireless.default_radio0.ssid='WH3000_5G' 2>/dev/null || true
uci set wireless.default_radio0.encryption='psk2+ccmp' 2>/dev/null || true
uci set wireless.default_radio0.key='password123' 2>/dev/null || true

# 设置 2.4G WiFi
uci set wireless.default_radio1.ssid='WH3000_2.4G' 2>/dev/null || true
uci set wireless.default_radio1.encryption='psk2+ccmp' 2>/dev/null || true
uci set wireless.default_radio1.key='password123' 2>/dev/null || true

uci commit wireless
logger -t wifi-setup "WiFi SSID and key configured"
exit 0
WIFI_EOF
chmod +x files/etc/uci-defaults/99-wifi-setup
echo ">>> [5/7] WiFi 配置已写入（不手动 wifi up）"

# =====================================================
# 6. ★ Docker 数据目录 + 自动挂载修复 ★
# =====================================================

# 6a. 自动挂载配置（打开全局自动挂载 + 添加 mmcblk0p7）
cat > files/etc/uci-defaults/10-fstab << 'FSTAB_EOF'
#!/bin/sh
# 全局：自动挂载未分配空间
uci set fstab.@global[0].anon_mount='1'
uci commit fstab

# 添加 mmcblk0p7 挂载点（如果不存在）
if ! grep -q mmcblk0p7 /etc/config/fstab 2>/dev/null; then
    uci add fstab mount
    uci set fstab.@mount[-1].target='/mnt/mmcblk0p7'
    uci set fstab.@mount[-1].device='/dev/mmcblk0p7'
    uci set fstab.@mount[-1].fstype='ext4'
    uci set fstab.@mount[-1].options='rw,noatime'
    uci set fstab.@mount[-1].enabled='1'
    uci commit fstab
    mkdir -p /mnt/mmcblk0p7
    logger -t fstab "mmcblk0p7 mount added"
fi
exit 0
FSTAB_EOF
chmod +x files/etc/uci-defaults/10-fstab

# 6b. Docker 运行时配置（确保 UCI 提前执行）
cat > files/etc/uci-defaults/20-docker-config << 'DOCKER_EOF'
#!/bin/sh
# 无论分区是否挂载，先设置 UCI 中的 Docker 数据目录
uci set docker.globals.data_root='/mnt/mmcblk0p7/docker'
uci commit docker

MOUNT_POINT="/mnt/mmcblk0p7"
DAEMON_DIR="/tmp/dockerd"
DAEMON_JSON="$DAEMON_DIR/daemon.json"

# 等待挂载点就绪（最多 15 秒）
count=0
while [ $count -lt 15 ]; do
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        break
    fi
    sleep 1
    count=$((count + 1))
done

# 如果成功挂载，写入运行时 daemon.json
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    DOCKER_DATA="$MOUNT_POINT/docker"
    mkdir -p "$DOCKER_DATA" "$DAEMON_DIR"
    cat > "$DAEMON_JSON" << JSONEOF
{
  "data-root": "$DOCKER_DATA",
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "iptables": true,
  "live-restore": true
}
JSONEOF
    logger -t docker-config "Docker data-root set to $DOCKER_DATA"
else
    logger -t docker-config "WARNING: $MOUNT_POINT not mounted, Docker will use /opt/docker"
fi

exit 0
DOCKER_EOF
chmod +x files/etc/uci-defaults/20-docker-config

echo ">>> [6/7] Docker 配置完成（分区自动挂载 + 数据目录已设置）"

# =====================================================
# 7. Web 界面 / Samba / rpcd 优化
# =====================================================
cat > files/etc/uci-defaults/98-system-optimize << 'OPT_EOF'
#!/bin/sh
# uhttpd 优化
uci -q set uhttpd.main.max_connections='100' 2>/dev/null || true
uci -q set uhttpd.main.max_requests='10' 2>/dev/null || true
uci -q set uhttpd.main.http_keepalive='20' 2>/dev/null || true
uci -q set uhttpd.main.script_timeout='60' 2>/dev/null || true
uci -q set uhttpd.main.network_timeout='30' 2>/dev/null || true
uci commit uhttpd 2>/dev/null || true

# rpcd 超时
uci -q set rpcd.@rpcd[0].timeout='60' 2>/dev/null || true
uci commit rpcd 2>/dev/null || true

# Samba 禁用 IPv6
uci -q set samba4.@samba[0].disable_ipv6='1' 2>/dev/null || true
uci commit samba4 2>/dev/null || true

# LuCI 语言
uci set luci.main.lang='zh_Hans' 2>/dev/null || true
uci commit luci 2>/dev/null || true

exit 0
OPT_EOF
chmod +x files/etc/uci-defaults/98-system-optimize
echo ">>> [7/7] 系统优化脚本已写入"

# =====================================================
# Banner
# =====================================================
mkdir -p files/etc
cat > files/etc/banner << 'BAN_EOF'
 __      __ _   _  _____   ___   ___   ___
 \ \    / /| | | ||___ /  / _ \ / _ \ / _ \
  \ \/\/ / | |_| |  |_ \ | | | | | | | | | |
   \_/\_/   \___/  |___/ |_| |_|\___/ |_| |_|
  华思飞 WH3000 · LEDE · Kernel 6.6 LTS
-------------------------------------------------
BAN_EOF

echo ""
echo "======================================"
echo " DIY 第二部分全部完成"
echo " 主机名          : WH3000"
echo " 主题            : luci-theme-design"
echo " docker-compose  : 锁定 v2.27.1"
echo " Lucky 权限      : 已修复"
echo " WiFi 设置       : SSID/密码 已写入，不手动 wifi up"
echo " Docker 数据目录 : /mnt/mmcblk0p7/docker（自动挂载已启用）"
echo " 系统优化        : 98-system-optimize"
echo "======================================"
