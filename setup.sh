#!/bin/sh

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 错误: 请使用 root 权限运行此脚本 (例如: sudo sh setup.sh)。"
  exit 1
fi

# 获取操作系统类型
OS=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "❌ 无法读取 /etc/os-release，无法识别操作系统类型！"
    exit 1
fi

echo "========================================="
echo "    IPv6 环境初始化与网络配置脚本"
echo "    当前识别到的系统: $OS"
echo "========================================="
echo ""

# ==========================================
#              Alpine 专属逻辑
# ==========================================
run_alpine() {
    # 1.1 更新系统及安装软件包
    echo ">>> [1/7] 正在更新系统并安装必要软件包..."
    apk update && apk add ca-certificates gcompat bash curl wget bind-tools
    if [ $? -eq 0 ]; then
        echo "✅ 软件包安装完成。"
    else
        echo "❌ 软件包安装失败，请检查网络。"
        exit 1
    fi
    echo ""

    # 1.2 剥离 IPv4 默认网关
    echo ">>> [2/7] 正在剥离 IPv4 默认网关（保留内网路由）..."
    GW=$(ip route | grep default | awk '{print $3}')
    if [ -n "$GW" ]; then
        ip route del default via "$GW"
        echo "✅ 已成功移除 IPv4 默认网关 (原网关: $GW)。"
    else
        echo "⚠️ 未找到 IPv4 默认网关，可能已被移除，跳过此步。"
    fi
    echo ""

    # 1.3 配置 IPv6 DNS
    echo ">>> [3/7] 正在配置 IPv6 DNS..."
    printf "nameserver 2001:4860:4860::8888\nnameserver 2001:4860:4860::8844\n" > /etc/resolv.conf
    echo "✅ IPv6 DNS 配置完成 (/etc/resolv.conf)。"
    echo ""

    # 1.5 绑定 GitHub API
    echo ">>> [4/7] 正在绑定 GitHub API 到 IPv6..."
    sed -i '/api.github.com/d' /etc/hosts
    echo "2001:4860:4802:32::118 api.github.com" >> /etc/hosts
    echo "✅ GitHub API 已指向 IPv6 节点。"
    echo ""

    # 1.6 调整传输 MTU
    echo ">>> [5/7] 正在调整网卡 eth0 的 MTU 为 1280..."
    ip link set eth0 mtu 1280
    if [ $? -eq 0 ]; then
        echo "✅ MTU 设置成功。"
    else
        echo "⚠️ MTU 设置失败，请检查是否存在 eth0 网卡。"
    fi
    echo ""

    # 1.4 强制静态解析
    echo ">>> [6/7] 强制静态解析探针主控域名..."
    echo "💡 提示: 请输入您的探针面板域名 (例如: nezha.example.com)，请勿携带 http(s)://"
    read -p "探针面板域名 (直接按回车跳过): " DOMAIN < /dev/tty

    if [ -n "$DOMAIN" ]; then
        echo "正在获取 $DOMAIN 的 AAAA 记录..."
        ADDR=$(dig +short AAAA "$DOMAIN" | head -n 1)
        if [ -n "$ADDR" ]; then
            sed -i "/$DOMAIN/d" /etc/hosts
            echo "$ADDR $DOMAIN" >> /etc/hosts
            echo "✅ 已强制静态解析: $ADDR -> $DOMAIN"
        else
            echo "❌ 无法获取 $DOMAIN 的 IPv6 地址，请确认您的探针主控已开启 IPv6 (或已套用双栈 CDN)。"
        fi
    else
        echo "⏭️ 未输入域名，已跳过强制静态解析。"
    fi
    echo ""

    # 1.7 探针被控安装
    echo ">>> [7/7] 探针被控安装..."
    echo "💡 提示: 由于本机仅有 IPv6 出口，脚本将尝试使用双栈加速站 (proxy.ooo.vg) 替换原始 GitHub 链接。"
    read -p "请输入您的探针安装命令 (直接按回车跳过): " probe_cmd < /dev/tty

    if [ -n "$probe_cmd" ]; then
        modified_cmd=$(echo "$probe_cmd" | sed 's|https://raw.githubusercontent.com|https://proxy.ooo.vg/raw.githubusercontent.com|g')
        modified_cmd=$(echo "$modified_cmd" | sed 's|https://github.com|https://proxy.ooo.vg/github.com|g')
        modified_cmd="${modified_cmd} --install-ghproxy https://proxy.ooo.vg"
        
        echo "-----------------------------------------"
        echo "🔄 自动修改后的安装命令如下:"
        printf "\033[32m%s\033[0m\n" "$modified_cmd"
        echo "-----------------------------------------"
        echo "🚀 正在为您执行探针安装..."
        
        bash -c "$modified_cmd"
        echo "✅ 探针安装流程结束。"
    else
        echo "⏭️ 未输入探针安装命令，已跳过此步。"
    fi
}

