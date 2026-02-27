%% 平方法 + HiLo 光学切片提取
clc; close all;

% ---------- 0) read ----------
filename_V  = '1.png';   % vertical stripes
filename_H  = '5.png';   % horizontal stripes
filename_UI = '9.png';   % uniform illumination

assert(isfile(filename_V) && isfile(filename_H) && isfile(filename_UI), '找不到图片，请检查路径或文件名');

I_V  = im2double(imread(filename_V));
I_H  = im2double(imread(filename_H));
I_UI = im2double(imread(filename_UI));

% to gray if needed
if ndims(I_V)==3,  I_V  = rgb2gray(I_V);  end
if ndims(I_H)==3,  I_H  = rgb2gray(I_H);  end
if ndims(I_UI)==3, I_UI = rgb2gray(I_UI); end

[rows, cols] = size(I_V);

% ---------- 1) subtraction (gain match + diff) ----------
% gain match to reduce DC residue (very important in practice)
alphaV = mean(I_V(:))  / (mean(I_UI(:)) + eps);
alphaH = mean(I_H(:))  / (mean(I_UI(:)) + eps);

D_V = I_V - alphaV * I_UI;
D_H = I_H - alphaH * I_UI;

% ---------- 2) 平方法：结合两个正交方向的差分信号 ----------
% 使用 hypot 计算：sqrt(D_V^2 + D_H^2)
I0 = hypot(D_V, D_H);          % 平方法结合
I0 = I0 - mean(I0(:));         % 零均值

% ---------- 3) Gaussian smoothing ----------
sigma = 12;
I0_blur = imgaussfilt(I0, sigma);

% ---------- 3.5) 预计算 HiLo 频域滤波器 ----------
cutoff_freq = 50;   % HiLo 高低通截止频率
cx = ceil(cols/2); cy = ceil(rows/2);
[u_grid, v_grid] = meshgrid(1:cols, 1:rows);
dist_sq = (u_grid - cx).^2 + (v_grid - cy).^2;
LP = exp(-dist_sq / (2 * cutoff_freq^2));
LP = ifftshift(LP); % 适配 MATLAB fft2 的频谱分布
HP = 1 - LP;

% ---------- 4) HiLo 光学切片重建 (sectioning) ----------
% I0_blur 的低频 + I_UI 的高频
I0_lowpass  = real(ifft2( fft2(I0_blur) .* LP ));
UI_highpass = real(ifft2( fft2(I_UI) .* HP ));
CI = I0_lowpass + UI_highpass;  % 对比度图（HiLo结果）
CI = max(CI, 0); % 截断负值

% ---------- show ----------
figure('Color','w','Position',[100 100 1000 600]);
subplot(2,3,1); imshow(D_V,[]); title('Step1: D_V (竖差分)');
subplot(2,3,2); imshow(D_H,[]); title('Step2: D_H (横差分)');
subplot(2,3,3); imshow(I0,[]); title('Step2.5: sqrt(D_V^2+D_H^2) (平方法)');
subplot(2,3,4); imshow(I0_blur,[]); title(['Step3: 高斯平滑 σ=' num2str(sigma)]);
subplot(2,3,5); imshow(CI,[]); title(['Step4: HiLo 对比度图 (cutoff=' num2str(cutoff_freq) ')']);
subplot(2,3,6); imshow(I_UI,[]); title('参考: 均匀照明 (I_UI)');

sgtitle('平方法 + HiLo 光学切片提取', 'FontSize', 14, 'FontWeight', 'bold');

% ROI zoom (optional)
roi_r = floor(rows/2)-120 : floor(rows/2)+120;
roi_c = floor(cols/2)-120 : floor(cols/2)+120;

figure('Color','w','Position',[200 200 900 300]);
subplot(1,2,1); imshow(I0(roi_r,roi_c),[]); title('ROI: 平方法结合');
subplot(1,2,2); imshow(CI(roi_r,roi_c),[]); title('ROI: HiLo 对比度');