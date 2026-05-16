#!/bin/bash
# =====================================================
# DIY 脚本第二部分
# 在 feeds install 之后、make defconfig 之前执行
# =====================================================

set -e

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
# 3. ★ 修复 WiFi 首次启动不出现的问题 ★
#
# 根因：mt7981-wo-firmware（Wireless Offload 固件）
# 在系统第一次启动时，netifd 比 wo-firmware 先加载完成，
# 导致 radio0/radio1 初始化竞争失败，WiFi 不出现。
# 重启后时序恢复正常，所以重启一次就有 WiFi 了。
#
# 修复方案：通过 uci-defaults 在首次启动时强制重启 netifd，
# 使其在 wo-firmware 稳定后重新初始化无线接口。
# =====================================================
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/10-wifi-init-fix << 'WIFI_EOF'
#!/bin/sh
# ★ MT7981 WiFi 首次启动修复脚本 ★
# 等待 wo-firmware 加载完成，再重启 netifd 使 radio 正常初始化

logger -t wifi-init "MT7981 wo-firmware 启动修复：等待固件加载..."

# 等待 mt7915e 驱动模块加载（最多等 30 秒）
count=0
while [ $count -lt 30 ]; do
    if lsmod | grep -q "mt7915e"; then
        break
    fi
    sleep 1
    count=$((count + 1))
done

# 再额外等 3 秒让 wo-firmware 完全就绪
sleep 3

# 重启 netifd 使其重新扫描并初始化无线接口
logger -t wifi-init "mt7915e 已加载，重启 netifd 以初始化 WiFi radio..."
/etc/init.d/network restart

logger -t wifi-init "WiFi 初始化修复完成"
exit 0
WIFI_EOF
chmod +x files/etc/uci-defaults/10-wifi-init-fix

echo ">>> [3/5] WiFi 首次启动修复脚本已写入"

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
echo " WiFi修复  : uci-defaults/10-wifi-init-fix"
echo " Web优化   : uci-defaults/99-uhttpd-optimize"
echo "======================================"

