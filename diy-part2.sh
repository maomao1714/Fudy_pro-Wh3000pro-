#!/bin/bash
# =====================================================
# DIY 脚本第二部分
# 在 feeds install 之后、make defconfig 之前执行
# =====================================================

set -e

# =====================================================
# 0. ★ 处理 docker-compose 编译问题 ★
#
# 根因：LEDE master 上的 luci-app-dockerman 新版本新增了
# 对 docker-compose 的依赖，而 docker-compose 的 Go 模块
# 在 GitHub Actions 网络环境下无法全部下载，导致编译失败。
#
# 解决方案：
#   编译阶段：从 feeds 中移除 docker-compose 源码包，
#             避免 Go 模块下载失败。
#   运行阶段：内置一个 uci-defaults 脚本，在固件首次启动
#             后自动下载并安装 docker-compose 官方二进制，
#             完全保留 docker-compose 功能。
# =====================================================
echo ">>> [0/5] 处理 docker-compose 编译问题..."
rm -rf feeds/packages/utils/docker-compose 2>/dev/null || true
find . -name "*.stamp" -path "*docker-compose*" -delete 2>/dev/null || true
echo ">>> docker-compose 源码包已从 feeds 中移除（将在运行时安装）"

# 内置 docker-compose 运行时安装脚本
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/20-install-docker-compose << 'COMPOSE_EOF'
#!/bin/sh
# ★ 自动安装 docker-compose 官方二进制 ★
# 在首次启动、网络就绪后执行

ARCH="aarch64"
COMPOSE_BIN="/usr/local/bin/docker-compose"

# 已安装则跳过
if [ -x "$COMPOSE_BIN" ]; then
    logger -t compose-install "docker-compose 已存在，跳过安装"
    exit 0
fi

logger -t compose-install "开始安装 docker-compose（aarch64）..."

# 等待网络就绪（最多等60秒）
count=0
while [ $count -lt 60 ]; do
    if ping -c1 -W2 github.com >/dev/null 2>&1; then
        break
    fi
    sleep 2
    count=$((count + 2))
done

