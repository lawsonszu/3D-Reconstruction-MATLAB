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
   实验表明，**HiLo 算法的重建质量显著优于乘法法 (Multiplication approach)**。这与理论预期完全一致：玻璃半球表面反光极不均匀，而乘法法在样本反射率差异较大的区域会导致光学切片能力下降。HiLo 算法在傅里叶频域进行滤波处理，保留了低空间频率的幅度，因此对反射率的剧烈变化具有极强的鲁棒性。

## 🔬 具体计算流程 (Algorithm Pipeline)
本项目的核心切片提取与三维重建流程参考了 Martínez 等人的研究，并在 `main_sml_hilo.m` 中严格落实了以下计算步骤：

1. **背景相减 (Background Subtraction)**：
   分别将横向、竖向结构光图像减去均匀照明图像 ($I_V - I_{UI}$, $I_H - I_{UI}$)，去除离焦背景信号，仅保留聚焦区域的结构光高频图案。
2. **局部对比度计算 (Focus Variation Operator)**：
   采用 **5x5 窗口的改进拉普拉斯算子 (SML)** 分别计算横向与竖向信号的对比度并求均值。此举旨在消除单一方向条纹带来的方向敏感性，达到类似棋盘格投影 的各向同性效果。
3. **高斯模糊去纹理 (Gaussian Blurring)**：
   对 SML 对比度图像应用高斯平滑 (`sigma_xy`)，消除对比度图像中残留的结构光空间频率（即条纹本身）。
4. **HiLo 高频恢复 (HiLo Image Reconstruction)**：
   在傅里叶频域中，对模糊后的对比度图像应用低通滤波 (Low-pass filter) 得到低频轮廓，对原始均匀照明图像应用互补的高通滤波 (High-pass filter) 获取高频细节，最后将二者在频域结合，重建出包含高频细节的光学切片。
5. **轴向响应构建 (Log Fusion & Z-Stack)**：
   使用 Log 函数对模糊对比度与 HiLo 切片进行非线性加权融合 (`w_fuse`)，遍历所有 Z 层构建完整的三维轴向响应矩阵 `vol_response`。
6. **亚层峰值定位 (Sub-layer Peak Fitting)**：
   为消除离散层距导致的“同心圈”或“台阶纹”假象，对 Z 轴方向平滑后，提取局部最大值邻域的 5 个数据点，进行 **5点 log-二次拟合**，从而解算出亚像素级别的精确深度图 (Height map)。
7. **形貌后处理 (Post-processing)**：
   利用响应峰值强度作为置信度映射 (Confidence map)，进行去离群点操作，并应用引导滤波 (Guided Filter) 实现保边平滑与加权融合，输出最终的 3D 表面点云。

## 🚀 快速开始 (Usage)
1. 下载上方百度网盘中的 `data_50-150.zip` 数据集并解压到本地。
2. 在 MATLAB 中打开 `main_sml_hilo.m`。
3. 将代码顶部的 `data_root` 变量路径修改为你解压后的数据集路径。
4. 运行程序，程序将自动输出各层光学切片的提取过程以及最终的 3D 表面形貌渲染图。
*(注：默认参数 `sigma_xy = 16`, `cutoff_freq = 50`, `w_fuse = 0.6` 已针对当前玻璃半球样本进行过优化)*

## 📄 参考文献 (References)
1. P. Martínez, C. Bermudez, G. Carles, C. Cadevall, A. Matilla, J. Marine, R. Artigas. *"Metrological characterization of different methods for recovering the optically sectioned image by means of structured light,"* Proc. SPIE 11782 (2021).
2. C. Bermudez, P. Martinez, C. Cadevall, R. Artigas. *"Active illumination focus variation,"* Proc. SPIE 11056 (2019).
