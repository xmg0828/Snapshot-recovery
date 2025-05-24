#!/bin/bash

# 颜色设置
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检测操作系统类型
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        DATE_CMD="gdate"
        STAT_CMD="gstat"
        # 检查是否安装了GNU工具
        if ! command -v gdate &> /dev/null; then
            echo -e "${YELLOW}检测到macOS系统，正在检查GNU工具...${NC}"
            if ! command -v brew &> /dev/null; then
                echo -e "${RED}错误: 请先安装Homebrew，然后运行: brew install coreutils${NC}"
                exit 1
            fi
            echo -e "${YELLOW}正在安装GNU工具...${NC}"
            brew install coreutils
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS_TYPE="linux"
        DATE_CMD="date"
        STAT_CMD="stat"
    else
        echo -e "${RED}错误: 不支持的操作系统类型${NC}"
        exit 1
    fi
}

# 格式化文件大小（跨平台兼容）
format_size() {
    local bytes=$1
    if [ "$OS_TYPE" = "macos" ]; then
        # macOS使用不同的参数
        if command -v gnumfmt &> /dev/null; then
            gnumfmt --to=iec-i --suffix=B $bytes 2>/dev/null || echo "${bytes}B"
        else
            # 简单的大小格式化
            if [ $bytes -gt 1073741824 ]; then
                echo "$(( bytes / 1073741824 ))GB"
            elif [ $bytes -gt 1048576 ]; then
                echo "$(( bytes / 1048576 ))MB"
            elif [ $bytes -gt 1024 ]; then
                echo "$(( bytes / 1024 ))KB"
            else
                echo "${bytes}B"
            fi
        fi
    else
        numfmt --to=iec-i --suffix=B $bytes 2>/dev/null || echo "${bytes}B"
    fi
}

# 获取文件修改时间（跨平台兼容）
get_file_date() {
    local file_path="$1"
    if [ "$OS_TYPE" = "macos" ]; then
        $STAT_CMD -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file_path" 2>/dev/null || echo "未知日期"
    else
        $STAT_CMD -c "%y" "$file_path" 2>/dev/null | cut -d'.' -f1 || echo "未知日期"
    fi
}

# 获取文件大小（跨平台兼容）
get_file_size() {
    local file_path="$1"
    if [ "$OS_TYPE" = "macos" ]; then
        $STAT_CMD -f "%z" "$file_path" 2>/dev/null || echo "0"
    else
        $STAT_CMD -c "%s" "$file_path" 2>/dev/null || echo "0"
    fi
}

# 远程获取文件信息（跨平台兼容）
get_remote_file_info() {
    local ssh_cmd="$1"
    local file_path="$2"
    
    # 先检查远程系统类型
    local remote_os=$(eval "$ssh_cmd 'uname -s'" 2>/dev/null)
    
    if [[ "$remote_os" == "Darwin" ]]; then
        # 远程是macOS
        eval "$ssh_cmd 'stat -f \"%z %m\" \"$file_path\"'" 2>/dev/null
    else
        # 远程是Linux
        eval "$ssh_cmd 'stat -c \"%s %Y\" \"$file_path\"'" 2>/dev/null
    fi
}

clear
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}           系统快照恢复工具 v2.1                 ${NC}"
echo -e "${BLUE}           (支持 Linux & macOS)                 ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# 检测操作系统
detect_os
echo -e "${CYAN}检测到操作系统: ${GREEN}$OS_TYPE${NC}"
echo ""

# 选择恢复模式
echo -e "${CYAN}请选择恢复方式:${NC}"
echo -e "1) ${GREEN}本地恢复${NC} - 从本地/backups目录恢复快照"
echo -e "2) ${GREEN}远程恢复${NC} - 从远程服务器下载并恢复快照"
echo ""
read -p "请选择 [1-2]: " RESTORE_TYPE

if ! [[ "$RESTORE_TYPE" =~ ^[1-2]$ ]]; then
    echo -e "${RED}错误: 无效的选择!${NC}"
    exit 1
fi

