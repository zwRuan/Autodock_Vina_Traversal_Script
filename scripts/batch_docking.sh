#!/bin/bash

# 主控批量对接脚本
# 控制m×n蛋白质-配体组合的顺序遍历和盲对接

set -e

echo "=========================================="
echo "主控批量盲对接脚本"
echo "m×n 蛋白质-配体组合顺序执行"
echo "=========================================="

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 目录配置
PROTEINS_DIR="$PROJECT_DIR/proteins"
LIGANDS_DIR="$PROJECT_DIR/ligands"
CONFIGS_DIR="$PROJECT_DIR/configs"
RESULTS_DIR="$PROJECT_DIR/results"

# 脚本路径
GENERATE_CONFIG_SCRIPT="$SCRIPT_DIR/generate_config.sh"
VINA_DOCKING_SCRIPT="$SCRIPT_DIR/vina_blind_docking.sh"

echo "项目目录: $PROJECT_DIR"
echo "脚本目录: $SCRIPT_DIR"
echo ""

# 检查环境和脚本
check_environment() {
    echo "检查环境和脚本..."
    
    # 检查目录
    for dir in "$PROTEINS_DIR" "$LIGANDS_DIR"; do
        if [[ ! -d "$dir" ]]; then
            echo "错误: 目录不存在: $dir"
            exit 1
        fi
    done
    
    # 创建输出目录
    mkdir -p "$CONFIGS_DIR" "$RESULTS_DIR"
    
    # 检查脚本文件
    for script in "$GENERATE_CONFIG_SCRIPT" "$VINA_DOCKING_SCRIPT"; do
        if [[ ! -f "$script" ]]; then
            echo "错误: 脚本文件不存在: $script"
            exit 1
        fi
        
        if [[ ! -x "$script" ]]; then
            echo "设置脚本执行权限: $script"
            chmod +x "$script"
        fi
    done
    
    # 检查必要工具
    for tool in vina prepare_receptor4 prepare_ligand4 python3; do
        if ! command -v "$tool" &> /dev/null; then
            echo "错误: 缺少工具 $tool"
            exit 1
        fi
    done
    
    echo "✓ 环境检查完成"
}

