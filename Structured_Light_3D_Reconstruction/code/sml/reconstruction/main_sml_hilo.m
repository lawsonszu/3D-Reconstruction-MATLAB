%% HiLo + SML(5x5) 轴向扫描三维重建（整理版）
% 目标：在“信息充足区域”尽量还原真实光滑形貌（减少坑洼/同心圈）
% 核心流程：
%   Step1 读取并排序Z层数据
%   Step2 每层：SML对比度图 -> HiLo光学切片 -> log融合，构建轴向响应体 vol
%   Step3 对 vol 做Z向平滑，抑制峰位抖动
%   Step4 5点log-二次拟合做亚层峰值定位（重点：消同心圈/台阶纹）
%   Step5 后处理：去离群 + 置信度引导的保边平滑 + 加权融合
%   Step6 可视化

clc; clear; close all;

%% =============== 参数区（只建议你主要改这里）===============
data_root   = 'C:\lab_training_data\50-150';   % 数据根目录（子文件夹名为Z值）
name_V      = '1.png';
name_H      = '5.png';
name_UI     = '9.png';

% 裁剪区域（根据你实验设置）
y_start = 600;
y_end   = 1600;

% SML对比度图的XY平滑（对轴向响应稳定性很关键）
sigma_xy = 16;

% HiLo 截止频率（频域高/低通分割尺度）
cutoff_freq = 50;

% 融合权重：w*log(contrast) + (1-w)*log(sectioned)
w_fuse = 0.6;

% 只在Z方向平滑（抑制峰位跳层/抖动）
sigma_z = 1.5;    % 1.2~2.0 常用

% Step4：峰附近取 5 层（固定 -2..+2）
% Step4用log-二次拟合定位峰值，不需要 gamma（gamma是soft-argmax那套）

% 是否挖空（你现在不需要，保持 false）
use_mask = false;
mask_prc = 10;    % 如果 use_mask=true，用峰强度分位数筛掉弱信息点（10~30）

% Step5：后处理参数
med_win = [5 5];          % 离群检测的中值窗口
outlier_k = 3;            % 离群阈值（k*sigma_r），2.5~4
conf_pow = 0.6;           % 置信度映射非线性（0.5~1）
guided_win = [41 41];     % guided filter 邻域（31~61）
guided_smooth = 1e-2;     % guided filter 平滑强度（1e-3~1e-1）

% 可视化范围（仅影响显示，不会改数据）
show_range = [60 140];    % 你原来用的显示范围；想自动就把下面注释打开
% show_range = [];        % 设为空则自动
step_show = 2;            % 3D显示下采样
%% ============================================================


%% Step1：扫描并排序所有Z层文件夹
dir_list = dir(fullfile(data_root, '*'));
folder_nums = str2double({dir_list.name});
valid_idx = ~isnan(folder_nums);
sorted_z_vals = folder_nums(valid_idx);
sorted_dirs = dir_list(valid_idx);
[sorted_z_vals, order] = sort(sorted_z_vals);
sorted_dirs = sorted_dirs(order);

num_layers = numel(sorted_dirs);
if num_layers == 0
    error('未找到有效的Z文件夹，请检查路径：%s', data_root);
end
fprintf('检测到 %d 层数据 (Z: %g -> %g)\n', num_layers, sorted_z_vals(1), sorted_z_vals(end));

dz = mean(diff(sorted_z_vals));
fprintf('估算Z层间距 dz = %.4f\n', dz);

%% Step1.1：读取首层确定裁剪尺寸
first_path = fullfile(data_root, sorted_dirs(1).name, name_UI);
temp_img = imread(first_path);
if size(temp_img, 1) < y_end
    error('图像高度不足 y_end=%d，当前高度=%d', y_end, size(temp_img,1));
end

rows = y_end - y_start + 1;
cols = size(temp_img, 2);
fprintf('裁剪区域 Y[%d-%d] -> 新尺寸 %dx%d\n', y_start, y_end, rows, cols);

%% Step1.2：预计算 HiLo 频域滤波器（只跟ROI大小有关）
cx = ceil(cols/2); cy = ceil(rows/2);
[u_grid, v_grid] = meshgrid(1:cols, 1:rows);
dist_sq = (u_grid - cx).^2 + (v_grid - cy).^2;

LP = exp(-dist_sq / (2 * cutoff_freq^2));
LP = ifftshift(LP);
HP = 1 - LP;

%% Step2：逐层计算轴向响应，构建体数据 vol_response(:,:,k)
% 用 NaN 初始化：避免跳过层时留下 0 干扰后续处理
vol_response = nan(rows, cols, num_layers);
valid_layer  = false(1, num_layers);

