#!/bin/bash

# =========================================================
# Project: All-in-One Script for Debian/Ubuntu
# Author: Your AI Assistant
# Version: 1.0
# Last Updated: 2025-08-23
# Description: A comprehensive script for VPS initialization and management.
# =========================================================

# --- Color Definitions ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Function to check if running as root ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须以 root 用户身份运行。${NC}"
        echo -e "${YELLOW}请尝试使用 'sudo ./all-in-one.sh'${NC}"
        exit 1
    fi
}

# --- Function to pause execution ---
press_any_key() {
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 1. 开启/设置 Root 权限 (实际是设置密码)
enable_root_login() {
    echo -e "${YELLOW}此功能将为您设置 root 用户密码。${NC}"
    echo -e "在 Ubuntu 系统中，默认 root 账户是被禁用的，设置密码后即可使用 'su root'。"
    read -p "您确定要为 root 用户设置密码吗？(y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        passwd root
        echo -e "${GREEN}root 密码设置成功。${NC}"
    else
        echo -e "${YELLOW}操作已取消。${NC}"
    fi
    press_any_key
}

# 2. 更新系统
update_system() {
    echo -e "${GREEN}正在更新软件包列表...${NC}"
    apt-get update -y
    echo -e "${GREEN}正在升级系统软件包...${NC}"
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    apt-get autoremove -y
    apt-get autoclean -y
    echo -e "${GREEN}系统更新完成。${NC}"
    press_any_key
}

# 3. 安装常用工具
install_common_tools() {
    echo -e "${GREEN}正在安装常用工具...${NC}"
    local packages="wget curl sudo unzip git htop net-tools socat gnupg ca-certificates lsb-release"
    DEBIAN_FRONTEND=noninteractive apt-get install -y $packages
    echo -e "${GREEN}常用工具安装完成：${NC}"
    echo "$packages"
    press_any_key
}

# 4. 开启 BBR
enable_bbr() {
    echo -e "${GREEN}正在启用 BBR...${NC}"
    # 检查BBR是否已存在，避免重复添加
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    
    # 应用更改
    sysctl -p
    
    # 检查结果
    echo -e "${YELLOW}BBR 状态检查:${NC}"
    local bbr_status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ "$bbr_status" == "bbr" ]]; then
        echo -e "${GREEN}TCP BBR 已成功启用。${NC}"
    else
        echo -e "${RED}TCP BBR 启用失败。当前拥塞控制算法为: $bbr_status${NC}"
    fi
    
    local lsmod_bbr=$(lsmod | grep bbr)
    if [ -n "$lsmod_bbr" ]; then
        echo -e "${GREEN}BBR 内核模块已加载:${NC}"
        echo "$lsmod_bbr"
    else
        echo -e "${RED}BBR 内核模块未加载。请检查您的内核版本是否高于 4.9。${NC}"
    fi
    press_any_key
}

# 5. 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker 似乎已经安装。${NC}"
        docker --version
        press_any_key
        return
    fi

    echo -e "${GREEN}正在安装 Docker...${NC}"
    # 卸载旧版本
    apt-get remove docker docker-engine docker.io containerd runc -y

    # 设置 Docker 的官方 GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # 设置仓库
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 更新并安装
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # 检查是否安装成功
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker 安装成功！${NC}"
        docker --version
        systemctl status docker --no-pager
    else
        echo -e "${RED}Docker 安装失败。请检查错误信息。${NC}"
    fi
    press_any_key
}

# 6. VPS 测速
run_speedtest() {
    echo -e "${GREEN}正在下载并运行 bench.sh 脚本...${NC}"
    wget -qO- bench.sh | bash
    echo -e "${GREEN}测速完成。${NC}"
    press_any_key
}

