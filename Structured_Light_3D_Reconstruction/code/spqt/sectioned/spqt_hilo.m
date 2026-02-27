%% Simple SPQT (spiral phase transform) demo - minimal runnable
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

% ---------- 1.5) synthesize 2D pattern (recommended: normalized multiply) ----------
V0 = D_V - mean(D_V(:));
H0 = D_H - mean(D_H(:));
V0 = V0 / (std(V0(:)) + eps);
H0 = H0 / (std(H0(:)) + eps);

I_synth = V0 .* H0;  % key: multiplication gives a more "checker/dot" like 2D texture

% optional: remove slow background (vignetting) to help SPQT look like "rings"
sigma_bg = 60;   % 40~120 try
I0 = I_synth - imgaussfilt(I_synth, sigma_bg);
I0 = I0 - mean(I0(:));   % enforce zero-mean again

% ---------- 2) SPQT (spiral phase transform) ----------
% build spiral phase kernel aligned with fftshift(fft2(.))
[U, V] = meshgrid(-floor(cols/2):ceil(cols/2)-1, -floor(rows/2):ceil(rows/2)-1);
R = sqrt(U.^2 + V.^2);

H = (U + 1i*V) ./ (R + eps);   % exp(i*theta)
H(R==0) = 0;                   % DC must be 0

F  = fftshift(fft2(I0));
Q  = ifft2(ifftshift(F .* H)); % complex quadrature field

SPQT_edge = abs(Q);            % <<< this is the one that looks like "hollow rings"
CI        = hypot(I0, SPQT_edge); % optional "contrast image" (paper style)

% ---------- 3) Gaussian smoothing ----------
sigma = 12;
CI_blur = imgaussfilt(SPQT_edge, sigma);  % use SPQT_edge for sectioning (closer to your senior's look)

% ---------- 3.5) 预计算 HiLo 频域滤波器 ----------
cutoff_freq = 50;   % HiLo 高低通截止频率
cx = ceil(cols/2); cy = ceil(rows/2);
[u_grid, v_grid] = meshgrid(1:cols, 1:rows);
dist_sq = (u_grid - cx).^2 + (v_grid - cy).^2;
LP = exp(-dist_sq / (2 * cutoff_freq^2));
LP = ifftshift(LP); % 适配 MATLAB fft2 的频谱分布
HP = 1 - LP;

% ---------- 4) HiLo 光学切片重建 (sectioning) ----------
% CI_blur 的低频 + I_UI 的高频
CI_lowpass  = real(ifft2( fft2(CI_blur) .* LP ));
UI_highpass = real(ifft2( fft2(I_UI) .* HP ));
I_sectioned = CI_lowpass + UI_highpass;
I_sectioned = max(I_sectioned, 0); % 截断负值

% ---------- show ----------
figure('Color','w','Position',[100 100 1500 420]);
subplot(1,5,1); imshow(I0,[]); title('Step1: synth (zero-mean)');
subplot(1,5,2); imshow(SPQT_edge,[]); title('Step2: SPQT |Q| (环状结构看这里)');
subplot(1,5,3); imshow(CI,[]); title('Step2b: hypot(I0,|Q|) (可选)');
subplot(1,5,4); imshow(CI_blur,[]); title(['Step3: Gaussian \sigma=' num2str(sigma)]);
subplot(1,5,5); imshow(I_sectioned,[]); title('Step4: sectioned = blur * UI');

% ROI zoom (optional)
roi_r = floor(rows/2)-120 : floor(rows/2)+120;
roi_c = floor(cols/2)-120 : floor(cols/2)+120;

figure('Color','w','Position',[150 150 1100 420]);
subplot(1,3,1); imshow(I0(roi_r,roi_c),[]); title('ROI: synth');
subplot(1,3,2); imshow(SPQT_edge(roi_r,roi_c),[]); title('ROI: SPQT |Q|');
subplot(1,3,3); imshow(CI_blur(roi_r,roi_c),[]); title('ROI: blurred');