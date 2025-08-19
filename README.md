# AutoDock Vina 批量盲对接系统

一个基于AutoDock Vina的自动化分子对接流水线，支持m×n蛋白质-配体组合的批量盲对接。

## 🚀 快速开始

### 环境安装

按顺序执行以下命令安装所需环境：

```bash
# 设置CUDA环境变量
export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:${LD_LIBRARY_PATH}
export GPU_INCLUDE_PATH=$CUDA_HOME/include
export GPU_LIBRARY_PATH=$CUDA_HOME/lib64

# 编译AutoDock-GPU
make clean
make DEVICE=CUDA NUMWI=64 OVERLAP=ON

# 激活conda环境并安装Python依赖
conda activate meeko311
pip install git+https://github.com/Valdes-Tresanco-MS/AutoDockTools_py3
pip install meson ninja meeko==0.6.1 rdkit scipy

# 安装AutoGrid（用于网格文件生成）
cd AutoGrid
conda install -c conda-forge autoconf automake libtool pkg-config tcsh
meson setup --wipe builddir --prefix=$HOME/.local
meson compile -C builddir
meson install -C builddir
export PATH="$HOME/.local/bin:$PATH"

# 验证安装
autogrid4 -h

# 安装Autodock Vina
bash install_vina_script.sh
```

### 文件准备

按照以下目录结构准备输入文件：

```
项目根目录/
├── proteins/          # 蛋白质PDB文件目录
│   ├── egfr.pdb
│   ├── protein2.pdb
│   └── ...
├── ligands/           # 配体PDB文件目录
│   ├── Afatinib.pdb
│   ├── ligand2.pdb
│   └── ...
├── scripts/           # 脚本目录
│   ├── batch_docking.sh
│   ├── generate_config.sh
│   └── vina_blind_docking.sh
├── configs/           # 配置文件（自动生成）
└── results/           # 结果目录（自动生成）
```

### 执行批量对接

```bash
bash scripts/batch_docking.sh
```

## 📁 输出结构

执行完成后，结果将按以下结构组织：

```
results/
├── egfr_Afatinib/           # 蛋白质-配体组合目录
│   ├── logs/
│   │   └── vina_blind_docking.log    # Vina运行日志
│   ├── egfr.pdbqt              # 转换后的蛋白质文件
│   ├── Afatinib.pdbqt          # 转换后的配体文件
│   └── Afatinib_out.pdbqt      # 对接结果文件
├── protein2_ligand2/        # 其他组合...
└── batch_report.txt         # 批量结果汇总报告
```

## 🔧 核心脚本功能详解 (讲解各个脚本功能，不影响使用)

### 1. `scripts/generate_config.sh` - 配置文件生成器

**功能**：为每个蛋白质-配体对自动生成盲对接配置文件

**工作原理**：
1. **蛋白质结构分析**：
   ```python
   # 读取PDB文件中的所有ATOM记录
   coords = []
   for line in pdb_file:
       if line.startswith('ATOM'):
           x, y, z = extract_coordinates(line)
           coords.append([x, y, z])
   ```

2. **几何中心计算**：
   ```python
   # 计算蛋白质的几何中心作为搜索中心
   center = np.mean(coords, axis=0)
   ```

3. **搜索盒子尺寸确定**：
   ```python
   # 计算蛋白质边界
   min_coords = np.min(coords, axis=0)
   max_coords = np.max(coords, axis=0)
   dimensions = max_coords - min_coords
   
   # 盲对接盒子 = 蛋白质尺寸 + 20Å buffer
   box_size = dimensions + 20.0
   ```

4. **配置文件生成**：
   ```bash
   # 生成标准Vina配置文件
   cat > config.txt << EOF
   receptor = protein.pdbqt
   ligand = ligand.pdbqt
   center_x = -10.123
   center_y = 6.595  
   center_z = 2.264
   size_x = 154.5
   size_y = 139.8
   size_z = 129.7
   exhaustiveness = 24
   num_modes = 1
   EOF
   ```

**关键特性**：
- ✅ **真正的盲对接**：搜索盒子完全包裹蛋白质表面
- ✅ **自适应尺寸**：根据蛋白质大小自动调整搜索空间
- ✅ **高精度搜索**：详尽度设置为24，确保全面搜索