# ==========================================
#          Debian / Ubuntu 专属逻辑
# ==========================================
run_debian() {
    # 1. 配置 IPv6 DNS
    echo ">>> [1/5] 正在配置 IPv6 DNS..."
    printf "nameserver 2001:4860:4860::8888\nnameserver 2001:4860:4860::8844\n" > /etc/resolv.conf
    echo "✅ IPv6 DNS 配置完成 (/etc/resolv.conf)。"
    echo ""

    # 2. 剥离 IPv4 默认网关
    echo ">>> [2/5] 正在剥离 IPv4 默认网关（保留内网路由）..."
    GW=$(ip route | grep default | awk '{print $3}')
    if [ -n "$GW" ]; then
        ip route del default via "$GW"
        echo "✅ 已成功移除 IPv4 默认网关 (原网关: $GW)。"
    else
        echo "⚠️ 未找到 IPv4 默认网关，可能已被移除，跳过此步。"
    fi
    echo ""

    # 3. 验证网络
    echo ">>> [3/5] 正在验证 IPv6 网络连通性..."
    echo "正在请求 curl -6 ip.sb 测定公网 IP："
    IPv6_IP=$(curl -s -6 ip.sb)
    if [ -n "$IPv6_IP" ]; then
        echo "✅ 网络连接正常，当前 IPv6 地址为: $IPv6_IP"
    else
        echo "❌ 无法获取 IPv6 地址，请检查网络配置或等待网络生效。"
    fi
    echo ""

    # 4. 探针被控安装
    echo ">>> [4/5] 探针被控安装..."
    echo "💡 提示 1: 当前机器为纯 IPv6，脚本将使用双栈加速站 (proxy.ooo.vg) 为您替换 Github 链接。"
    echo "💡 提示 2: 探针安装后若未上线，请检查您的探针主控服务器是否支持 IPv6。如果主控端没有 IPv6 地址，请自行在你的探针主控服务器安装 WARP 提供 IPv6 出口！"
    read -p "请输入您的探针安装命令 (直接按回车跳过): " probe_cmd < /dev/tty

    if [ -n "$probe_cmd" ]; then
        modified_cmd=$(echo "$probe_cmd" | sed 's|https://raw.githubusercontent.com|https://proxy.ooo.vg/raw.githubusercontent.com|g')
        modified_cmd=$(echo "$modified_cmd" | sed 's|https://github.com|https://proxy.ooo.vg/github.com|g')
        modified_cmd="${modified_cmd} --install-ghproxy https://proxy.ooo.vg"
        
        echo "-----------------------------------------"
        echo "🔄 自动修改后的安装命令如下:"
        printf "\033[32m%s\033[0m\n" "$modified_cmd"
        echo "-----------------------------------------"
        echo "🚀 正在为您执行探针安装..."
        
        bash -c "$modified_cmd"
        echo "✅ 探针安装流程结束。"
    else
        echo "⏭️ 未输入探针安装命令，已跳过此步。"
    fi
    echo ""

    # 5. 其他注意事项
    echo ">>> [5/5] 关于【IPv4 出口与代理】的说明..."
    echo "🌐 WARP: 本脚本不再内置 WARP 安装。如需 IPv4 出口，请自行安装 WARP。"
    echo "⛔ 代理: 不推荐搭建代理。当前机器 IP 路由可能较差 (如 HE 线路朝鲜 IP 广播，全球 Ping 300+)，且宿主机母鸡已屏蔽大陆方向的弱代理协议。如确需折腾，请自行研究。"
}

# ==========================================
#               路由与执行
# ==========================================
case "$OS" in
    alpine)
        run_alpine
        ;;
    debian|ubuntu)
        run_debian
        ;;
    *)
        echo "⚠️ 警告: 识别到未知的系统类型 ($OS)！将默认使用 Debian/Ubuntu 逻辑运行..."
        run_debian
        ;;
esac

echo ""
echo "========================================="
echo "             脚本执行完毕！"
echo "========================================="
