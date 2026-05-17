#!/bin/bash
# =====================================================
# DIY 脚本第一部分：在 feeds update 之前执行
# 主要用途：添加自定义软件源
# =====================================================

# 添加 Lucky 软件源（内网穿透/DDNS工具）
echo "src-git lucky https://github.com/gdy666/luci-app-lucky.git" >> feeds.conf.default

# 添加 Qmodem 软件源（4G/5G模块管理）
echo "src-git qmodem https://github.com/FUjr/modem_feeds.git;main" >> feeds.conf.default

# 添加 rtp2httpd 软件源（IPTV 组播转单播）
# 使用 main 分支，feeds update 后在 diy-part2 里替换为 Makefile.versioned
# Makefile.versioned 已包含固定版本号和 PKG_HASH，从 Release 下载源码，无需 Node.js 构建前端
echo "src-git rtp2httpd https://github.com/stackia/rtp2httpd.git" >> feeds.conf.default

echo "✅ 软件源添加完成"
