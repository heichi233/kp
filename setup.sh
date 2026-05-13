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
    # 1.1 更新系统及安装软件包 (加入 sudo 防报错)
    echo ">>> [1/6] 正在更新系统并安装必要软件包..."
    apk update && apk add ca-certificates gcompat bash curl wget bind-tools sudo
    if [ $? -eq 0 ]; then
        echo "✅ 软件包安装完成。"
    else
        echo "❌ 软件包安装失败，请检查网络。"
        exit 1
    fi
    echo ""

    # 1.2 剥离 IPv4 默认网关
    echo ">>> [2/6] 正在剥离 IPv4 默认网关（保留内网路由）..."
    GW=$(ip route | grep default | awk '{print $3}')
    if [ -n "$GW" ]; then
        ip route del default via "$GW"
        echo "✅ 已成功移除 IPv4 默认网关 (原网关: $GW)。"
    else
        echo "⚠️ 未找到 IPv4 默认网关，可能已被移除，跳过此步。"
    fi
    echo ""

    # 1.3 配置 IPv6 DNS
    echo ">>> [3/6] 正在配置 IPv6 DNS..."
    printf "nameserver 2001:4860:4860::8888\nnameserver 2001:4860:4860::8844\n" > /etc/resolv.conf
    echo "✅ IPv6 DNS 配置完成 (/etc/resolv.conf)。"
    echo ""

    # 1.4 绑定 GitHub API
    echo ">>> [4/6] 正在绑定 GitHub API 到 IPv6..."
    sed -i '/api.github.com/d' /etc/hosts
    echo "2001:4860:4802:32::118 api.github.com" >> /etc/hosts
    echo "✅ GitHub API 已指向 IPv6 节点。"
    echo ""

    # 1.5 调整传输 MTU
    echo ">>> [5/6] 正在调整网卡 eth0 的 MTU 为 1280..."
    ip link set eth0 mtu 1280 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ MTU 设置成功。"
    else
        echo "⚠️ MTU 设置失败，可能网卡名称不是 eth0，跳过此步。"
    fi
    echo ""

    # 1.6 探针被控安装 (含自动识别静态解析与地区参数)
    echo ">>> [6/6] 探针自动安装与环境解析..."
    
    echo "🌍 请选择探针区域:"
    echo "  1. 朝鲜"
    echo "  2. 南极"
    echo "  0. 跳过 (不指定地区)"
    read -p "请输入选项 [0/1/2] (默认 0): " region_choice < /dev/tty
    
    custom_ipv4_param=""
    case "$region_choice" in
        1) custom_ipv4_param=" --custom-ipv4 175.45.176.0" ;;
        2) custom_ipv4_param=" --custom-ipv4 104.28.212.152" ;;
        *) custom_ipv4_param="" ;;
    esac
    echo ""

    echo "💡 提示: 请直接粘贴您的【完整探针安装命令】(无需手动输入域名，脚本会自动识别)。"
    read -p "安装命令 (直接按回车跳过): " probe_cmd < /dev/tty

    if [ -n "$probe_cmd" ]; then
        # 自动提取域名：兼容 Komari (-e https://domain) 和 哪吒 (-s domain:port)
        DOMAIN=$(echo "$probe_cmd" | sed -n 's/.*-e[ \t][ \t]*http[s]*:\/\/\([^ \t/]*\).*/\1/p')
        if [ -z "$DOMAIN" ]; then
            DOMAIN=$(echo "$probe_cmd" | sed -n 's/.*-s[ \t][ \t]*\([^ \t:]*\).*/\1/p')
        fi
        
        # 强制静态解析
        if [ -n "$DOMAIN" ]; then
            echo "🔍 自动识别到探针主控域名: $DOMAIN"
            echo "正在获取 $DOMAIN 的 AAAA 记录..."
            ADDR=$(dig +short AAAA "$DOMAIN" | head -n 1)
            if [ -n "$ADDR" ]; then
                sed -i "/$DOMAIN/d" /etc/hosts
                echo "$ADDR $DOMAIN" >> /etc/hosts
                echo "✅ 已强制静态解析: $ADDR -> $DOMAIN"
            else
                echo "❌ 无法获取 $DOMAIN 的 IPv6 地址！请确认您的探针主控已开启 IPv6。"
            fi
        else
            echo "⚠️ 未能自动从命令中提取出域名，将跳过强制解析阶段。"
        fi
        
        # 替换代理并组装最终命令 (包含加速代理和地区参数)
        modified_cmd=$(echo "$probe_cmd" | sed 's|https://raw.githubusercontent.com|https://proxy.ooo.vg/raw.githubusercontent.com|g')
        modified_cmd=$(echo "$modified_cmd" | sed 's|https://github.com|https://proxy.ooo.vg/github.com|g')
        modified_cmd="${modified_cmd} --install-ghproxy https://proxy.ooo.vg${custom_ipv4_param}"
        
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

    # 4. 探针被控安装 (含地区参数)
    echo ">>> [4/5] 探针被控安装..."
    echo "💡 提示 1: 当前机器为纯 IPv6，脚本将使用双栈加速站为您替换 Github 链接。"
    echo "💡 提示 2: 探针安装后若未上线，请自行确认探针主控端已开启 IPv6。"
    echo ""
    
    echo "🌍 请选择探针区域:"
    echo "  1. 朝鲜"
    echo "  2. 南极"
    echo "  0. 跳过 (不指定地区)"
    read -p "请输入选项 [0/1/2] (默认 0): " region_choice < /dev/tty
    
    custom_ipv4_param=""
    case "$region_choice" in
        1) custom_ipv4_param=" --custom-ipv4 175.45.176.0" ;;
        2) custom_ipv4_param=" --custom-ipv4 104.28.212.152" ;;
        *) custom_ipv4_param="" ;;
    esac
    echo ""

    read -p "请输入您的【完整探针安装命令】 (直接按回车跳过): " probe_cmd < /dev/tty

    if [ -n "$probe_cmd" ]; then
        modified_cmd=$(echo "$probe_cmd" | sed 's|https://raw.githubusercontent.com|https://proxy.ooo.vg/raw.githubusercontent.com|g')
        modified_cmd=$(echo "$modified_cmd" | sed 's|https://github.com|https://proxy.ooo.vg/github.com|g')
        modified_cmd="${modified_cmd} --install-ghproxy https://proxy.ooo.vg${custom_ipv4_param}"
        
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
    echo "⛔ 代理: 宿主机存在屏蔽机制，如需折腾弱代理协议请自行研究。"
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