# 扫描输入文件
scan_input_files() {
    echo ""
    echo "扫描输入文件..."
    
    # 查找蛋白质文件
    PROTEIN_FILES=()
    while IFS= read -r -d '' file; do
        PROTEIN_FILES+=("$file")
    done < <(find "$PROTEINS_DIR" -name "*.pdb" -print0 | sort -z)
    
    # 查找配体文件
    LIGAND_FILES=()
    while IFS= read -r -d '' file; do
        LIGAND_FILES+=("$file")
    done < <(find "$LIGANDS_DIR" -name "*.pdb" -print0 | sort -z)
    
    if [[ ${#PROTEIN_FILES[@]} -eq 0 ]]; then
        echo "错误: 未找到蛋白质PDB文件在 $PROTEINS_DIR"
        exit 1
    fi
    
    if [[ ${#LIGAND_FILES[@]} -eq 0 ]]; then
        echo "错误: 未找到配体PDB文件在 $LIGANDS_DIR"
        exit 1
    fi
    
    echo "✓ 发现 ${#PROTEIN_FILES[@]} 个蛋白质文件:"
    for protein in "${PROTEIN_FILES[@]}"; do
        echo "  - $(basename "$protein")"
    done
    
    echo "✓ 发现 ${#LIGAND_FILES[@]} 个配体文件:"
    for ligand in "${LIGAND_FILES[@]}"; do
        echo "  - $(basename "$ligand")"
    done
    
    echo "✓ 总计 $((${#PROTEIN_FILES[@]} * ${#LIGAND_FILES[@]})) 个组合"
}

# 执行单个对接任务
run_single_task() {
    local protein_pdb="$1"
    local ligand_pdb="$2"
    local task_id="$3"
    local total_tasks="$4"
    
    local protein_name=$(basename "$protein_pdb" .pdb)
    local ligand_name=$(basename "$ligand_pdb" .pdb)
    local job_name="${protein_name}_${ligand_name}"
    
    echo ""
    echo "=========================================="
    echo "任务 $task_id/$total_tasks: $job_name"
    echo "蛋白质: $protein_name"
    echo "配体: $ligand_name"
    echo "=========================================="
    
    # 文件路径
    local config_file="$CONFIGS_DIR/${job_name}.txt"
    local result_dir="$RESULTS_DIR/$job_name"
    local result_file="$result_dir/${ligand_name}_out.pdbqt"
    
    # 创建结果目录
    mkdir -p "$result_dir"
    
    # 步骤1: 生成配置文件
    echo "步骤1: 生成盲对接配置文件..."
    echo "执行: $GENERATE_CONFIG_SCRIPT \"$protein_pdb\" \"$ligand_pdb\" -o \"$config_file\""
    
    if "$GENERATE_CONFIG_SCRIPT" "$protein_pdb" "$ligand_pdb" -o "$config_file"; then
        echo "✓ 配置文件生成成功: $config_file"
    else
        echo "❌ 配置文件生成失败"
        return 1
    fi
    
    # 检查配置文件内容
    if [[ ! -f "$config_file" ]] || [[ ! -s "$config_file" ]]; then
        echo "❌ 配置文件为空或不存在"
        return 1
    fi
    
    # 显示配置文件关键信息
    echo "配置文件关键参数:"
    grep -E "center_|size_" "$config_file" | sed 's/^/  /'
    
    # 步骤2: 执行分子对接
    echo ""
    echo "步骤2: 执行Vina盲对接..."
    echo "工作目录: $result_dir"
    echo "执行: $VINA_DOCKING_SCRIPT \"$protein_pdb\" \"$ligand_pdb\" \"$config_file\" \"$result_dir\""
    
    local start_time=$(date +%s)
    
    if "$VINA_DOCKING_SCRIPT" "$protein_pdb" "$ligand_pdb" "$config_file" "$result_dir"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local duration_min=$((duration / 60))
        local duration_sec=$((duration % 60))
        
        echo "✓ 对接完成，耗时: ${duration_min}分${duration_sec}秒"
        
        # 检查结果文件
        if [[ -f "$result_file" ]] && [[ -s "$result_file" ]]; then
            echo "✓ 结果文件生成成功: $result_file"
            
            # 提取最佳结合能量
            local best_energy=$(grep "REMARK VINA RESULT" "$result_file" | head -1 | awk '{print $4}' 2>/dev/null || echo "N/A")
            echo "🏆 最佳结合能量: $best_energy kcal/mol"
            
            # 文件信息
            local file_size=$(du -h "$result_file" | cut -f1)
            local atom_count=$(grep -c '^ATOM\|^HETATM' "$result_file" 2>/dev/null || echo "0")
            echo "📁 文件大小: $file_size, 原子数: $atom_count"
            
            echo "✅ 任务 $task_id 成功完成: $job_name"
            return 0
        else
            echo "❌ 结果文件未生成或为空"
            return 1
        fi
    else
        echo "❌ Vina对接失败"
        return 1
    fi
}

# 生成批量报告
generate_batch_report() {
    local total_tasks="$1"
    local successful_tasks="$2"
    local failed_tasks="$3"
    local total_duration="$4"
    
    local report_file="$RESULTS_DIR/batch_report.txt"
    
    cat > "$report_file" << EOF
批量盲对接结果报告
====================
生成时间: $(date)
总任务数: $total_tasks
成功完成: $successful_tasks
失败任务: $failed_tasks
成功率: $(( successful_tasks * 100 / total_tasks ))%
总耗时: $((total_duration / 60))分$((total_duration % 60))秒

详细结果:
EOF
    
    echo "蛋白质-配体组合 | 状态 | 最佳能量(kcal/mol) | 结果文件" >> "$report_file"
    echo "----------------|------|------------------|----------" >> "$report_file"
    
    for protein_pdb in "${PROTEIN_FILES[@]}"; do
        for ligand_pdb in "${LIGAND_FILES[@]}"; do
            local protein_name=$(basename "$protein_pdb" .pdb)
            local ligand_name=$(basename "$ligand_pdb" .pdb)
            local job_name="${protein_name}_${ligand_name}"
            local result_file="$RESULTS_DIR/$job_name/${ligand_name}_out.pdbqt"
            
            if [[ -f "$result_file" ]] && [[ -s "$result_file" ]]; then
                local energy=$(grep "REMARK VINA RESULT" "$result_file" | head -1 | awk '{print $4}' 2>/dev/null || echo "N/A")
                printf "%-15s | %-4s | %-16s | %s\n" "$job_name" "成功" "$energy" "$result_file" >> "$report_file"
            else
                printf "%-15s | %-4s | %-16s | %s\n" "$job_name" "失败" "N/A" "无" >> "$report_file"
            fi
        done
    done
    
    echo ""
    echo "📊 批量报告已生成: $report_file"
}

# 主函数
main() {
    local batch_start_time=$(date +%s)
    
    # 检查环境
    check_environment
    
    # 扫描输入文件
    scan_input_files
    
    # 执行批量对接
    local total_tasks=$((${#PROTEIN_FILES[@]} * ${#LIGAND_FILES[@]}))
    local current_task=0
    local successful_tasks=0
    local failed_tasks=0
    
    echo ""
    echo "开始批量盲对接（顺序执行）..."
    
    for protein_pdb in "${PROTEIN_FILES[@]}"; do
        for ligand_pdb in "${LIGAND_FILES[@]}"; do
            current_task=$((current_task + 1))
            
            if run_single_task "$protein_pdb" "$ligand_pdb" "$current_task" "$total_tasks"; then
                successful_tasks=$((successful_tasks + 1))
            else
                failed_tasks=$((failed_tasks + 1))
                echo "❌ 任务失败: $(basename "$protein_pdb" .pdb)_$(basename "$ligand_pdb" .pdb)"
            fi
            
            # 显示进度
            echo ""
            echo "进度: $current_task/$total_tasks (成功: $successful_tasks, 失败: $failed_tasks)"
        done
    done
    
    # 生成总结
    local batch_end_time=$(date +%s)
    local total_duration=$((batch_end_time - batch_start_time))
    
    echo ""
    echo "=========================================="
    echo "批量盲对接完成！"
    echo "=========================================="
    echo "总任务数: $total_tasks"
    echo "成功完成: $successful_tasks"
    echo "失败任务: $failed_tasks"
    echo "成功率: $(( successful_tasks * 100 / total_tasks ))%"
    echo "总耗时: $((total_duration / 60))分$((total_duration % 60))秒"
    echo ""
    echo "结果目录: $RESULTS_DIR"
    echo "配置目录: $CONFIGS_DIR"
    
    # 生成报告
    generate_batch_report "$total_tasks" "$successful_tasks" "$failed_tasks" "$total_duration"
    
    echo ""
    echo "🎉 批量盲对接系统完成！"
}

# 运行主函数
main "$@"