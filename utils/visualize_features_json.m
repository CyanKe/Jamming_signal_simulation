% ==========================================================
% visualize_features_json.m - 可视化JSON特征文件
% ==========================================================
% 读取特征JSON文件并生成可视化对比图

clear; close all; clc;

%% 设置文件路径
script_path = fileparts(mfilename('fullpath'));
root_path = fileparts(script_path);

% 默认特征文件路径（可修改）
output_subdir = '20us_multi';  % 输出子目录名
jnr_value = '+10';             % JNR值

feature_file = fullfile(root_path, 'output', output_subdir, ['JNR_', jnr_value], 'test_echo_features.json');
metadata_file = fullfile(root_path, 'output', output_subdir, ['JNR_', jnr_value], 'test_echo_metadata.json');

% 检查文件是否存在
if ~exist(feature_file, 'file')
    % 尝试查找最新的特征文件
    output_dir = fullfile(root_path, 'output');
    dirs = dir(output_dir);
    dirs = dirs([dirs.isdir]);
    dirs = dirs(~ismember({dirs.name}, {'.', '..'}));
    if ~isempty(dirs)
        % 找到最新的目录
        datenums = [dirs.datenum];
        [~, idx] = sort(datenums, 'descend');
        newest_dir = dirs(idx(1)).name;
        jnr_dirs = dir(fullfile(output_dir, newest_dir, 'JNR_*'));
        jnr_dirs = jnr_dirs([jnr_dirs.isdir]);
        if ~isempty(jnr_dirs)
            feature_file = fullfile(output_dir, newest_dir, jnr_dirs(1).name, 'test_echo_features.json');
            metadata_file = fullfile(output_dir, newest_dir, jnr_dirs(1).name, 'test_echo_metadata.json');
        end
    end
end

fprintf('读取特征文件: %s\n', feature_file);
fprintf('读取元数据文件: %s\n', metadata_file);

