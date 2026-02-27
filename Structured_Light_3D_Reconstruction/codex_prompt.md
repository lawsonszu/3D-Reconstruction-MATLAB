# 结构光三维重建 (Active Illumination Focus Variation) 项目上下文

## 1. 项目背景与身份定义
- **用户身份**：光电信息科学与工程专业大二本科生。
- **AI 助手角色**：MATLAB 图像处理与三维重建算法专家。
- **研究目标**：基于主动照明的焦点变化法 (AiFV) 与结构光照明，重建光滑/低对比度表面的 3D 形貌。
- **核心难点**：消除重建结果中的同心圈 (Concentric rings)、台阶纹 (Step artifacts) 以及峰位跳层抖动，在“信息充足区域”尽量还原真实光滑形貌。

## 2. 理论基础 (参考论文)
本算法主要基于以下两篇文献：
1. *"Metrological characterization of different methods for recovering the optically sectioned image by means of structured light" (Martinez 等)*
2. *"Active illumination focus variation" (Bermudez 等)*

**论文核心四步法**：
1. **Subtraction (相减去背景)**：结构光图减去均匀照明图，提取焦平面的结构光高频调制。
2. **Contrast Image (对比度计算)**：论文推荐使用 FV 算子（如 Sum of Modified Laplacian, SML），本代码中采用 5x5 的 SML。
3. **Gaussian Blur (高斯平滑)**：去除对比度图的高频空间结构图案（本代码对应参数 `sigma_xy`）。
4. **High-frequency Recovery (高频恢复)**：论文推荐 HiLo 重建法，即在频域结合低通滤波后的对比度图和高通滤波后的均匀图（本代码对应参数 `cutoff_freq`）。

## 3. 现有数据与代码管线 (The Pipeline)
由于我们采集的是**横条纹(H)**和**竖条纹(V)**，而不是论文中的棋盘格，代码在底层做出了相应适配。当前代码包含 6 个核心 Step：

### Step 1: 数据读取与预处理
- 数据为 Z-stack 轴向扫描图。包含垂直条纹(`name_V`)、水平条纹(`name_H`)和均匀光(`name_UI`)。
- 预先生成 HiLo 频域高通/低通滤波器 (`LP` 和 `HP`)。

### Step 2: 逐层轴向响应构建 (构建三维体 `vol_response`)
- **双向 SML 融合**：分别计算 `dV = I_V - I_UI` 和 `dH = I_H - I_UI` 的 SML，再取平均 `CI = 0.5 * (SML5(dV) + SML5(dH))`。
- **XY 高斯平滑**：`imgaussfilt(CI, sigma_xy)`，论文指出 $\sigma \ge 6$ 效果较好，当前代码使用 `sigma_xy = 16` 以提升稳定性。
- **HiLo 切片提取**：`Isec = real(ifft2( fft2(CI).*LP + fft2(I_UI).*HP ))`。
- **加权对数融合**：`resp = w_fuse*log1p(CI) + (1-w_fuse)*log1p(Isec)`，结合对比度图和 HiLo 切片构建最终响应。

### Step 3: Z 向一维平滑
- 使用 1D 高斯核 (`sigma_z = 1.5`) 沿着 Z 轴方向平滑 `vol_response`。
- **目的**：抑制轴向响应的噪声，防止亚像素拟合时出现跳层和峰位抖动。

### Step 4: 5点 Log-二次亚层拟合 (Sub-pixel Peak Localization)
- 定位离散峰值所在层 `idx_0`，取其前后各 2 层（共 5 层）。
- 通过计算伪逆矩阵 `P = pinv(X)`，利用这 5 层的对数响应 `log(resp + eps)` 进行二次抛物线拟合求极大值，计算亚层偏移量 `delta`。
- **痛点**：这是消除同心圈和台阶纹的核心步骤，当前算法依赖对数域拟合，遇到弱信息区容易失效产生 NaN 或异常极大值。

### Step 5: 深度图后处理 (Post-processing)
- **去离群点**：基于中值滤波 (`med_win = [5 5]`) 和绝对中位差 (MAD, 阈值 `outlier_k = 3`) 剔除尖刺。
- **置信度图 (Confidence Map)**：利用峰值强度 `peak_strength` 归一化后经过非线性幂次 `conf_pow` 映射作为置信度。
- **置信度引导的保边平滑**：优先使用 `imguidedfilter`（引导滤波），用置信度图做 guide。
- **加权融合**：`height_map = alpha .* hm + (1 - alpha) .* hm_s`，信息充足区保真，弱信息区顺滑。

### Step 6: 3D 可视化
- 使用 `surf` 配合光照材质 (`camlight`, `gouraud`) 展示 2D 深度图和 3D 形貌。

## 4. 给 AI 的工作准则
当我在提问中要求你修改代码、优化算法或排查问题时，请遵循以下原则：
1. **理解痛点**：重点关注如何通过调参或改进数学模型（特别是 Step 4 的亚层拟合和 Step 3 的 Z向平滑）来**消除台阶纹和同心圈**。
2. **保持框架**：不要随意推翻现有的 6 步管线，你的修改应基于现有的变量名（如 `vol_response`, `sigma_xy`, `cutoff_freq`, `w_fuse`）。
3. **算法依据**：任何对 SML、HiLo 滤波或亚像素拟合公式的修改，请简要说明其背后的信号处理或光学理论支撑。
4. **性能考量**：MATLAB 擅长矩阵运算，在修改如三维矩阵切片、索引逻辑（如 Step 4 中的 `lin0`, `linm1` 线性索引）时，必须避免使用多重 `for` 循环，保持向量化编程。