# 7. 管理 IPv6
manage_ipv6() {
    # 检查IPv6状态
    check_ipv6_status() {
        local status=$(sysctl -n net.ipv6.conf.all.disable_ipv6)
        if [ "$status" -eq 0 ]; then
            echo -e "IPv6 状态: ${GREEN}已启用${NC}"
        else
            echo -e "IPv6 状态: ${RED}已禁用${NC}"
        fi
    }

    # 禁用IPv6
    disable_ipv6() {
        echo -e "${YELLOW}正在禁用 IPv6...${NC}"
        # 使用 sed 来修改或添加配置，比直接追加更安全
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
        
        echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
        echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
        echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${GREEN}IPv6 已禁用, 重启后永久生效。${NC}"
    }

    # 启用IPv6
    enable_ipv6() {
        echo -e "${YELLOW}正在启用 IPv6...${NC}"
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf

        echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf
        echo "net.ipv6.conf.default.disable_ipv6 = 0" >> /etc/sysctl.conf
        echo "net.ipv6.conf.lo.disable_ipv6 = 0" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${GREEN}IPv6 已启用, 重启后永久生效。${NC}"
    }

    clear
    echo "--- IPv6 管理菜单 ---"
    check_ipv6_status
    echo "---------------------"
    echo "1. 禁用 IPv6"
    echo "2. 启用 IPv6"
    echo "0. 返回主菜单"
    read -p "请输入选项 [0-2]: " ipv6_choice

    case $ipv6_choice in
        1) disable_ipv6 ;;
        2) enable_ipv6 ;;
        0) return ;;
        *) echo -e "${RED}无效的选项。${NC}" ;;
    esac
    press_any_key
}

# 8. 修改 SSH 端口
change_ssh_port() {
    local ssh_config_file="/etc/ssh/sshd_config"
    local current_port=$(grep -i "^port" "$ssh_config_file" | awk '{print $2}' | head -n1)
    if [ -z "$current_port" ]; then
        current_port="22"
    fi
    
    echo -e "${YELLOW}当前 SSH 端口为: $current_port${NC}"
    read -p "请输入新的 SSH 端口 (1-65535): " new_port

    # 验证输入
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "${RED}错误：无效的端口号。${NC}"
        press_any_key
        return
    fi

    echo -e "${YELLOW}警告：修改 SSH 端口是一项危险操作。${NC}"
    echo -e "${YELLOW}在继续之前，请确保您的防火墙（如UFW、云服务商安全组）已放行新端口 $new_port/tcp。${NC}"
    read -p "您确定要将 SSH 端口更改为 $new_port 吗？(y/n): " confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # 备份配置文件
        cp "$ssh_config_file" "$ssh_config_file.bak.$(date +%F_%T)"
        echo -e "${GREEN}已备份配置文件到 $ssh_config_file.bak...${NC}"

        # 修改端口
        sed -i "s/^#\?Port .*/Port $new_port/" "$ssh_config_file"
        
        # 检查是否修改成功
        if grep -q "^Port $new_port" "$ssh_config_file"; then
            echo -e "${GREEN}SSH 配置文件修改成功。${NC}"
            
            # 提示在防火墙中允许新端口
            if command -v ufw &> /dev/null && [[ $(ufw status | grep -c "inactive") -eq 0 ]]; then
                echo -e "${YELLOW}检测到 UFW 正在运行，将自动为您添加入站规则...${NC}"
                ufw allow $new_port/tcp
                ufw status
            else
                echo -e "${RED}警告：UFW 未运行或未安装。请手动配置您的防火墙以允许端口 $new_port！${NC}"
            fi

            echo -e "${YELLOW}正在重启 SSH 服务...${NC}"
            systemctl restart sshd
            
            # 检查 SSH 服务状态
            if systemctl is-active --quiet sshd; then
                echo -e "${GREEN}SSH 服务已成功重启。请使用新端口 $new_port 重新连接！${NC}"
            else
                echo -e "${RED}错误：SSH 服务重启失败！请检查配置文件 /etc/ssh/sshd_config 或系统日志。${NC}"
            fi

        else
            echo -e "${RED}错误：修改 SSH 配置文件失败。${NC}"
        fi
    else
        echo -e "${YELLOW}操作已取消。${NC}"
    fi
    press_any_key
}

