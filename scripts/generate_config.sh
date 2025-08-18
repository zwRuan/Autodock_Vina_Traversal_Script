#!/bin/bash

# 简化的盲对接配置生成脚本
# 生成完全包裹蛋白质的盲对接配置文件

set -e

# 默认参数
OUTPUT_FILE=""
VERBOSE=false

# 显示帮助信息
show_help() {
    cat << EOF
用法: $0 <protein.pdb> <ligand.pdb> [选项]

生成盲对接配置文件 - 盒子完全包裹蛋白质

参数:
  protein.pdb     蛋白质PDB文件
  ligand.pdb      配体PDB文件

选项:
  -o, --output    输出配置文件路径
  -v, --verbose   详细输出
  -h, --help      显示帮助信息

示例:
  $0 egfr.pdb Afatinib.pdb -o config.txt
EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$PROTEIN_PDB" ]]; then
                    PROTEIN_PDB="$1"
                elif [[ -z "$LIGAND_PDB" ]]; then
                    LIGAND_PDB="$1"
                else
                    echo "过多参数: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 检查必需参数
    if [[ -z "$PROTEIN_PDB" ]] || [[ -z "$LIGAND_PDB" ]]; then
        echo "错误: 缺少蛋白质或配体文件参数"
        show_help
        exit 1
    fi
}

# 日志函数
log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[LOG] $*"
    fi
}

# 分析蛋白质文件 - 计算几何中心和包围盒
analyze_protein_for_blind_docking() {
    local pdb_file="$1"
    
    log "分析蛋白质文件: $pdb_file"
    
    python3 << EOF
import numpy as np
import sys

def analyze_protein_blind_docking(pdb_file):
    """
    分析蛋白质用于盲对接
    返回: 几何中心坐标 和 完全包围的盒子大小
    """
    coords = []
    
    try:
        with open(pdb_file, 'r') as f:
            for line in f:
                if line.startswith('ATOM'):
                    try:
                        x = float(line[30:38].strip())
                        y = float(line[38:46].strip())
                        z = float(line[46:54].strip())
                        coords.append([x, y, z])
                    except ValueError:
                        continue
    except Exception as e:
        print(f"ERROR: 无法读取文件 {pdb_file}: {e}", file=sys.stderr)
        return None
    
    if not coords:
        print("ERROR: 未找到有效的原子坐标", file=sys.stderr)
        return None
    
    coords = np.array(coords)
    
    # 计算几何中心 (用作盲对接的搜索中心)
    center = np.mean(coords, axis=0)
    
    # 计算蛋白质的边界
    min_coords = np.min(coords, axis=0)
    max_coords = np.max(coords, axis=0)
    dimensions = max_coords - min_coords
    
    # 盲对接盒子大小 = 蛋白质尺寸 + 足够的buffer确保完全包围
    # 根据AutoDock文档，通常需要15-20Å的buffer
    buffer = 20.0  # 20Å buffer确保完全包围
    box_size = dimensions + buffer
    
    return center, box_size, min_coords, max_coords, dimensions

# 执行分析
result = analyze_protein_blind_docking("$pdb_file")
if result:
    center, box_size, min_coords, max_coords, dimensions = result
    
    # 输出格式: center_x,center_y,center_z,size_x,size_y,size_z
    print(f"{center[0]:.3f},{center[1]:.3f},{center[2]:.3f},{box_size[0]:.1f},{box_size[1]:.1f},{box_size[2]:.1f}")
    
    # 输出调试信息到stderr
    print(f"蛋白质边界: ({min_coords[0]:.1f}, {min_coords[1]:.1f}, {min_coords[2]:.1f}) 到 ({max_coords[0]:.1f}, {max_coords[1]:.1f}, {max_coords[2]:.1f})", file=sys.stderr)
    print(f"蛋白质尺寸: {dimensions[0]:.1f} × {dimensions[1]:.1f} × {dimensions[2]:.1f} Å", file=sys.stderr)
    print(f"几何中心: ({center[0]:.3f}, {center[1]:.3f}, {center[2]:.3f})", file=sys.stderr)
    print(f"盲对接盒子: {box_size[0]:.1f} × {box_size[1]:.1f} × {box_size[2]:.1f} Å (含20Å buffer)", file=sys.stderr)
else:
    print("ERROR")
EOF
}

