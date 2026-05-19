#!/bin/bash
# =====================================================
# DIY 脚本第二部分 - 预置配置文件终极版
# 不再依赖 uci-defaults，直接写入 /etc/config 文件
# =====================================================

# 1. 主机名
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
echo ">>> [1/6] 主机名已配置"

# 2. 主题
if [ -f package/lean/default-settings/files/zzz-default-settings ]; then
    sed -i 's/luci-theme-bootstrap/luci-theme-design/g' \
        package/lean/default-settings/files/zzz-default-settings
fi
find feeds/luci -name "Makefile" 2>/dev/null \
    | xargs grep -l "bootstrap" 2>/dev/null \
    | while read f; do
        sed -i 's/luci-theme-bootstrap/luci-theme-design/g' "$f"
    done
echo ">>> [2/6] 默认主题改为 luci-theme-design"

# 3. Lucky 权限
echo ">>> [3/6] 修复 Lucky 执行权限..."
find feeds/lucky/ -type f \( -name "lucky" -o -name "lucky*" \) \
    -exec chmod +x {} \; 2>/dev/null || true
find package/ -path "*/lucky/files*" -type f \
    -exec file {} \; 2>/dev/null \
    | grep -i "ELF\|executable" \
    | cut -d: -f1 \
    | xargs chmod +x 2>/dev/null || true
echo ">>> Lucky 权限修复完成"

# =====================================================
# 4. ★ 预置无线配置文件（不再依赖启动脚本） ★
# =====================================================
mkdir -p files/etc/config
cat > files/etc/config/wireless << 'WIFI_CONF'
config wifi-device 'radio0'
        option type 'mac80211'
        option channel 'auto'
        option hwmode '11g'
        option path 'platform/soc/18000000.wifi'
        option htmode 'HT40'
        option disabled '0'

config wifi-iface 'default_radio0'
        option device 'radio0'
        option network 'lan'
        option mode 'ap'
        option ssid 'WH3000_2.4G'
        option encryption 'psk2+ccmp'
        option key 'password123'

config wifi-device 'radio1'
        option type 'mac80211'
        option channel 'auto'
        option hwmode '11a'
        option path 'platform/soc/18000000.wifi+1'
        option htmode 'VHT80'
        option disabled '0'

config wifi-iface 'default_radio1'
        option device 'radio1'
        option network 'lan'
        option mode 'ap'
        option ssid 'WH3000_5G'
        option encryption 'psk2+ccmp'
        option key 'password123'
WIFI_CONF
echo ">>> [4/6] 无线配置已预置（路径已修正为 +1）"

# =====================================================
# 5. ★ 预置 fstab 和 Docker 配置文件 ★
# =====================================================
cat > files/etc/config/fstab << 'FSTAB_CONF'
config global
        option anon_mount '1'

config mount
        option target '/mnt/mmcblk0p7'
        option device '/dev/mmcblk0p7'
        option fstype 'ext4'
        option options 'rw,noatime'
        option enabled '1'
FSTAB_CONF

cat > files/etc/config/docker << 'DOCKER_CONF'
config globals
        option data_root '/mnt/mmcblk0p7/docker'
DOCKER_CONF

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/20-docker-prepare << 'DOCKER_PREP'
#!/bin/sh
# 等待分区挂载后创建 docker 目录
MOUNT="/mnt/mmcblk0p7"
for i in $(seq 1 15); do
    mountpoint -q "$MOUNT" && break
    sleep 1
done
if mountpoint -q "$MOUNT"; then
    mkdir -p "$MOUNT/docker"
    logger -t docker-prepare "Docker data directory ready"
else
    logger -t docker-prepare "WARNING: $MOUNT not mounted"
fi
exit 0
DOCKER_PREP
chmod +x files/etc/uci-defaults/20-docker-prepare

echo ">>> [5/6] 分区挂载和 Docker 目录已预置"

# 6. 系统优化（预置部分 uci 配置）
cat > files/etc/uci-defaults/98-system-optimize << 'OPT_EOF'
#!/bin/sh
uci -q set uhttpd.main.max_connections='100' 2>/dev/null || true
uci -q set uhttpd.main.max_requests='10' 2>/dev/null || true
uci -q set uhttpd.main.http_keepalive='20' 2>/dev/null || true
uci -q set uhttpd.main.script_timeout='60' 2>/dev/null || true
uci -q set uhttpd.main.network_timeout='30' 2>/dev/null || true
uci commit uhttpd 2>/dev/null || true

uci -q set rpcd.@rpcd[0].timeout='60' 2>/dev/null || true
uci commit rpcd 2>/dev/null || true

uci -q set samba4.@samba[0].disable_ipv6='1' 2>/dev/null || true
uci commit samba4 2>/dev/null || true

uci set luci.main.lang='zh_Hans' 2>/dev/null || true
uci commit luci 2>/dev/null || true
exit 0
OPT_EOF
chmod +x files/etc/uci-defaults/98-system-optimize
echo ">>> [6/6] 系统优化脚本已写入"

# Banner
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
echo " DIY 第二部分完成（预置配置文件版）"
echo " 无线配置：已预置 /etc/config/wireless"
echo " 分区挂载：已预置 /etc/config/fstab"
echo " Docker  ：已预置 /etc/config/docker"
echo "======================================"
