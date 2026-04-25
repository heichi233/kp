#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误: 请使用 root 权限运行此脚本 (例如: sudo bash setup.sh)。"
  exit 1
fi

echo "========================================="
echo "       IPv6 环境初始化与网络配置脚本"
echo "========================================="
echo ""

# 1. 配置 IPv6 DNS
echo ">>> [1/6] 正在配置 IPv6 DNS..."
echo -e "nameserver 2001:4860:4860::8888\nnameserver 2001:4860:4860::8844" > /etc/resolv.conf
echo "✅ IPv6 DNS 配置完成 (/etc/resolv.conf)。"
echo ""

# 2. 剥离 IPv4 默认网关
echo ">>> [2/6] 正在剥离 IPv4 默认网关（保留内网路由）..."
GW=$(ip route | grep default | awk '{print $3}')
if [ -n "$GW" ]; then
    ip route del default via "$GW"
    echo "✅ 已成功移除 IPv4 默认网关 (原网关: $GW)。"
else
    echo "⚠️ 未找到 IPv4 默认网关，可能已被移除，跳过此步。"
fi
echo ""

# 3. 验证网络
echo ">>> [3/6] 正在验证 IPv6 网络连通性..."
echo "正在请求 curl -6 ip.sb 测定公网 IP："
IPv6_IP=$(curl -s -6 ip.sb)
if [ -n "$IPv6_IP" ]; then
    echo "✅ 网络连接正常，当前 IPv6 地址为: $IPv6_IP"
else
    echo "❌ 无法获取 IPv6 地址，请检查网络配置或等待网络生效。"
fi
echo ""

# 4. 探针被控安装 (自动替换双栈代理)
echo ">>> [4/6] 探针被控安装..."
echo "💡 提示: 当前机器为纯 IPv6，脚本将使用双栈加速站 (proxy.ooo.vg) 为您替换 Github 链接。"
# 修复：加上 < /dev/tty 强制从键盘读取输入
read -p "请输入您的探针安装命令 (直接按回车跳过): " probe_cmd < /dev/tty

if [ -n "$probe_cmd" ]; then
    # 替换原始命令中的 githubusercontent 链接
    modified_cmd="${probe_cmd//https:\/\/raw.githubusercontent.com/https:\/\/proxy.ooo.vg\/raw.githubusercontent.com}"
    # 顺便兼容一下如果是 github.com 原始链接的替换
    modified_cmd="${modified_cmd//https:\/\/github.com/https:\/\/proxy.ooo.vg\/github.com}"
    
    # 在末尾追加 proxy 相关的参数
    modified_cmd="${modified_cmd} --install-ghproxy https://proxy.ooo.vg"
    
    echo "-----------------------------------------"
    echo "🔄 自动修改后的安装命令如下:"
    echo -e "\033[32m$modified_cmd\033[0m"
    echo "-----------------------------------------"
    echo "🚀 正在为您执行探针安装..."
    
    # 使用 eval 执行带有管道符(|)的组合命令
    eval "$modified_cmd"
    
    echo "✅ 探针安装流程结束。"
else
    echo "⏭️ 未输入探针安装命令，已跳过此步。"
fi
echo ""

# 5. 安装 WARP (可选)
echo ">>> [5/6] WARP 安装 (可选)"
# 修复：加上 < /dev/tty 强制从键盘读取输入
read -p "❓ 是否现在安装 WARP？(y/n, 默认 n): " install_warp < /dev/tty
install_warp=${install_warp:-n}

if [[ "$install_warp" =~ ^[Yy]$ ]]; then
    echo "🚀 正在下载并运行 WARP 安装脚本..."
    wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh d
else
    echo "⏭️ 已跳过 WARP 安装。"
fi
echo ""

# 6. 安装代理提示
echo ">>> [6/6] 关于【搭建代理】的说明..."
echo "⛔ 不推荐搭建代理: 当前机器 IP 路由可能较差 (如 HE 线路朝鲜 IP 广播，全球 Ping 300+)，且宿主机母鸡已屏蔽大陆方向的弱代理协议。如确需折腾，请自行研究。"
echo ""

echo "========================================="
echo "              脚本执行完毕！"
echo "========================================="