fprintf('开始构建轴向响应体 vol_response ...\n');
for k = 1:num_layers
    z_val = sorted_z_vals(k);
    current_path = fullfile(data_root, sorted_dirs(k).name);

    try
        full_V  = double(imread(fullfile(current_path, name_V)));
        full_H  = double(imread(fullfile(current_path, name_H)));
        full_UI = double(imread(fullfile(current_path, name_UI)));
    catch
        warning('跳过层 Z=%g：读取图片失败', z_val);
        continue;
    end

    % 裁剪 ROI
    I_V  = full_V (y_start:y_end, :);
    I_H  = full_H (y_start:y_end, :);
    I_UI = full_UI(y_start:y_end, :);

    % ---- Step2.1：SML(5x5) 计算对比度图（FV思想）----
    dV = I_V - I_UI;
    dH = I_H - I_UI;
    CI = 0.5 * (SML5(dV) + SML5(dH));
    CI = imgaussfilt(CI, sigma_xy);

    % ---- Step2.2：HiLo 光学切片（对比度低频 + 均匀照明高频）----
    Isec = real(ifft2( fft2(CI).*LP + fft2(I_UI).*HP ));
    Isec = max(Isec, 0);

    % ---- Step2.3：log融合（保留Z向相对关系，避免每层独立归一化）----
    resp = w_fuse*log1p(CI) + (1-w_fuse)*log1p(Isec);

    vol_response(:,:,k) = resp;
    valid_layer(k) = true;

    if mod(k, 10) == 0
        fprintf('  已处理 %d/%d (Z=%g)\n', k, num_layers, z_val);
    end
end

% 剔除无效层
vol_response  = vol_response(:,:,valid_layer);
sorted_z_vals = sorted_z_vals(valid_layer);
num_layers    = sum(valid_layer);

if num_layers < 5
    error('有效层数不足 5 层（当前=%d），无法做5点拟合。', num_layers);
end

dz = mean(diff(sorted_z_vals));
fprintf('有效层数=%d，更新dz=%.4f\n', num_layers, dz);

%% Step3：Z向补齐 + 仅Z向高斯平滑（抑制峰位抖动/跳层）
if any(isnan(vol_response(:)))
    vol_response = fillmissing(vol_response, 'linear', 3, 'EndValues', 'nearest');
end

g = gauss1d(sigma_z);
vol_response = convn(vol_response, reshape(g,1,1,[]), 'same');

%% Step4：5点 log-二次拟合（亚层峰值定位，减少同心圈/台阶纹）
fprintf('Step4: 5点log-二次拟合进行亚层峰值定位...\n');

% 先找离散峰所在层（作为中心层 idx_0）
[~, idx_0] = max(vol_response, [], 3);

% ===== 关键：先把5点二次拟合的伪逆矩阵 P 算出来（常数）=====
x = [-2 -1 0 1 2]';
X = [x.^2 x ones(5,1)];
P = pinv(X);          % 3x5 常数矩阵
Pa = P(1,:);          % 对应 a 的线性组合系数 (1x5)
Pb = P(2,:);          % 对应 b 的线性组合系数 (1x5)

% ===== 更省内存的索引方式（不造 ndgrid / sub2ind 大矩阵）=====
N = rows * cols;
pix  = (1:N)';        % 2D线性索引（列优先展开）
idx0v = idx_0(:);

idx_m2 = max(idx0v-2, 1);
idx_m1 = max(idx0v-1, 1);
idx_p1 = min(idx0v+1, num_layers);
idx_p2 = min(idx0v+2, num_layers);

lin0  = pix + (idx0v -1) * N;
linm2 = pix + (idx_m2-1) * N;
linm1 = pix + (idx_m1-1) * N;
linp1 = pix + (idx_p1-1) * N;
linp2 = pix + (idx_p2-1) * N;

r0  = vol_response(lin0);
rm2 = vol_response(linm2);
rm1 = vol_response(linm1);
rp1 = vol_response(linp1);
rp2 = vol_response(linp2);

peak_strength = reshape(r0, rows, cols);

Lm2 = log(rm2 + eps);
Lm1 = log(rm1 + eps);
L0  = log(r0  + eps);
Lp1 = log(rp1 + eps);
Lp2 = log(rp2 + eps);

% 直接线性组合得到 a,b（避免构造 5xN 的 Y）
a = Pa(1)*Lm2 + Pa(2)*Lm1 + Pa(3)*L0 + Pa(4)*Lp1 + Pa(5)*Lp2;
b = Pb(1)*Lm2 + Pb(2)*Lm1 + Pb(3)*L0 + Pb(4)*Lp1 + Pb(5)*Lp2;

delta = -b ./ (2*a);
bad = ~isfinite(delta) | (a >= 0) | (abs(a) < 1e-10);
delta(bad) = 0;
delta = max(min(delta, 2), -2);

delta = reshape(delta, rows, cols);

% 每个像素的中心层 z（注意：这是“逐像素”的，不要用 sorted_z_vals(idx_0) 直接索引矩阵）
z0_center = reshape(sorted_z_vals(idx0v), rows, cols);
height_map = z0_center + delta * dz;
% 可选：如果你以后想挖掉弱信息区域（你现在不需要）
if use_mask
    thr = prctile(peak_strength(:), mask_prc);
    height_map(peak_strength <= thr) = NaN;
