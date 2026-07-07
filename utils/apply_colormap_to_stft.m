% ==========================================================
% apply_colormap_to_stft.m - 将复数STFT转换为colormap RGB图像
%
% 处理流程:
%   复数STFT → abs() → [dB 或 线性] → 全局百分位归一化 → colormap查表 → uint8 RGB
%
% 输入:
%   stft_complex  - 复数STFT矩阵 [Nfft, Ncol]（单个样本）
%   colormap_name - 字符串, MATLAB支持的colormap名称
%                   (如 'parula','jet','turbo','hot','gray','bone','pink' 等)
%   norm_params   - 结构体, 包含 .lo 和 .hi (全局归一化范围)
%   normalization - 字符串, 'dB' (默认) 或 'linear'
%                   'dB':     mag = 20*log10(abs(S)), 压缩动态范围, 突出弱信号
%                   'linear': mag = abs(S), 保留原始幅度比例, 突出强信号
%
% 输出:
%   rgb_uint8     - uint8数组 [Nfft, Ncol, 3], 范围 [0, 255]
%
% 注意:
%   - 归一化使用 norm_params 指定的全局范围, 确保跨样本的颜色一致性
%   - 'gray' colormap 仍输出 [H, W, 3] (三通道相同), 维持维度统一
% ==========================================================

function rgb_uint8 = apply_colormap_to_stft(stft_complex, colormap_name, norm_params, normalization)
    if nargin < 4
        normalization = 'dB';  % 默认: dB归一化 (向后兼容)
    end

    % 1. 计算幅度, 按模式转换
    mag_abs = abs(stft_complex);
    switch lower(normalization)
        case 'db'
            mag = 20 * log10(mag_abs + eps);
        case 'linear'
            mag = mag_abs;
        otherwise
            error('apply_colormap_to_stft: 未知的归一化模式 ''%s'', 请使用 ''dB'' 或 ''linear''', normalization);
    end

    % 2. 使用全局范围线性归一化到 [0, 1]
    mag_norm = (mag - norm_params.lo) / (norm_params.hi - norm_params.lo);
    mag_norm = max(0, min(1, mag_norm));  % clip outliers

    % 3. 获取256级 colormap 查找表
    cmap = feval(colormap_name, 256);  % [256, 3] double, 范围 [0, 1]

    % 4. 归一化值映射到 colormap 索引 (1-based)
    idx = round(mag_norm * 255) + 1;   % [Nfft, Ncol] 整数索引

    % 5. 查表得到 RGB (用 idx(:) 扁平化保证兼容所有MATLAB版本, 再 reshape 回 [H,W,3])
    [H, W] = size(idx);
    rgb = reshape(cmap(idx(:), :), H, W, 3);  % [H, W, 3] double, 范围 [0, 1]

    % 6. 转换为 uint8
    rgb_uint8 = uint8(rgb * 255);
end