# 生成盲对接配置文件
generate_blind_docking_config() {
    local protein_pdb="$1"
    local ligand_pdb="$2"
    local output_file="$3"
    
    log "生成盲对接配置文件..."
    
    # 分析蛋白质
    echo "分析蛋白质用于盲对接..."
    local analysis_result=$(analyze_protein_for_blind_docking "$protein_pdb" 2>/dev/null)
    
    if [[ "$analysis_result" == "ERROR" ]] || [[ -z "$analysis_result" ]]; then
        echo "错误: 无法分析蛋白质文件 $protein_pdb"
        return 1
    fi
    
    # 解析分析结果
    IFS=',' read -r center_x center_y center_z size_x size_y size_z <<< "$analysis_result"
    
    # 验证数值
    for value in "$center_x" "$center_y" "$center_z" "$size_x" "$size_y" "$size_z"; do
        if ! [[ "$value" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
            echo "错误: 无效的数值参数: $value"
            return 1
        fi
    done
    
    # 生成文件名
    local protein_name=$(basename "$protein_pdb" .pdb)
    local ligand_name=$(basename "$ligand_pdb" .pdb)
    
    # 创建输出目录
    mkdir -p "$(dirname "$output_file")"
    
    # 生成配置文件
    cat > "$output_file" << EOF
# 盲对接配置文件
# 盒子完全包裹蛋白质，配体从盒子外部搜索结合位点
# 
# 蛋白质: $protein_name
# 配体: $ligand_name
# 生成时间: $(date)
# 
# 注意: 这是盲对接配置，搜索整个蛋白质表面的结合位点

receptor = ${protein_name}.pdbqt
ligand = ${ligand_name}.pdbqt
center_x = $center_x
center_y = $center_y
center_z = $center_z
size_x = $size_x
size_y = $size_y
size_z = $size_z
out = ${ligand_name}_out.pdbqt
cpu = 0
energy_range = 10
exhaustiveness = 24
num_modes = 1
EOF
    
    echo "✓ 盲对接配置文件已生成: $output_file"
    echo ""
    echo "盲对接参数摘要:"
    echo "  搜索中心: ($center_x, $center_y, $center_z)"
    echo "  搜索盒子: $size_x × $size_y × $size_z Å"
    
    # 修复计算搜索体积的Python语法错误
    local volume=$(python3 -c "print(f'{${size_x} * ${size_y} * ${size_z}:.0f}')")
    echo "  搜索体积: ${volume} Å³"
    echo "  详尽度: 24 (高精度搜索)"
    echo ""
    echo "📋 配置说明:"
    echo "  - 盒子完全包裹蛋白质 + 20Å buffer"
    echo "  - 搜索中心为蛋白质几何中心"
    echo "  - 适用于未知结合位点的盲对接"
    echo "  - 配体将从盒子外部搜索最佳结合位点"
    
    return 0
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"
    
    log "输入参数:"
    log "  蛋白质: $PROTEIN_PDB"
    log "  配体: $LIGAND_PDB"
    log "  输出: $OUTPUT_FILE"
    
    # 检查输入文件
    for file in "$PROTEIN_PDB" "$LIGAND_PDB"; do
        if [[ ! -f "$file" ]]; then
            echo "错误: 文件不存在: $file"
            exit 1
        fi
    done
    
    # 生成默认输出文件名
    if [[ -z "$OUTPUT_FILE" ]]; then
        local protein_name=$(basename "$PROTEIN_PDB" .pdb)
        local ligand_name=$(basename "$LIGAND_PDB" .pdb)
        OUTPUT_FILE="${protein_name}_${ligand_name}_blind.txt"
    fi
    
    echo "盲对接配置生成器"
    echo "蛋白质: $(basename "$PROTEIN_PDB")"
    echo "配体: $(basename "$LIGAND_PDB")"
    echo ""
    
    # 生成配置文件
    if generate_blind_docking_config "$PROTEIN_PDB" "$LIGAND_PDB" "$OUTPUT_FILE"; then
        echo ""
        echo "✅ 盲对接配置生成完成！"
        echo "配置文件: $OUTPUT_FILE"
        echo ""
        echo "下一步: 使用此配置文件执行Vina盲对接"
    else
        echo "❌ 配置文件生成失败"
        exit 1
    fi
}

# 运行主函数
main "$@"