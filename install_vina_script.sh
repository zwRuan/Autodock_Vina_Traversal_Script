#!/bin/bash

# 修正的AutoDock Vina安装脚本
# 使用正确的下载链接和方法

set -e

echo "=========================================="
echo "修正的AutoDock Vina安装脚本"
echo "=========================================="

INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# 方法2：从正确的GitHub release下载
download_vina_binary() {
    echo "从GitHub下载AutoDock Vina..."
    
    # 使用正确的release URL
    local base_url="https://github.com/ccsb-scripps/AutoDock-Vina/releases/download/v1.2.5"
    local filename="vina_1.2.5_linux_x86_64"
    local download_url="$base_url/$filename"
    
    echo "下载地址: $download_url"
    
    if command -v wget &> /dev/null; then
        if wget -O "$INSTALL_DIR/vina" "$download_url"; then
            chmod +x "$INSTALL_DIR/vina"
            echo "✅ wget下载成功"
            return 0
        fi
    fi
    
    if command -v curl &> /dev/null; then
        if curl -L -o "$INSTALL_DIR/vina" "$download_url"; then
            chmod +x "$INSTALL_DIR/vina"
            echo "✅ curl下载成功"
            return 0
        fi
    fi
    
    echo "❌ 下载失败"
    return 1
}


# 测试vina安装
test_vina() {
    local vina_path="$1"
    
    echo "测试vina: $vina_path"
    
    if [[ ! -f "$vina_path" ]]; then
        echo "❌ 文件不存在"
        return 1
    fi
    
    if [[ ! -x "$vina_path" ]]; then
        echo "❌ 文件不可执行"
        return 1
    fi
    
    # 测试基本功能
    if "$vina_path" --help &> /dev/null; then
        echo "✅ vina功能正常"
        echo "版本信息:"
        "$vina_path" --version 2>&1 || echo "无版本信息"
        return 0
    else
        echo "❌ vina无法运行"
        return 1
    fi
}

# 主安装流程
main() {
    echo "开始安装AutoDock Vina..."
    
    # 添加PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> ~/.bashrc
        export PATH="$INSTALL_DIR:$PATH"
        echo "✓ 已添加到PATH"
    fi
    
    # 依次尝试不同方法
    local methods=(
        "download_vina_binary" 
    )
    
    for method in "${methods[@]}"; do
        echo ""
        echo "尝试方法: $method"
        
        if $method; then
            if test_vina "$INSTALL_DIR/vina"; then
                echo ""
                echo "=========================================="
                echo "✅ AutoDock Vina安装成功！"
                echo "=========================================="
                echo "安装位置: $INSTALL_DIR/vina"
                echo "请运行以下命令重新加载环境:"
                echo "  source ~/.bashrc"
                echo ""
                echo "然后测试:"
                echo "  vina --version"
                return 0
            fi
        fi
        
        echo "❌ 方法 $method 失败"
    done
}

# 运行主函数
main "$@"