# 本地恢复函数
local_restore() {
    echo -e "\n${BLUE}=== 本地恢复模式 ===${NC}"
    
    # 检查本地备份目录
    BACKUP_DIR="/backups"
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}错误: 备份目录 $BACKUP_DIR 不存在!${NC}"
        exit 1
    fi

    # 查找本地快照文件
    echo -e "${BLUE}正在查找本地系统快照...${NC}"
    
    # 跨平台兼容的find命令
    if [ "$OS_TYPE" = "macos" ]; then
        SNAPSHOT_FILES=($(find $BACKUP_DIR -maxdepth 1 -type f -name "system_snapshot_*.tar.gz" | sort -r))
    else
        SNAPSHOT_FILES=($(find $BACKUP_DIR -maxdepth 1 -type f -name "system_snapshot_*.tar.gz" | sort -r))
    fi

    if [ ${#SNAPSHOT_FILES[@]} -eq 0 ]; then
        echo -e "${RED}错误: 未找到系统快照文件!${NC}"
        exit 1
    fi

    # 显示可用快照列表
    echo -e "${YELLOW}可用的本地快照:${NC}"
    for i in "${!SNAPSHOT_FILES[@]}"; do
        SNAPSHOT_PATH="${SNAPSHOT_FILES[$i]}"
        SNAPSHOT_NAME=$(basename "$SNAPSHOT_PATH")
        
        # 获取文件大小和日期
        SNAPSHOT_SIZE_BYTES=$(get_file_size "$SNAPSHOT_PATH")
        SNAPSHOT_SIZE=$(format_size "$SNAPSHOT_SIZE_BYTES")
        SNAPSHOT_DATE=$(get_file_date "$SNAPSHOT_PATH")
        
        echo -e "$((i+1))) ${GREEN}$SNAPSHOT_NAME${NC} (${SNAPSHOT_SIZE}, ${SNAPSHOT_DATE})"
    done

    # 选择要恢复的快照
    read -p "请选择要恢复的快照编号 [1-${#SNAPSHOT_FILES[@]}]: " SNAPSHOT_CHOICE

    if ! [[ "$SNAPSHOT_CHOICE" =~ ^[0-9]+$ ]] || [ "$SNAPSHOT_CHOICE" -lt 1 ] || [ "$SNAPSHOT_CHOICE" -gt ${#SNAPSHOT_FILES[@]} ]; then
        echo -e "${RED}错误: 无效的选择!${NC}"
        exit 1
    fi

    SELECTED_SNAPSHOT="${SNAPSHOT_FILES[$((SNAPSHOT_CHOICE-1))]}"
    SNAPSHOT_NAME=$(basename "$SELECTED_SNAPSHOT")
    
    # 设置本地快照路径用于恢复
    LOCAL_SNAPSHOT="$SELECTED_SNAPSHOT"
    
    echo -e "\n${YELLOW}准备恢复本地系统快照: ${GREEN}$SNAPSHOT_NAME${NC}"
}

# 远程恢复函数
remote_restore() {
    echo -e "\n${BLUE}=== 远程恢复模式 ===${NC}"
    
    # 检查必要工具
    if ! command -v scp &> /dev/null; then
        echo -e "${RED}错误: 未找到 scp 命令${NC}"
        if [ "$OS_TYPE" = "macos" ]; then
            echo -e "${YELLOW}macOS用户请运行: xcode-select --install${NC}"
        else
            echo -e "${YELLOW}Linux用户请安装: apt-get install openssh-client${NC}"
        fi
        exit 1
    fi

    if ! command -v ssh &> /dev/null; then
        echo -e "${RED}错误: 未找到 ssh 命令${NC}"
        if [ "$OS_TYPE" = "macos" ]; then
            echo -e "${YELLOW}macOS用户请运行: xcode-select --install${NC}"
        else
            echo -e "${YELLOW}Linux用户请安装: apt-get install openssh-client${NC}"
        fi
        exit 1
    fi

    # 获取远程服务器信息
    echo -e "${BLUE}请输入远程服务器连接信息:${NC}"
    echo ""

    read -p "远程服务器IP地址或域名: " REMOTE_HOST
    if [ -z "$REMOTE_HOST" ]; then
        echo -e "${RED}错误: 必须输入远程服务器地址!${NC}"
        exit 1
    fi

    read -p "SSH端口 [默认: 22]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}

    read -p "用户名 [默认: root]: " SSH_USER
    SSH_USER=${SSH_USER:-root}

    echo -e "${YELLOW}请选择认证方式:${NC}"
    echo "1) 密码认证"
    echo "2) SSH密钥认证"
    read -p "请选择 [1-2]: " AUTH_METHOD

    if [ "$AUTH_METHOD" = "1" ]; then
        # 密码认证
        read -s -p "SSH密码: " SSH_PASS
        echo ""
        if [ -z "$SSH_PASS" ]; then
            echo -e "${RED}错误: 必须输入密码!${NC}"
            exit 1
        fi
        SSH_CMD="sshpass -p '$SSH_PASS' ssh -o StrictHostKeyChecking=no -p $SSH_PORT $SSH_USER@$REMOTE_HOST"
        SCP_CMD="sshpass -p '$SSH_PASS' scp -o StrictHostKeyChecking=no -P $SSH_PORT"
        
        # 检查sshpass是否安装
        if ! command -v sshpass &> /dev/null; then
            echo -e "${YELLOW}正在安装 sshpass...${NC}"
            if [ "$OS_TYPE" = "macos" ]; then
                if command -v brew &> /dev/null; then
                    brew install hudochenkov/sshpass/sshpass
                else
                    echo -e "${RED}错误: 请先安装Homebrew，然后运行: brew install hudochenkov/sshpass/sshpass${NC}"
                    exit 1
                fi
            else
                apt-get update && apt-get install -y sshpass
            fi
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误: 无法安装 sshpass${NC}"
                exit 1
            fi
        fi
    elif [ "$AUTH_METHOD" = "2" ]; then
        # 密钥认证
        read -p "SSH私钥文件路径 [默认: ~/.ssh/id_rsa]: " SSH_KEY
        SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
        
        # 展开波浪号
        SSH_KEY="${SSH_KEY/#\~/$HOME}"
        
        if [ ! -f "$SSH_KEY" ]; then
            echo -e "${RED}错误: SSH密钥文件不存在: $SSH_KEY${NC}"
            exit 1
        fi
        
        SSH_CMD="ssh -o StrictHostKeyChecking=no -i $SSH_KEY -p $SSH_PORT $SSH_USER@$REMOTE_HOST"
        SCP_CMD="scp -o StrictHostKeyChecking=no -i $SSH_KEY -P $SSH_PORT"
    else
        echo -e "${RED}错误: 无效的认证方式选择!${NC}"
        exit 1
    fi

    read -p "远程备份目录路径 [默认: /backups]: " REMOTE_BACKUP_DIR
    REMOTE_BACKUP_DIR=${REMOTE_BACKUP_DIR:-/backups}

    # 测试远程连接
    echo -e "\n${BLUE}测试远程连接...${NC}"
    if ! eval "$SSH_CMD 'echo 连接成功'" &>/dev/null; then
        echo -e "${RED}错误: 无法连接到远程服务器!${NC}"
        echo -e "${RED}请检查IP地址、端口、用户名和密码/密钥是否正确${NC}"
        exit 1
    fi
    echo -e "${GREEN}远程连接测试成功!${NC}"

    # 查找远程快照文件
    echo -e "\n${BLUE}正在查找远程系统快照...${NC}"
    SNAPSHOT_LIST=$(eval "$SSH_CMD 'find $REMOTE_BACKUP_DIR -maxdepth 1 -type f -name \"system_snapshot_*.tar.gz\" | sort -r'")

    if [ -z "$SNAPSHOT_LIST" ]; then
        echo -e "${RED}错误: 在远程服务器上未找到系统快照文件!${NC}"
        echo -e "${RED}路径: $REMOTE_HOST:$REMOTE_BACKUP_DIR${NC}"
        exit 1
    fi

    # 将快照列表转换为数组
    IFS=$'\n' read -rd '' -a SNAPSHOT_FILES <<< "$SNAPSHOT_LIST"

    # 显示可用快照列表
    echo -e "${YELLOW}远程服务器上可用的快照:${NC}"
    for i in "${!SNAPSHOT_FILES[@]}"; do
        SNAPSHOT_PATH="${SNAPSHOT_FILES[$i]}"
        SNAPSHOT_NAME=$(basename "$SNAPSHOT_PATH")
        
        # 获取文件大小和日期（跨平台兼容）
        SNAPSHOT_INFO=$(get_remote_file_info "$SSH_CMD" "$SNAPSHOT_PATH")
        if [ -n "$SNAPSHOT_INFO" ]; then
            SNAPSHOT_SIZE_BYTES=$(echo "$SNAPSHOT_INFO" | cut -d' ' -f1)
            SNAPSHOT_TIMESTAMP=$(echo "$SNAPSHOT_INFO" | cut -d' ' -f2)
            
            # 格式化大小
            SNAPSHOT_SIZE=$(format_size "$SNAPSHOT_SIZE_BYTES")
            # 格式化日期
            if [ "$OS_TYPE" = "macos" ]; then
                SNAPSHOT_DATE=$($DATE_CMD -r "$SNAPSHOT_TIMESTAMP" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知日期")
            else
                SNAPSHOT_DATE=$($DATE_CMD -d "@$SNAPSHOT_TIMESTAMP" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知日期")
            fi
        else
            SNAPSHOT_SIZE="未知大小"
            SNAPSHOT_DATE="未知日期"
        fi
        
        echo -e "$((i+1))) ${GREEN}$SNAPSHOT_NAME${NC} (${SNAPSHOT_SIZE}, ${SNAPSHOT_DATE})"
    done

    # 选择要恢复的快照
    read -p "请选择要下载并恢复的快照编号 [1-${#SNAPSHOT_FILES[@]}]: " SNAPSHOT_CHOICE

    if ! [[ "$SNAPSHOT_CHOICE" =~ ^[0-9]+$ ]] || [ "$SNAPSHOT_CHOICE" -lt 1 ] || [ "$SNAPSHOT_CHOICE" -gt ${#SNAPSHOT_FILES[@]} ]; then
        echo -e "${RED}错误: 无效的选择!${NC}"
        exit 1
    fi

    SELECTED_SNAPSHOT="${SNAPSHOT_FILES[$((SNAPSHOT_CHOICE-1))]}"
    SNAPSHOT_NAME=$(basename "$SELECTED_SNAPSHOT")

    echo -e "\n${YELLOW}准备从远程服务器下载并恢复系统快照: ${GREEN}$SNAPSHOT_NAME${NC}"
    echo -e "${YELLOW}远程服务器: ${GREEN}$SSH_USER@$REMOTE_HOST:$SSH_PORT${NC}"

    # 创建本地临时目录
    LOCAL_TEMP_DIR="/tmp/remote_restore_$$"
    mkdir -p "$LOCAL_TEMP_DIR"

    # 下载快照文件
    echo -e "\n${BLUE}正在从远程服务器下载快照文件...${NC}"
    echo -e "${YELLOW}这可能需要一些时间，请耐心等待...${NC}"

    LOCAL_SNAPSHOT="$LOCAL_TEMP_DIR/$SNAPSHOT_NAME"
    if ! eval "$SCP_CMD $SSH_USER@$REMOTE_HOST:\"$SELECTED_SNAPSHOT\" \"$LOCAL_SNAPSHOT\""; then
        echo -e "${RED}错误: 下载快照文件失败!${NC}"
        rm -rf "$LOCAL_TEMP_DIR"
        exit 1
    fi

    echo -e "${GREEN}快照文件下载完成!${NC}"

    # 验证下载的文件
    if [ ! -f "$LOCAL_SNAPSHOT" ]; then
        echo -e "${RED}错误: 下载的快照文件不存在!${NC}"
        rm -rf "$LOCAL_TEMP_DIR"
        exit 1
    fi
}

# 系统恢复函数
perform_restore() {
    # 确认恢复
    echo -e "\n${RED}警告: 恢复操作将把系统状态恢复到快照创建时的状态。此操作不可撤销!${NC}"
    echo -e "${RED}恢复后，快照创建时间点之后的所有更改将丢失!${NC}"
    read -p "是否继续? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}恢复已取消.${NC}"
        # 清理远程下载的临时文件
        if [ "$RESTORE_TYPE" -eq 2 ] && [ -n "$LOCAL_TEMP_DIR" ]; then
            rm -rf "$LOCAL_TEMP_DIR"
        fi
        exit 0
    fi

    # 恢复模式选择
    echo -e "\n${YELLOW}请选择恢复模式:${NC}"
    if [ "$OS_TYPE" = "linux" ]; then
        echo -e "1) ${GREEN}标准恢复${NC} - 恢复所有系统文件，但保留当前网络配置"
        echo -e "2) ${GREEN}完全恢复${NC} - 完全恢复所有文件，包括网络配置（可能导致网络中断）"
        read -p "请选择恢复模式 [1-2]: " RESTORE_MODE
    else
        echo -e "1) ${GREEN}标准恢复${NC} - 恢复用户文件和应用程序配置"
        echo -e "2) ${GREEN}完全恢复${NC} - 恢复所有文件（不包括系统核心文件）"
        read -p "请选择恢复模式 [1-2]: " RESTORE_MODE
    fi

    if ! [[ "$RESTORE_MODE" =~ ^[1-2]$ ]]; then
        echo -e "${RED}错误: 无效的选择!${NC}"
        # 清理远程下载的临时文件
        if [ "$RESTORE_TYPE" -eq 2 ] && [ -n "$LOCAL_TEMP_DIR" ]; then
            rm -rf "$LOCAL_TEMP_DIR"
        fi
        exit 1
    fi

    # 备份关键系统配置
    if [ "$RESTORE_MODE" -eq 1 ]; then
        echo -e "\n${BLUE}备份当前系统配置...${NC}"
        if [ "$RESTORE_TYPE" -eq 2 ]; then
            BACKUP_CONFIG_DIR="$LOCAL_TEMP_DIR/current_config"
        else
            BACKUP_CONFIG_DIR="/tmp/system_backup_$$"
        fi
        mkdir -p "$BACKUP_CONFIG_DIR"
        
        if [ "$OS_TYPE" = "linux" ]; then
            cp /etc/fstab "$BACKUP_CONFIG_DIR/fstab.bak" 2>/dev/null
            cp /etc/network/interfaces "$BACKUP_CONFIG_DIR/interfaces.bak" 2>/dev/null
            cp -r /etc/netplan "$BACKUP_CONFIG_DIR/" 2>/dev/null
            cp /etc/hostname "$BACKUP_CONFIG_DIR/hostname.bak" 2>/dev/null
            cp /etc/hosts "$BACKUP_CONFIG_DIR/hosts.bak" 2>/dev/null
            cp /etc/resolv.conf "$BACKUP_CONFIG_DIR/resolv.conf.bak" 2>/dev/null
        else
            # macOS系统配置备份
            cp /etc/hosts "$BACKUP_CONFIG_DIR/hosts.bak" 2>/dev/null
            cp /etc/resolv.conf "$BACKUP_CONFIG_DIR/resolv.conf.bak" 2>/dev/null
        fi
    fi

    # 停止关键服务（仅Linux）
    if [ "$OS_TYPE" = "linux" ]; then
        echo -e "${BLUE}停止关键服务...${NC}"
        for service in nginx apache2 mysql docker; do
            if command -v systemctl &> /dev/null && systemctl is-active --quiet $service 2>/dev/null; then
                echo "停止 $service 服务..."
                systemctl stop $service 2>/dev/null
            fi
        done
    fi

    # 执行恢复
    echo -e "${BLUE}正在恢复系统文件...${NC}"

    if [ "$OS_TYPE" = "linux" ]; then
        # Linux系统恢复
        if [ "$RESTORE_MODE" -eq 1 ]; then
            # 标准恢复 - 保留网络设置
            tar -xzf "$LOCAL_SNAPSHOT" -C / \
                --exclude="dev/*" \
                --exclude="proc/*" \
                --exclude="sys/*" \
                --exclude="run/*" \
                --exclude="tmp/*" \
                --exclude="etc/fstab" \
                --exclude="etc/hostname" \
                --exclude="etc/hosts" \
                --exclude="etc/network/*" \
                --exclude="etc/netplan/*" \
                --exclude="etc/resolv.conf" \
                --exclude="backups/*"
        else
            # 完全恢复 - 包括网络设置
            tar -xzf "$LOCAL_SNAPSHOT" -C / \
                --exclude="dev/*" \
                --exclude="proc/*" \
                --exclude="sys/*" \
                --exclude="run/*" \
                --exclude="tmp/*" \
                --exclude="backups/*"
        fi
    else
        # macOS系统恢复（更加谨慎）
        if [ "$RESTORE_MODE" -eq 1 ]; then
            # 标准恢复 - 主要恢复用户文件
            tar -xzf "$LOCAL_SNAPSHOT" -C / \
                --exclude="System/*" \
                --exclude="dev/*" \
                --exclude="private/var/vm/*" \
                --exclude="private/var/tmp/*" \
                --exclude="tmp/*" \
                --exclude="etc/hosts" \
                --exclude="etc/resolv.conf" \
                --exclude="backups/*"
        else
            # 完全恢复 - 包括更多系统文件，但排除核心系统
            tar -xzf "$LOCAL_SNAPSHOT" -C / \
                --exclude="System/*" \
                --exclude="dev/*" \
                --exclude="private/var/vm/*" \
                --exclude="private/var/tmp/*" \
                --exclude="tmp/*" \
                --exclude="backups/*"
        fi
    fi

    RESTORE_RESULT=$?
    if [ $RESTORE_RESULT -ne 0 ]; then
        echo -e "${RED}错误: 系统恢复失败!${NC}"
        # 清理远程下载的临时文件
        if [ "$RESTORE_TYPE" -eq 2 ] && [ -n "$LOCAL_TEMP_DIR" ]; then
            rm -rf "$LOCAL_TEMP_DIR"
        fi
        exit 1
    fi

    # 恢复系统配置(标准模式)
    if [ "$RESTORE_MODE" -eq 1 ]; then
        echo -e "${BLUE}恢复当前系统配置...${NC}"
        if [ "$RESTORE_TYPE" -eq 2 ]; then
            BACKUP_CONFIG_DIR="$LOCAL_TEMP_DIR/current_config"
        else
            BACKUP_CONFIG_DIR="/tmp/system_backup_$$"
        fi
        
        if [ "$OS_TYPE" = "linux" ]; then
            cp "$BACKUP_CONFIG_DIR/fstab.bak" /etc/fstab 2>/dev/null
            cp "$BACKUP_CONFIG_DIR/interfaces.bak" /etc/network/interfaces 2>/dev/null
            cp -r "$BACKUP_CONFIG_DIR/netplan"/* /etc/netplan/ 2>/dev/null
            cp "$BACKUP_CONFIG_DIR/hostname.bak" /etc/hostname 2>/dev/null
            cp "$BACKUP_CONFIG_DIR/hosts.bak" /etc/hosts 2>/dev/null
            cp "$BACKUP_CONFIG_DIR/resolv.conf.bak" /etc/resolv.conf 2>/dev/null
        else
            cp "$BACKUP_CONFIG_DIR/hosts.bak" /etc/hosts 2>/dev/null
            cp "$BACKUP_CONFIG_DIR/resolv.conf.bak" /etc/resolv.conf 2>/dev/null
        fi
        
        # 清理临时配置备份
        if [ "$RESTORE_TYPE" -ne 2 ]; then
            rm -rf "$BACKUP_CONFIG_DIR"
        fi
    fi

    # 清理临时文件
    if [ "$RESTORE_TYPE" -eq 2 ] && [ -n "$LOCAL_TEMP_DIR" ]; then
        echo -e "${BLUE}清理临时文件...${NC}"
        rm -rf "$LOCAL_TEMP_DIR"
    fi

    # 通知成功
    echo -e "\n${GREEN}系统快照恢复成功!${NC}"
    if [ "$RESTORE_TYPE" -eq 1 ]; then
        echo -e "${GREEN}快照来源: 本地文件 - $SELECTED_SNAPSHOT${NC}"
    else
        echo -e "${GREEN}快照来源: 远程服务器 - $SSH_USER@$REMOTE_HOST:$SELECTED_SNAPSHOT${NC}"
    fi
    
    if [ "$RESTORE_MODE" -eq 1 ]; then
        if [ "$OS_TYPE" = "linux" ]; then
            echo -e "${BLUE}已保留当前网络配置.${NC}"
        else
            echo -e "${BLUE}已保留当前系统配置.${NC}"
        fi
    else
        echo -e "${YELLOW}已恢复所有设置.${NC}"
    fi

    # 提示重启
    echo -e "\n${YELLOW}建议重启系统以完成恢复.${NC}"
    read -p "是否立即重启系统? [y/N]: " REBOOT
    if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}系统将在5秒后重启...${NC}"
        sleep 5
        if [ "$OS_TYPE" = "linux" ]; then
            reboot
        else
            sudo reboot
        fi
    else
        echo -e "${YELLOW}请手动重启系统以完成恢复.${NC}"
    fi
}

# 主程序流程
if [ "$RESTORE_TYPE" -eq 1 ]; then
    local_restore
else
    remote_restore
fi

perform_restore
