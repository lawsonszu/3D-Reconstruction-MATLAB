# 结构光三维重建 (3D Reconstruction using Structured Light)

## 📌 项目简介
本项目基于**主动照明焦点变化技术 (Active Illumination Focus Variation, AiFV)** 与 **HiLo 算法**，实现了微观表面形貌的高精度三维重建。

传统焦点变化 (FV) 技术难以测量缺乏纹理的光学光滑表面。为解决这一问题，本项目通过向样本表面投影人工结构光（横/竖条纹），人为引入高频纹理，并结合改进的拉普拉斯算子 (SML) 与 HiLo 频域融合技术，成功提取了兼顾低系统噪声与高横向分辨率的光学切片 (Optically-sectioned image)。

## 📁 文件结构与核心代码
* `SML_sectioned.m`：**单层光学切片提取验证脚本**。逐步展示了从原始条纹/均匀图像到背景相减、SML对比度计算、高斯平滑以及 HiLo 频域融合的全链路过程，并包含详细的中间结果可视化。
* `main_sml_hilo.m`：**全流程 Z-Stack 轴向扫描三维重建脚本**。包含序列图像读取、逐层切片提取、Z轴响应去噪、亚像素级峰值定位（5点 log-二次拟合）以及基于置信度引导的保边平滑与 3D 可视化。

## 🔬 算法原理解析 (Pipeline)
本项目的核心切片提取流程参考了 Martínez 等人的研究，以 `SML_sectioned.m` 为例，具体流程如下：

1.  **背景相减 (Background Subtraction)**：
    使用带有条纹的结构光图像 ($I_V$, $I_H$) 减去均匀照明图像 ($I_{UI}$)。此步骤用于去除离焦背景信号，仅保留聚焦区域的结构光高频图案。
2.  **计算局部对比度 (Focus Variation Operator)**：
    对相减后的图像应用焦点变化算子。本项目采用 **5x5 窗口的改进拉普拉斯算子 (Sum of Modified Laplacian, SML)**。我们将横向和竖向条纹的 SML 结果进行合并，以消除单一方向条纹带来的方向敏感性，达到类似棋盘格投影 的各向同性效果。
3.  **高斯模糊 (Gaussian Blurring)**：
    对 SML 对比度图像应用高斯平滑 ($\sigma_{xy}$)。其目的是消除对比度图像中残留的结构光人工空间频率（即条纹本身）。
4.  **HiLo 高频恢复 (HiLo Image Reconstruction)**：
    高斯模糊会损失图像的原始高频形貌细节。为了恢复高频信息，我们在频域中对模糊后的对比度图像应用低通滤波 (Low-pass filter)，同时对原始的均匀照明图像应用互补的高通滤波 (High-pass filter)，最后将两者结合。HiLo 方法具有极高的鲁棒性，且对样本表面反射率的变化不敏感。
5.  **轴向响应与亚层拟合 (Axial Response & Sub-layer Fitting)**：
    使用 Log 函数对 SML 对比度与 HiLo 切片进行非线性加权融合。通过提取 Z 轴序列 (Z-Stack) 上的局部响应最大值，并结合 5点二次拟合进行亚层定位，最终映射出三维深度图 (Height map)。

## 🚀 快速开始 (Usage)

### 1. 准备数据
请将采集到的 Z-Stack 图像序列按照高度分别存放在数字命名的文件夹中（例如 `1`, `2`, `3` ...）。
每个文件夹内需包含：
* `1.png`: 竖条纹结构光图像
* `5.png`: 横条纹结构光图像
* `9.png`: 均匀照明图像

### 2. 参数配置
在 `main_sml_hilo.m` 中修改以下核心参数：
* `data_root`：修改为你的本地图像文件夹路径。
* `sigma_xy` (默认 16)：对比度图像的 XY 平滑尺度，影响切片质量与横向分辨率间的折中。
* `cutoff_freq` (默认 50)：HiLo 算法在傅里叶频域的截止频率。
* `w_fuse` (默认 0.6)：低频对比度与高频光学切片的 Log 融合权重。

### 3. 运行重建
直接在 MATLAB 中运行 `main_sml_hilo.m`，程序将自动输出 2D 深度图以及 3D 表面形貌渲染图。

## 📄 参考文献 (References)
1. P. Martínez, C. Bermudez, G. Carles, C. Cadevall, A. Matilla, J. Marine, R. Artigas. *"Metrological characterization of different methods for recovering the optically sectioned image by means of structured light,"* Proc. SPIE 11782 (2021).
2. C. Bermudez, P. Martinez, C. Cadevall, R. Artigas. *"Active illumination focus variation,"* Proc. SPIE 11056 (2019).