# 获取最新版本号
VERSION=$(wget -qO- "https://api.github.com/repos/docker/compose/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')

if [ -z "$VERSION" ]; then
    logger -t compose-install "无法获取版本号，跳过"
    exit 1
fi

URL="https://github.com/docker/compose/releases/download/v${VERSION}/docker-compose-linux-${ARCH}"
logger -t compose-install "下载 v${VERSION}..."

wget -qO "$COMPOSE_BIN" "$URL" && \
    chmod +x "$COMPOSE_BIN" && \
    logger -t compose-install "docker-compose v${VERSION} 安装成功" || \
    logger -t compose-install "安装失败，请手动安装"

exit 0
COMPOSE_EOF
chmod +x files/etc/uci-defaults/20-install-docker-compose
echo ">>> docker-compose 运行时安装脚本已内置"

# =====================================================
# 1. 修改路由器默认主机名
# =====================================================
sed -i 's/OpenWrt/WH3000Pro/g' package/base-files/files/bin/config_generate
echo ">>> [1/5] 主机名改为 WH3000Pro"

# =====================================================
# 2. 修改默认 LuCI 主题为 Design
# =====================================================
# LEDE 的默认设置文件
if [ -f package/lean/default-settings/files/zzz-default-settings ]; then
    sed -i 's/luci-theme-bootstrap/luci-theme-design/g' \
        package/lean/default-settings/files/zzz-default-settings
fi
# luci feeds 里的主题引用
find feeds/luci -name "Makefile" 2>/dev/null \
    | xargs grep -l "bootstrap" 2>/dev/null \
    | while read f; do
        sed -i 's/luci-theme-bootstrap/luci-theme-design/g' "$f"
    done
echo ">>> [2/5] 默认主题改为 luci-theme-design"

# =====================================================
# 3. ★ 修复 WiFi 首次启动需等待数分钟的问题 ★
#
# 真实根因（来自日志分析）：
#   - WiFi 固件（mt798x-wmac）在启动后约 9 秒就加载完毕
#   - 但 hostapd 在开机后约 335 秒（~5.5分钟）才启动
#   - 原因：netifd 将 hostapd 的启动绑定在 wwan0（移动网络）
#     接口的 ifup 事件链上。wwan0 上线 → firewall reload →
#     才触发 hostapd 初始化。若 wwan0 迟迟不稳定，WiFi 就
#     一直不出现。
#
# 修复方案：
#   用一个独立的 init.d 服务，在系统启动后 15 秒（WiFi 固件
#   已就绪，但不依赖任何网络接口状态）强制执行一次
#   wifi up，让 hostapd 立即初始化，完全脱离 wwan0 依赖。
# =====================================================
mkdir -p files/etc/uci-defaults
mkdir -p files/etc/init.d

# ── 独立 WiFi 启动服务 ──────────────────────────────
cat > files/etc/init.d/wifi-boot-fix << 'WFIX_EOF'
#!/bin/sh /etc/rc.common
# ★ WH3000Pro WiFi 首次启动修复服务 ★
# 在所有网络服务之后（START=25 之后），独立触发 wifi up
# 完全不依赖 wwan0 / firewall 事件链

START=25
STOP=99
USE_PROCD=1

boot() {
    # 后台执行，不阻塞启动流程
    (
        logger -t wifi-boot-fix "等待 WiFi 固件就绪（15秒）..."
        sleep 15

        # 确认 mt798x-wmac 已加载
        count=0
        while [ $count -lt 20 ]; do
            if [ -d /sys/class/ieee80211/phy0 ]; then
                break
            fi
            sleep 1
            count=$((count + 1))
        done

        if [ -d /sys/class/ieee80211/phy0 ]; then
            logger -t wifi-boot-fix "phy0 就绪，执行 wifi up..."
            wifi up
            logger -t wifi-boot-fix "WiFi 启动完成"
        else
            logger -t wifi-boot-fix "警告：phy0 未就绪，跳过"
        fi
    ) &
}

start_service() {
    :
}
WFIX_EOF
chmod +x files/etc/init.d/wifi-boot-fix

# ── uci-defaults：启用该服务 + 写入 WiFi 默认配置 ──
cat > files/etc/uci-defaults/10-wifi-boot-fix << 'UCIWIFI_EOF'
#!/bin/sh
# 启用 wifi-boot-fix 服务（开机自动运行）
/etc/init.d/wifi-boot-fix enable 2>/dev/null || true

# 确保 wireless 配置里 radio 是启用状态（disabled=0）
uci -q set wireless.radio0.disabled='0' 2>/dev/null || true
uci -q set wireless.radio1.disabled='0' 2>/dev/null || true
uci commit wireless 2>/dev/null || true

exit 0
UCIWIFI_EOF
chmod +x files/etc/uci-defaults/10-wifi-boot-fix

echo ">>> [3/5] WiFi 启动修复服务已写入（独立于 wwan0 依赖链）"

# =====================================================
# 4. Web 管理界面优化（uhttpd）
#    使用 uci-defaults 方式，不覆盖原始配置文件
# =====================================================
cat > files/etc/uci-defaults/99-uhttpd-optimize << 'UCI_EOF'
#!/bin/sh
# uhttpd 性能优化 - 首次启动时执行

uci -q set uhttpd.main.max_connections='100'
uci -q set uhttpd.main.max_requests='10'
uci -q set uhttpd.main.http_keepalive='20'
uci -q set uhttpd.main.script_timeout='60'
uci -q set uhttpd.main.network_timeout='30'
uci commit uhttpd
/etc/init.d/uhttpd restart 2>/dev/null || true

exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/99-uhttpd-optimize

# rpcd 超时优化
cat > files/etc/uci-defaults/98-rpcd-timeout << 'RPCD_EOF'
#!/bin/sh
uci -q set rpcd.@rpcd[0].timeout='60' 2>/dev/null || true
uci commit rpcd 2>/dev/null || true
exit 0
RPCD_EOF
chmod +x files/etc/uci-defaults/98-rpcd-timeout

echo ">>> [4/5] uhttpd / rpcd 优化脚本已写入"

# =====================================================
# 5. 自定义 Banner
# =====================================================
mkdir -p files/etc
cat > files/etc/banner << 'BAN_EOF'
 __      __ _   _  _____   ___   ___   ___  
 \ \    / /| | | ||___ /  / _ \ / _ \ / _ \ 
  \ \/\/ / | |_| |  |_ \ | | | | | | | | | |
   \_/\_/   \___/  |___/ |_| |_|\___/ |_| |_|
  华思飞 WH3000 Pro · LEDE · Kernel 6.6 LTS
-------------------------------------------------
BAN_EOF

echo ">>> [5/5] Banner 已自定义"

echo ""
echo "======================================"
echo " DIY 第二部分全部完成"
echo " 主机名    : WH3000Pro"
echo " 主题      : luci-theme-design"
echo " WiFi修复  : init.d/wifi-boot-fix (独立于wwan0依赖链)"
echo " Web优化   : uci-defaults/99-uhttpd-optimize"
echo "======================================"