### 2. `scripts/vina_blind_docking.sh` - Vina对接执行器

**功能**：执行单个蛋白质-配体对的完整对接流程

**工作流程**：

1. **文件格式转换**：
   ```bash
   # PDB → PDBQT 转换（AutoDockTools_py3）
   prepare_receptor4 -r protein.pdb -o protein.pdbqt \
     -A checkhydrogens -U nphs_lps_waters_nonstdres
   
   prepare_ligand4 -l ligand.pdb -o ligand.pdbqt \
     -A bonds_hydrogens
   ```

2. **配置参数解析**：
   ```bash
   # 从配置文件读取对接参数
   CENTER_X=$(grep "center_x" config.txt | sed 's/.*=\s*//')
   SIZE_X=$(grep "size_x" config.txt | sed 's/.*=\s*//')
   # ... 其他参数
   ```

3. **Vina对接执行**：
   ```bash
   vina \
     --receptor protein.pdbqt \
     --ligand ligand.pdbqt \
     --center_x $CENTER_X --center_y $CENTER_Y --center_z $CENTER_Z \
     --size_x $SIZE_X --size_y $SIZE_Y --size_z $SIZE_Z \
     --out result.pdbqt \
     --exhaustiveness 24 \
     --num_modes 1 \
     --cpu 0
   ```

4. **结果分析**：
   ```bash
   # 解析PDBQT结果文件，提取结合能量
   grep "REMARK VINA RESULT" result.pdbqt | \
   while read line; do
       energy=$(echo "$line" | awk '{print $4}')
       rmsd=$(echo "$line" | awk '{print $5}')
       echo "结合能量: $energy kcal/mol, RMSD: $rmsd"
   done
   ```

**容错机制**：
- 多种PDB转换策略，确保格式兼容性
- 自动Vina路径检测
- 详细的错误日志记录

### 3. `scripts/batch_docking.sh` - 批量对接主控制器

**功能**：协调整个批量对接流程

**执行逻辑**：
1. **环境检查**：验证所有必要工具和文件
2. **文件扫描**：自动发现proteins/和ligands/目录中的PDB文件
3. **任务生成**：创建m×n个蛋白质-配体组合任务
4. **顺序执行**：
   ```bash
   for protein in proteins/*.pdb; do
       for ligand in ligands/*.pdb; do
           # 生成配置文件
           generate_config.sh "$protein" "$ligand" -o "config.txt"
           
           # 执行对接
           vina_blind_docking.sh "$protein" "$ligand" "config.txt" "work_dir"
       done
   done
   ```
5. **结果汇总**：生成批量报告和统计信息

## 📊 结果解读

### 对接结果文件 (`*_out.pdbqt`)
- **REMARK VINA RESULT**: 包含结合能量和RMSD信息
- **MODEL**: 不同的结合构象
- **ATOM/HETATM**: 配体在结合位点的三维坐标

### 关键指标
- **结合能量**: 数值越负，结合越强（单位：kcal/mol）
- **RMSD**: 构象相似性指标（单位：Å）
- **搜索空间**: 盲对接覆盖的体积（通常>1,000,000 Å³）

### 批量报告 (`batch_report.txt`)
包含所有组合的汇总信息：
- 成功/失败统计
- 最佳结合能量排序
- 执行时间统计



---

## 📚 参考内容

本系统的开发参考了以下优秀的工作，在此表示感谢：

- **AutoDock Vina**: Trott, O. & Olson, A. J. AutoDock Vina: improving the speed and accuracy of docking. *J. Comput. Chem.* **31**, 455-461 (2010).
- **AutoDockTools**: Morris, G. M. et al. AutoDock4 and AutoDockTools4. *J. Comput. Chem.* **30**, 2785-2791 (2009).
- **AutoDock-GPU**: https://github.com/ccsb-scripps/AutoDock-GPU  
  提供了高性能GPU加速的分子对接方案
- **AutoDockTools_py3**: https://github.com/Valdes-Tresanco-MS/AutoDockTools_py3  
  现代化的Python 3兼容版本AutoDockTools
- **分子对接教程**: https://zhuanlan.zhihu.com/p/696041695  
  详细的AutoDock Vina使用指南和最佳实践
- **药物设计方法**: https://zhuanlan.zhihu.com/p/27108643502  
  计算药物设计的理论基础和实践方法
