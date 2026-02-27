# 结构光三维重建 (3D Reconstruction using Structured Light)

## 📌 项目简介
本项目基于**主动照明焦点变化技术 (Active Illumination Focus Variation, AiFV)** 与 **HiLo 算法**，实现了微观表面形貌的高精度三维重建。

传统焦点变化 (FV) 技术难以测量缺乏纹理的光学光滑表面。为解决这一问题，本项目通过向样本表面投影人工结构光（横/竖条纹），人为引入高频纹理，并结合改进的拉普拉斯算子 (SML) 与 HiLo 频域融合技术，成功提取了兼顾低系统噪声与高横向分辨率的光学切片 (Optically-sectioned image)。

## 🗂️ 实验数据采集 (开源数据)
* **实验样本**：玻璃半球样本 (Glass Hemisphere)。该样本表面光滑且具有极其剧烈的反射率变化，是验证三维重建算法鲁棒性的理想材料。
* **采集图像**：包含 Z 轴扫描序列 (Z-Stack) 的均匀照明图像、横条纹结构光图像与竖条纹结构光图像。

🔗 **原始采集数据下载 (Baidu Netdisk)**:
* **链接**: https://pan.baidu.com/s/1eizeH1gB33InE2854lLNeA?pwd=8888 
* **提取码**: 8888

## 📊 实验结果与算法对比
在针对**玻璃半球样本**（反射率剧烈变化）的重建实验中，我们对论文中提及的多种算法进行了复现与对比，得出以下结论：

1. **局部对比度算子对比 (SML vs. 平方差 vs. SPQT)**：
   在三种对比度提取方法中，基于焦点变化思想的 **SML 算子 (Sum of Modified Laplacian) 表现最为出色**。相比之下，平方差法 (Squared Difference) 和螺旋相位正交变换 (SPQT) 的还原效果较差，难以有效应对玻璃半球复杂的反光特性。
2. **高频恢复算法对比 (HiLo vs. 乘法融合)**：
   实验表明，**HiLo 算法的重建质量显著优于乘法法 (Multiplication approach)**。这与理论预期完全一致：玻璃半球表面反光极不均匀，而乘法法在样本反射率差异较大的区域会导致光学切片能力下降。HiLo 算法在傅里叶频域进行滤波处理，对反射率的剧烈变化具有极强的鲁棒性。

## 📁 文件结构与核心代码
* `SML_sectioned.m`：**单层光学切片提取验证脚本**。逐步展示了从原始条纹/均匀图像到背景相减、SML对比度计算、高斯平滑以及 HiLo 频域融合的全链路过程，并包含详细的中间结果可视化。
* `main_sml_hilo.m`：**全流程 Z-Stack 轴向扫描三维重建脚本**。包含序列图像读取、逐层切片提取、Z轴响应去噪、亚像素级峰值定位（5点 log-二次拟合）以及基于置信度引导的保边平滑与 3D 可视化。

## 🚀 快速开始 (Usage)
1. 通过上方百度网盘链接下载 `data_50-150.zip` 并解压。
2. 在 `main_sml_hilo.m` 中，将 `data_root` 变量修改为你解压后的本地数据文件夹路径。
3. 直接在 MATLAB 中运行 `main_sml_hilo.m`，程序将自动输出 2D 深度图以及 3D 表面形貌渲染图。
*(注：默认参数 `sigma_xy = 16`, `cutoff_freq = 50`, `w_fuse = 0.6` 已针对当前玻璃半球样本进行过优化)*

## 📄 参考文献 (References)
1. P. Martínez, C. Bermudez, G. Carles, C. Cadevall, A. Matilla, J. Marine, R. Artigas. *"Metrological characterization of different methods for recovering the optically sectioned image by means of structured light,"* Proc. SPIE 11782 (2021).
2. C. Bermudez, P. Martinez, C. Cadevall, R. Artigas. *"Active illumination focus variation,"* Proc. SPIE 11056 (2019).