# 9. 管理防火墙 (UFW)
manage_firewall() {
    # 检查是否已安装 UFW
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}UFW 未安装。正在为您安装...${NC}"
        apt-get update
        apt-get install -y ufw
        echo -e "${GREEN}UFW 安装完成。${NC}"
    fi
    
    clear
    echo "--- UFW 防火墙管理 ---"
    ufw status verbose
    echo "--------------------------"
    echo "1. 启用防火墙 (将默认拒绝所有入站，放行出站)"
    echo "2. 关闭防火墙"
    echo "3. 查看状态"
    echo "4. 添加规则 (例如: allow 80/tcp)"
    echo "0. 返回主菜单"
    read -p "请输入选项 [0-4]: " firewall_choice

    case $firewall_choice in
        1) 
            # 默认放行SSH端口
            local current_port=$(grep -i "^port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
            [ -z "$current_port" ] && current_port="22"
            echo -e "${YELLOW}为防止失联，将自动放行当前SSH端口: $current_port ${NC}"
            ufw allow $current_port/tcp
            yes | ufw enable
            echo -e "${GREEN}防火墙已启用。${NC}"
            ufw status
            ;;
        2) 
            ufw disable
            echo -e "${GREEN}防火墙已关闭。${NC}"
            ;;
        3) 
            ufw status verbose 
            ;;
        4)
            read -p "请输入规则 (例如 'allow 80/tcp' 或 'delete allow 80'): " rule
            if [ -n "$rule" ]; then
                ufw $rule
                echo -e "${GREEN}规则已执行。${NC}"
                ufw status
            else
                echo -e "${RED}输入为空，操作取消。${NC}"
            fi
            ;;
        0) return ;;
        *) echo -e "${RED}无效的选项。${NC}" ;;
    esac
    press_any_key
}


# --- Main Menu Function ---
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}=======================================================${NC}"
        echo -e "${GREEN}             VPS All-in-One 管理脚本                  ${NC}"
        echo -e "${GREEN}       适用于 Debian 10+ / Ubuntu 20.04+             ${NC}"
        echo -e "${GREEN}=======================================================${NC}"
        echo -e " ${YELLOW}1. 设置 Root 用户密码${NC}"
        echo -e " ${YELLOW}2. 更新系统与软件包${NC}"
        echo -e " ${YELLOW}3. 安装常用工具 (wget, curl, htop等)${NC}"
        echo -e " ${YELLOW}4. 启用 TCP BBR 加速${NC}"
        echo -e " ${YELLOW}5. 安装 Docker 和 Docker Compose${NC}"
        echo -e " ${YELLOW}6. 服务器性能和网络测速${NC}"
        echo -e " ${YELLOW}7. 管理 IPv6 (检测/启用/禁用)${NC}"
        echo -e " ${YELLOW}8. 修改默认 SSH 端口${NC}"
        echo -e " ${YELLOW}9. 管理 UFW 防火墙${NC}"
        echo -e " ${RED}0. 退出脚本${NC}"
        echo -e "-------------------------------------------------------"
        read -p "请输入选项 [0-9]: " choice

        case $choice in
            1) enable_root_login ;;
            2) update_system ;;
            3) install_common_tools ;;
            4) enable_bbr ;;
            5) install_docker ;;
            6) run_speedtest ;;
            7) manage_ipv6 ;;
            8) change_ssh_port ;;
            9) manage_firewall ;;
            0) break ;;
            *) echo -e "${RED}无效的选项，请重新输入。${NC}" && sleep 2 ;;
        esac
    done
}

# --- Script Entry Point ---
check_root
main_menu
echo -e "${GREEN}感谢使用！${NC}"
