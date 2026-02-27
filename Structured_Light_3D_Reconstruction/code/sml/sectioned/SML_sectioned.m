%% 全流程结构光光学切片提取验证 (Full Pipeline Optical Sectioning Demo)
% 目标：展示从原始图像到最终轴向响应的每一个中间步骤
% 参考框架：Active Illumination Focus Variation + HiLo

clc; clear; close all;

%% ==================== 1. 参数设置 ====================
name_V  = '1.png';  % 竖条纹结构光图像 (Vertical)
name_H  = '5.png';  % 横条纹结构光图像 (Horizontal)
name_UI = '9.png';  % 均匀照明图像 (Uniform)

sigma_xy    = 12;   % 对比度平滑尺度 (平滑周期性网格纹)
cutoff_freq = 50;   % HiLo 高低通截止频率
w_fuse      = 0.6;  % Log 融合权重

%% ==================== 2. 数据读取与预处理 ====================
if ~exist(name_V, 'file') || ~exist(name_H, 'file') || ~exist(name_UI, 'file')
    error('未找到图片！请确保 1.png, 5.png, 9.png 与本脚本在同一文件夹下。');
end

% 读取并强制转换为单通道灰度图 (Double类型)
read_gray = @(x) double(mean(imread(x), 3)); 
I_V  = read_gray(name_V);
I_H  = read_gray(name_H);
I_UI = read_gray(name_UI);

[rows, cols] = size(I_UI);
fprintf('成功读取灰度图像，尺寸: %d x %d\n', rows, cols);

%% ============= 3. 预计算 HiLo 频域滤波器 =============
cx = ceil(cols/2); cy = ceil(rows/2);
[u_grid, v_grid] = meshgrid(1:cols, 1:rows);
dist_sq = (u_grid - cx).^2 + (v_grid - cy).^2;

LP = exp(-dist_sq / (2 * cutoff_freq^2));
LP = ifftshift(LP); % 适配 MATLAB fft2 的频谱分布
HP = 1 - LP;

%% ============ 4. 核心计算与中间变量保存 ============
fprintf('正在计算全流程光学切片...\n');

% [Step 1] 差分：去除离焦背景，保留纯结构光信号
dV = I_V - I_UI;
dH = I_H - I_UI;

% [Step 2] 计算单向 SML 对比度
SML_V = SML5(dV);
SML_H = SML5(dH);

% [Step 3] 对比度合并与平滑
CI_raw = 0.5 * (SML_V + SML_H);
CI_smooth = imgaussfilt(CI_raw, sigma_xy);

% [Step 4] HiLo 光学切片重建 
% 分别获取对比度的低频和 UI 的高频 (此处仅为了展示，所以拆开算)
CI_lowpass  = real(ifft2( fft2(CI_smooth) .* LP ));
UI_highpass = real(ifft2( fft2(I_UI) .* HP ));

Isec = CI_lowpass + UI_highpass;
Isec = max(Isec, 0); % 截断负值

% [Step 5] Log 非线性加权融合
resp = w_fuse * log1p(CI_smooth) + (1 - w_fuse) * log1p(Isec);

fprintf('计算完成！准备可视化...\n');

%% ==================== 5. 全景可视化 ====================
figure('Name', '全流程光学切片提取细节', 'Color', 'w', 'Position', [100, 100, 1000, 600]);
colormap_gray = 'gray';   % 全程使用灰度

% --- 第一排：原始输入 ---
subplot(3,4,1); imagesc(I_V); colormap(gca, colormap_gray); axis image off;
title('1. 竖条纹结构光 (I_V)');
subplot(3,4,2); imagesc(I_H); colormap(gca, colormap_gray); axis image off;
title('2. 横条纹结构光 (I_H)');
subplot(3,4,3); imagesc(I_UI); colormap(gca, colormap_gray); axis image off;
title('3. 均匀照明 (I_{UI})');

% --- 第二排：差分与边缘特征提取 ---
% 注意：差分图有负数，用 abs 方便可视化实际信号强度
subplot(3,4,5); imagesc(abs(dV)); colormap(gca, colormap_gray); axis image off;
title('4. 竖向差分信号 |I_V - I_{UI}|');
subplot(3,4,6); imagesc(abs(dH)); colormap(gca, colormap_gray); axis image off;
title('5. 横向差分信号 |I_H - I_{UI}|');
subplot(3,4,7); imagesc(SML_V); colormap(gca, colormap_gray); axis image off;
title('6. 竖向 SML 对比度特征');
subplot(3,4,8); imagesc(SML_H); colormap(gca, colormap_gray); axis image off;
title('7. 横向 SML 对比度特征');

% --- 第三排：平滑、频域合并与最终响应 ---
subplot(3,4,9); imagesc(CI_raw); colormap(gca, colormap_gray); axis image off;
title('8. 合并原始对比度 (CI_{raw})');
subplot(3,4,10); imagesc(CI_smooth); colormap(gca, colormap_gray); axis image off;
title(sprintf('9. 高斯平滑对比度 (CI_{smooth})\n[\\sigma_{xy} = %d]', sigma_xy));
subplot(3,4,11); imagesc(Isec); colormap(gca, colormap_gray); axis image off;
title(sprintf('10. HiLo 切片 (CI低频 + UI高频)\n[Cutoff = %d]', cutoff_freq));
subplot(3,4,12); imagesc(resp); colormap(gca, colormap_gray); axis image off;
title(sprintf('11. 最终 Log 融合响应 (Resp)\n[w_{fuse} = %.1f]', w_fuse));

sgtitle('Active Illumination Focus Variation + HiLo 完整信号链路分析', 'FontSize', 16, 'FontWeight', 'bold');

%% ==================== 局部函数区 ====================
function CI = SML5(img)
% 焦点变化核心算子：Modified Laplacian + 5x5窗口局部求和
    ML = abs(imfilter(img, [-1 2 -1], 'replicate')) + ...
         abs(imfilter(img, [-1; 2; -1], 'replicate'));
    CI = imfilter(ML, ones(5,5), 'replicate');
end