#!/bin/bash

# 通用Vina盲对接脚本
# 接受参数控制的Vina分子对接

set -e

# 显示帮助信息
show_help() {
    cat << EOF
用法: $0 <protein.pdb> <ligand.pdb> <config.txt> <work_dir>

通用Vina盲对接脚本

参数:
  protein.pdb     蛋白质PDB文件
  ligand.pdb      配体PDB文件  
  config.txt      配置文件
  work_dir        工作目录（结果输出目录）

示例:
  $0 egfr.pdb Afatinib.pdb config.txt results/egfr_Afatinib/
EOF
}

# 解析参数
if [[ $# -ne 4 ]]; then
    echo "错误: 参数数量不正确"
    show_help
    exit 1
fi

RECEPTOR_PDB="$1"
LIGAND_PDB="$2"
CONFIG_FILE="$3"
WORK_DIR="$4"

# 检查参数
for file in "$RECEPTOR_PDB" "$LIGAND_PDB" "$CONFIG_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo "错误: 文件不存在: $file"
        exit 1
    fi
done

echo "=========================================="
echo "Vina盲对接执行器"
echo "=========================================="
echo "蛋白质: $(basename "$RECEPTOR_PDB")"
echo "配体: $(basename "$LIGAND_PDB")"
echo "配置: $(basename "$CONFIG_FILE")"
echo "工作目录: $WORK_DIR"
echo ""

# 生成文件名
PROTEIN_NAME=$(basename "$RECEPTOR_PDB" .pdb)
LIGAND_NAME=$(basename "$LIGAND_PDB" .pdb)
RECEPTOR_PDBQT="$WORK_DIR/${PROTEIN_NAME}.pdbqt"
LIGAND_PDBQT="$WORK_DIR/${LIGAND_NAME}.pdbqt"
OUTPUT_PDBQT="$WORK_DIR/${LIGAND_NAME}_out.pdbqt"

# 创建工作目录
mkdir -p "$WORK_DIR"

# 设置环境变量
export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:${LD_LIBRARY_PATH}
export PATH="$HOME/.local/bin:$PATH"

# 激活conda环境
if command -v conda &> /dev/null; then
    eval "$(conda shell.bash hook)" 2>/dev/null || true
    conda activate meeko311 2>/dev/null || echo "继续使用当前环境"
fi

echo "检查输入文件..."
for file in "$RECEPTOR_PDB" "$LIGAND_PDB" "$CONFIG_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo "错误: 文件 $file 不存在!"
        exit 1
    fi
done
echo "✓ 输入文件检查通过"

# 创建输出目录
mkdir -p "$WORK_DIR/logs"

# 步骤1: 转换PDB到PDBQT
echo ""
echo "步骤1: 转换文件格式..."

if [[ ! -f "$RECEPTOR_PDBQT" ]] || [[ "$RECEPTOR_PDB" -nt "$RECEPTOR_PDBQT" ]]; then
    echo "转换受体: $RECEPTOR_PDB -> $RECEPTOR_PDBQT"
    prepare_receptor4 -r "$RECEPTOR_PDB" -o "$RECEPTOR_PDBQT" -A checkhydrogens -U nphs_lps_waters_nonstdres 2>/dev/null || \
    prepare_receptor4 -r "$RECEPTOR_PDB" -o "$RECEPTOR_PDBQT" -A None -U None 2>/dev/null || \
    prepare_receptor4 -r "$RECEPTOR_PDB" -o "$RECEPTOR_PDBQT"
    echo "✓ 受体转换完成"
fi

if [[ ! -f "$LIGAND_PDBQT" ]] || [[ "$LIGAND_PDB" -nt "$LIGAND_PDBQT" ]]; then
    echo "转换配体: $LIGAND_PDB -> $LIGAND_PDBQT"
    prepare_ligand4 -l "$LIGAND_PDB" -o "$LIGAND_PDBQT" -A bonds_hydrogens 2>/dev/null || \
    prepare_ligand4 -l "$LIGAND_PDB" -o "$LIGAND_PDBQT"
    echo "✓ 配体转换完成"
fi

# 步骤2: 读取配置参数
echo ""
echo "步骤2: 读取配置参数..."
CENTER_X=$(grep -E "^\s*center_x\s*=" "$CONFIG_FILE" | sed 's/.*=\s*//' | sed 's/\s*$//' || echo "0.0")
CENTER_Y=$(grep -E "^\s*center_y\s*=" "$CONFIG_FILE" | sed 's/.*=\s*//' | sed 's/\s*$//' || echo "0.0")
CENTER_Z=$(grep -E "^\s*center_z\s*=" "$CONFIG_FILE" | sed 's/.*=\s*//' | sed 's/\s*$//' || echo "0.0")
SIZE_X=$(grep -E "^\s*size_x\s*=" "$CONFIG_FILE" | sed 's/.*=\s*//' | sed 's/\s*$//' || echo "126.0")
SIZE_Y=$(grep -E "^\s*size_y\s*=" "$CONFIG_FILE" | sed 's/.*=\s*//' | sed 's/\s*$//' || echo "124.0")
SIZE_Z=$(grep -E "^\s*size_z\s*=" "$CONFIG_FILE" | sed 's/.*=\s*//' | sed 's/\s*$//' || echo "126.0")
EXHAUSTIVENESS=$(grep -E "^\s*exhaustiveness\s*=" "$CONFIG_FILE" | sed 's/.*=\s*//' | sed 's/\s*$//' || echo "24")
NUM_MODES=$(grep -E "^\s*num_modes\s*=" "$CONFIG_FILE" | sed 's/.*=\s*//' | sed 's/\s*$//' || echo "1")

echo "盲对接参数:"
echo "  中心坐标: (${CENTER_X}, ${CENTER_Y}, ${CENTER_Z})"
echo "  盒子大小: ${SIZE_X} × ${SIZE_Y} × ${SIZE_Z} Å"
echo "  详尽度: ${EXHAUSTIVENESS}"
echo "  模式数: ${NUM_MODES}"
echo ""
echo "🎯 这是真正的盲对接 - 搜索整个蛋白质表面！"

# 步骤3: 检查Vina
echo ""
echo "步骤3: 检查AutoDock Vina..."

# 查找Vina
VINA_PATHS=(
    "$(which vina 2>/dev/null)"
    "$HOME/.local/bin/vina"
    "/usr/local/bin/vina"
)

VINA_PATH=""
for path in "${VINA_PATHS[@]}"; do
    if [[ -n "$path" ]] && [[ -f "$path" ]] && [[ -x "$path" ]]; then
        if "$path" --help &> /dev/null; then
            VINA_PATH="$path"
            break
        fi
    fi
done

if [[ -z "$VINA_PATH" ]]; then
    echo "❌ 未找到AutoDock Vina"
    echo "请确保Vina已正确安装:"
    echo "  conda install -c conda-forge vina"
    exit 1
fi

echo "✓ 找到AutoDock Vina: $VINA_PATH"

# 显示Vina版本
echo "Vina版本信息:"
$VINA_PATH --version || echo "  版本信息获取失败"

# 步骤4: 运行Vina盲对接
echo ""
echo "步骤4: 运行Vina盲对接..."
echo "=========================================="

# 计算预估时间
total_volume=$(echo "${SIZE_X} * ${SIZE_Y} * ${SIZE_Z}" | bc)
echo "搜索空间体积: $(printf "%.0f" $total_volume) Å³"
echo "预估运行时间: 5-30分钟（取决于详尽度和CPU数量）"
echo ""

# 显示完整的Vina命令
echo "Vina命令:"
echo "$VINA_PATH \\"
echo "  --receptor $RECEPTOR_PDBQT \\"
echo "  --ligand $LIGAND_PDBQT \\"
echo "  --center_x $CENTER_X \\"
echo "  --center_y $CENTER_Y \\"
echo "  --center_z $CENTER_Z \\"
echo "  --size_x $SIZE_X \\"
echo "  --size_y $SIZE_Y \\"
echo "  --size_z $SIZE_Z \\"
echo "  --out $OUTPUT_PDBQT \\"
echo "  --exhaustiveness $EXHAUSTIVENESS \\"
echo "  --num_modes $NUM_MODES \\"
echo "  --cpu 0"
echo ""

# 记录开始时间
start_time=$(date +%s)
echo "开始时间: $(date)"
echo "正在运行Vina..."
echo ""

# 运行Vina
if "$VINA_PATH" \
    --receptor "$RECEPTOR_PDBQT" \
    --ligand "$LIGAND_PDBQT" \
    --center_x "$CENTER_X" \
    --center_y "$CENTER_Y" \
    --center_z "$CENTER_Z" \
    --size_x "$SIZE_X" \
    --size_y "$SIZE_Y" \
    --size_z "$SIZE_Z" \
    --out "$OUTPUT_PDBQT" \
    --exhaustiveness "$EXHAUSTIVENESS" \
    --num_modes "$NUM_MODES" \
    --cpu 0 \
    > "$WORK_DIR/logs/vina_blind_docking.log" 2>&1; then
    
    # 记录结束时间
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    duration_min=$((duration / 60))
    duration_sec=$((duration % 60))
    
    echo "✅ Vina盲对接完成！"
    echo "结束时间: $(date)"
    echo "总耗时: ${duration_min}分${duration_sec}秒"
    echo ""
    
    # 检查输出文件
    if [[ -f "$OUTPUT_PDBQT" ]] && [[ -s "$OUTPUT_PDBQT" ]]; then
        echo "=========================================="
        echo "盲对接结果分析"
        echo "=========================================="
        
        # 显示文件信息
        echo "输出文件: $OUTPUT_PDBQT"
        echo "文件大小: $(du -h "$OUTPUT_PDBQT" | cut -f1)"
        echo "原子数量: $(grep -c '^ATOM\|^HETATM' "$OUTPUT_PDBQT" 2>/dev/null || echo "0")"
        echo ""
        
        # 提取并显示所有结合模式的能量
        echo "所有结合模式和能量:"
        echo "模式  |  结合能量   |  RMSD"
        echo "------|-------------|--------"
        
        mode_count=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^REMARK\ VINA\ RESULT: ]]; then
                mode_count=$((mode_count + 1))
                energy=$(echo "$line" | awk '{print $4}')
                rmsd_lb=$(echo "$line" | awk '{print $5}')
                rmsd_ub=$(echo "$line" | awk '{print $6}')
                printf "%4d  |  %8s   |  %s\n" "$mode_count" "$energy" "$rmsd_lb"
            fi
        done < "$OUTPUT_PDBQT"
        
        if [[ $mode_count -eq 0 ]]; then
            echo "未找到结合模式信息，检查输出文件格式"
        else
            echo ""
            echo "找到 $mode_count 个结合模式"
            
            # 显示最佳结合能量
            best_energy=$(grep "REMARK VINA RESULT" "$OUTPUT_PDBQT" | head -1 | awk '{print $4}')
            echo "🏆 最佳结合能量: ${best_energy} kcal/mol"
        fi
        
        echo ""
        echo "=========================================="
        echo "✅ 盲对接流水线完成！"
        echo "=========================================="
        echo ""
        echo "结果文件位置: $OUTPUT_PDBQT"
        echo "详细日志: $WORK_DIR/logs/vina_blind_docking.log"
        echo ""
        echo "🔍 下一步建议:"
        echo "  1. 使用PyMOL可视化结果: pymol $RECEPTOR_PDB $OUTPUT_PDBQT"
        echo "  2. 分析蛋白-配体相互作用"
        echo "  3. 如需更精确结果，可增加详尽度重新运行"
        
    else
        echo "❌ Vina运行成功但未生成输出文件"
        echo ""
        echo "检查Vina日志:"
        cat "$WORK_DIR/logs/vina_blind_docking.log" | tail -20
    fi
    
else
    echo "❌ Vina盲对接失败"
    echo ""
    echo "错误信息:"
    cat "$WORK_DIR/logs/vina_blind_docking.log" | tail -20 || echo "  无日志文件"
    echo ""
    echo "调试信息:"
    echo "  受体文件: $RECEPTOR_PDBQT (大小: $(ls -lh "$RECEPTOR_PDBQT" 2>/dev/null | awk '{print $5}' || echo "文件不存在"))"
    echo "  配体文件: $LIGAND_PDBQT (大小: $(ls -lh "$LIGAND_PDBQT" 2>/dev/null | awk '{print $5}' || echo "文件不存在"))"
    echo "  搜索中心: ($CENTER_X, $CENTER_Y, $CENTER_Z)"
    echo "  搜索大小: ($SIZE_X, $SIZE_Y, $SIZE_Z)"
    exit 1
fi

echo ""
echo "🎉 盲对接任务完成！"