%% 读取特征JSON文件
fid = fopen(feature_file, 'r', 'n', 'UTF-8');
rawData = fread(fid, inf);
fclose(fid);
jsonStr = char(rawData');
features = jsondecode(jsonStr);
num_samples = length(features);

fprintf('共 %d 个样本\n\n', num_samples);

%% 读取metadata获取干扰类型
if exist(metadata_file, 'file')
    fid = fopen(metadata_file, 'r', 'n', 'UTF-8');
    rawData = fread(fid, inf);
    fclose(fid);
    jsonStr = char(rawData');
    metadata = jsondecode(jsonStr);

    signal_types = cell(num_samples, 1);
    for i = 1:num_samples
        if iscell(metadata(i).jam_types)
            signal_types{i} = strjoin(metadata(i).jam_types, '+');
        else
            signal_types{i} = metadata(i).jam_types;
        end
    end
else
    % 如果没有metadata，使用索引作为标签
    signal_types = arrayfun(@(x) sprintf('Sample_%d', x), 1:num_samples, 'UniformOutput', false);
end

%% 提取特征数据
skewness = zeros(num_samples, 1);
kurtosis = zeros(num_samples, 1);
envelope_variation = zeros(num_samples, 1);
modulation_bandwidth = zeros(num_samples, 1);
modulation_rate = zeros(num_samples, 1);
spectral_skewness = zeros(num_samples, 1);
spectral_kurtosis = zeros(num_samples, 1);
carrier_factor = zeros(num_samples, 1);
awgn_factor = zeros(num_samples, 1);
bispectrum_variance = zeros(num_samples, 1);
bispectrum_mean = zeros(num_samples, 1);
wavelet_scale_centroid = zeros(num_samples, 1);
wavelet_max_singular = zeros(num_samples, 1);
wavelet_variance = zeros(num_samples, 1);
shannon_entropy = zeros(num_samples, 1);
exponential_entropy = zeros(num_samples, 1);
norm_entropy = zeros(num_samples, 1);

% 提取每个样本的特征
for i = 1:num_samples
    f = features(i);

    skewness(i) = f.time_domain.skewness;
    kurtosis(i) = f.time_domain.kurtosis;
    envelope_variation(i) = f.time_domain.envelope_variation;
    modulation_bandwidth(i) = f.time_domain.modulation_bandwidth;
    modulation_rate(i) = f.time_domain.modulation_rate;

    spectral_skewness(i) = f.freq_domain.spectral_skewness;
    spectral_kurtosis(i) = f.freq_domain.spectral_kurtosis;
    carrier_factor(i) = f.freq_domain.carrier_factor;
    awgn_factor(i) = f.freq_domain.awgn_factor;

    bispectrum_variance(i) = f.bispectrum.bispectrum_variance;
    bispectrum_mean(i) = f.bispectrum.bispectrum_mean;

    wavelet_scale_centroid(i) = f.wavelet.scale_centroid;
    wavelet_max_singular(i) = f.wavelet.max_singular_value;
    wavelet_variance(i) = f.wavelet.variance;

    shannon_entropy(i) = f.statistical.shannon_entropy;
    exponential_entropy(i) = f.statistical.exponential_entropy;
    norm_entropy(i) = f.statistical.norm_entropy;
end

%% 获取干扰类型标签
unique_types = unique(signal_types);
num_types = length(unique_types);
fprintf('干扰类型数量: %d\n', num_types);
for i = 1:num_types
    count = sum(strcmp(signal_types, unique_types{i}));
    fprintf('  %s: %d 样本\n', unique_types{i}, count);
end

%% 生成颜色映射
colors = lines(num_types);
type_colors = zeros(num_samples, 3);
for i = 1:num_samples
    idx = find(strcmp(unique_types, signal_types{i}));
    type_colors(i, :) = colors(idx, :);
end

%% 可视化特征对比
figure('Name', '特征可视化', 'Position', [50, 50, 1600, 900]);

% 1. 时域: 偏度与峰度
subplot(2, 4, 1);
scatter(skewness, kurtosis, 50, type_colors, 'filled');
xlabel('偏度');
ylabel('峰度');
title('时域: 偏度 vs 峰度');
grid on;

% 2. 时域: 包络起伏度
subplot(2, 4, 2);
hold on;
for t = 1:num_types
    idx = strcmp(signal_types, unique_types{t});
    scatter(find(idx), envelope_variation(idx), 50, colors(t,:), 'filled');
end
xlabel('样本索引');
ylabel('包络起伏度');
title('时域: 包络起伏度');
legend(unique_types, 'Location', 'best', 'FontSize', 6);
grid on;

% 3. 时域: 调制参数
subplot(2, 4, 3);
scatter(modulation_bandwidth/1e6, modulation_rate, 50, type_colors, 'filled');
xlabel('调制带宽 (MHz)');
ylabel('调制速率');
title('时域: 调制参数');
grid on;

% 4. 频域: 载波因子与AWGN因子
subplot(2, 4, 4);
scatter(carrier_factor, awgn_factor, 50, type_colors, 'filled');
xlabel('载波因子');
ylabel('AWGN因子');
title('频域: 载波与噪声因子');
grid on;

% 5. 频域: 频谱偏度与峰度
subplot(2, 4, 5);
scatter(spectral_skewness, spectral_kurtosis, 50, type_colors, 'filled');
xlabel('频谱偏度');
ylabel('频谱峰度');
title('频域: 偏度 vs 峰度');
grid on;

% 6. 双谱域特征
subplot(2, 4, 6);
scatter(log10(bispectrum_variance+eps), log10(bispectrum_mean+eps), 50, type_colors, 'filled');
xlabel('log10(双谱方差)');
ylabel('log10(双谱均值)');
title('双谱域特征');
grid on;

% 7. 小波域特征
subplot(2, 4, 7);
scatter(wavelet_scale_centroid, wavelet_max_singular, 50, type_colors, 'filled');
xlabel('尺度重心');
ylabel('最大奇异值');
title('小波域特征');
grid on;

% 8. 统计域特征
subplot(2, 4, 8);
scatter(shannon_entropy, norm_entropy, 50, type_colors, 'filled');
xlabel('信息熵');
ylabel('范数熵');
title('统计域特征');
grid on;

sgtitle('多域特征可视化', 'FontSize', 14, 'FontWeight', 'bold');

%% 特征热力图
figure('Name', '特征矩阵热力图', 'Position', [100, 100, 1200, 600]);

% 构建特征矩阵
feature_matrix = [
    skewness, kurtosis, envelope_variation, ...
    spectral_skewness, spectral_kurtosis, carrier_factor, awgn_factor, ...
    log10(bispectrum_variance+eps), log10(bispectrum_mean+eps), ...
    wavelet_scale_centroid, wavelet_max_singular, wavelet_variance, ...
    shannon_entropy, norm_entropy
];

% 标准化
feature_matrix = (feature_matrix - mean(feature_matrix)) ./ (std(feature_matrix) + eps);

% 按类型排序
type_indices = zeros(num_samples, 1);
for i = 1:num_samples
    type_indices(i) = find(strcmp(unique_types, signal_types{i}));
end
[~, sort_idx] = sort(type_indices);
feature_matrix_sorted = feature_matrix(sort_idx, :);

% 绘制热力图
imagesc(feature_matrix_sorted');
colormap(jet);
colorbar;

feature_names = {'偏度', '峰度', '包络起伏', '频谱偏度', '频谱峰度', ...
                 '载波因子', 'AWGN因子', 'log(双谱方差)', 'log(双谱均值)', ...
                 '尺度重心', '最大奇异值', '小波方差', '信息熵', '范数熵'};
set(gca, 'YTick', 1:length(feature_names), 'YTickLabel', feature_names);
xlabel('样本索引');
ylabel('特征');
title('特征矩阵热力图 (标准化，按类型排序)');

% 添加类型分隔线
hold on;
for t = 1:num_types-1
    idx = sum(strcmp(signal_types(sort_idx(1:end)), unique_types{t}));
    line([idx+0.5, idx+0.5], [0.5, length(feature_names)+0.5], 'Color', 'w', 'LineWidth', 2);
end

%% PCA降维可视化
figure('Name', 'PCA降维可视化', 'Position', [150, 150, 1000, 400]);

% PCA
[coeff, score, ~, ~, explained] = pca(feature_matrix);

% 2D散点图
subplot(1, 2, 1);
hold on;
for t = 1:num_types
    idx = strcmp(signal_types, unique_types{t});
    scatter(score(idx, 1), score(idx, 2), 50, colors(t,:), 'filled');
end
xlabel(sprintf('PC1 (%.1f%%)', explained(1)));
ylabel(sprintf('PC2 (%.1f%%)', explained(2)));
title('PCA 2D');
legend(unique_types, 'Location', 'best', 'FontSize', 6);
grid on;

% 3D散点图
subplot(1, 2, 2);
hold on;
for t = 1:num_types
    idx = strcmp(signal_types, unique_types{t});
    scatter3(score(idx, 1), score(idx, 2), score(idx, 3), 50, colors(t,:), 'filled');
end
xlabel(sprintf('PC1 (%.1f%%)', explained(1)));
ylabel(sprintf('PC2 (%.1f%%)', explained(2)));
zlabel(sprintf('PC3 (%.1f%%)', explained(3)));
title('PCA 3D');
legend(unique_types, 'Location', 'best', 'FontSize', 6);
grid on;
view(45, 30);

sgtitle('PCA降维可视化', 'FontSize', 14, 'FontWeight', 'bold');

%% t-SNE降维可视化 (如果样本数足够)
if num_samples >= 30
    figure('Name', 't-SNE降维可视化', 'Position', [200, 200, 500, 400]);

    % t-SNE
    rng(42);  % 固定随机种子
    Y = tsne(feature_matrix, 'Algorithm', 'barneshut', 'NumDimensions', 2);

    hold on;
    for t = 1:num_types
        idx = strcmp(signal_types, unique_types{t});
        scatter(Y(idx, 1), Y(idx, 2), 50, colors(t,:), 'filled');
    end
    xlabel('t-SNE 1');
    ylabel('t-SNE 2');
    title('t-SNE 降维可视化');
    legend(unique_types, 'Location', 'best', 'FontSize', 6);
    grid on;
end

fprintf('\n可视化完成!\n');