end

%% Step5：后处理（不挖空）：去离群 + 置信度引导保边平滑 + 加权融合
fprintf('Step5: 后处理（保边平滑 + 加权融合）...\n');

hm0 = height_map;
nanmask = isnan(hm0);
hm = fillmissing(hm0, 'nearest');   % 保证滤波稳定

% 5.1 离群点替换：用中值图做参考，只替换明显尖点
hm_med = medfilt2(hm, med_win, 'symmetric');
res = hm - hm_med;
sigma_r = 1.4826 * mad(res(:), 1);
outlier = abs(res) > outlier_k * sigma_r;
hm(outlier) = hm_med(outlier);

% 5.2 置信度图（用峰强度），信息足区域置信度高
conf = mat2gray(peak_strength);
conf = conf.^conf_pow;
conf = max(conf, 0.05);

% 5.3 guided filter（优先），否则双边/高斯兜底
guide = conf;
if exist('imguidedfilter', 'file') == 2
    hm_s = imguidedfilter(hm, guide, ...
        'NeighborhoodSize', guided_win, ...
        'DegreeOfSmoothing', guided_smooth);
elseif exist('imbilatfilt', 'file') == 2
    hm_s = imbilatfilt(hm, 2.0, 15);
else
    hm_s = imgaussfilt(hm, 1.0);
end

% 5.4 加权融合：信息足区域更“保真”，弱信息区域更“顺滑”
alpha = 0.75*conf + 0.20;
alpha = min(max(alpha, 0.2), 0.95);
height_map = alpha .* hm + (1 - alpha) .* hm_s;

% 如果你希望保留原始NaN位置为空洞，取消下一行注释：
% height_map(nanmask) = NaN;

%% Step6：可视化
% 构建参数信息字符串
param_str = sprintf('σ_{xy}=%.1f, σ_z=%.1f, c_{freq}=%d, w_{fuse}=%.2f', ...
    sigma_xy, sigma_z, cutoff_freq, w_fuse);
input_info = sprintf('V=%s, H=%s, UI=%s', name_V, name_H, name_UI);
main_title = sprintf('FV(SML)+HiLo重建 | %s | %s', input_info, param_str);

figure('Name', main_title, ...
    'Color', 'w', 'Position', [80 120 1250 520]);

% 左：2D 深度图
subplot(1,2,1);
imagesc(height_map);
axis image; colormap jet; colorbar;
title(sprintf('2D深度图\n%s', param_str));
xlabel('X Pixel'); ylabel('Y Pixel (Cropped)');
% 显示范围（仅显示）
if ~isempty(show_range)
    caxis(show_range);
end

% 右：3D 表面
subplot(1,2,2);
[Xs, Ys] = meshgrid(1:step_show:cols, 1:step_show:rows);
Zs = height_map(1:step_show:end, 1:step_show:end);

% 【修改1】只保留一次 surf 调用，防止属性被覆盖
h = surf(Xs, Ys, Zs, Zs, 'EdgeColor','none');
shading interp;

% 【修改2】先设置坐标轴范围、视角和 Z 轴反转
axis tight;
set(gca, 'ZDir', 'reverse'); 
view(-45, 60);
daspect([1 1 0.15]);   

% 设置光照材质
lighting gouraud;
camlight headlight; % 主光源（现在能照亮顶部了）
camlight right;     % 添加一个侧光源增加立体感

set(h, 'AmbientStrength', 0.6, ...    % 环境光
       'DiffuseStrength', 0.9, ...    % 漫反射
       'SpecularStrength', 0.1);      % 高光（保持较低避免刺眼）
material dull;
colormap(jet);
grid on; % 开启网格可以更好地看出 XY 比例关系

title(sprintf('3D重建\n%s', param_str));
xlabel('X Pixel'); ylabel('Y Pixel'); zlabel('Height (μm)');
if ~isempty(show_range)
    zlim(show_range);
end
if ~isempty(show_range)
    zlim(show_range);
end
view(-45, 60);

disp('完成：重建 + 后处理 + 可视化');

%% ====================== 函数区 ======================
function CI = SML5(img)
% SML5：Modified Laplacian + 5x5窗口求和（FV/SML对比度算子）
    ML = abs(imfilter(img, [-1 2 -1], 'replicate')) + ...
         abs(imfilter(img, [-1; 2; -1], 'replicate'));
    CI = imfilter(ML, ones(5,5), 'replicate');
end

function g = gauss1d(sigma)
% 生成 1D 高斯核（用于只在Z方向平滑）
    r = max(1, ceil(3*sigma));
    x = -r:r;
    g = exp(-(x.^2)/(2*sigma^2));
    g = g / sum(g);
end