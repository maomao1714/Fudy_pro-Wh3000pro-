#!/bin/bash
# =====================================================
# DIY 脚本第一部分：在 feeds update 之前执行
# 主要用途：添加自定义软件源
# =====================================================

# 添加 Lucky 软件源（内网穿透/DDNS工具）
echo "src-git lucky https://github.com/gdy666/luci-app-lucky.git" >> feeds.conf.default

# 添加 Qmodem 软件源（4G/5G模块管理）
echo "src-git qmodem https://github.com/FUjr/modem_feeds.git;main" >> feeds.conf.default

# 如果你需要 SSR-Plus，取消下面这行的注释
# echo "src-git helloworld https://github.com/fw876/helloworld.git" >> feeds.conf.default

echo "✅ 软件源添加完成"
