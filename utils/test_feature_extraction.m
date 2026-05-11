% ==========================================================
% test_feature_extraction.m - 特征提取测试脚本
% ==========================================================
% 测试多域特征提取函数的正确性
% 使用config.m中配置的干扰信号类型进行测试
%
% 特征列表:
%   时域: 矩偏度、矩峰度、包络起伏度、快速脉内调制识别参数
%   频域: 矩偏度、矩峰度、载波因子、加性高斯白噪声因子
%   双谱域: 双谱方差、双谱均值
%   小波域: 方差、均值、最大值、尺度重心、最大奇异值、中心矩特征
%   统计域: 信息熵、指数熵、范数熵

clear; close all; clc;

%% 添加路径
script_path = fileparts(mfilename('fullpath'));
root_path = fileparts(script_path);
addpath(root_path);  % config.m
addpath(fullfile(root_path, 'generators', 'base'));
addpath(fullfile(root_path, 'generators', 'deceptive'));
addpath(fullfile(root_path, 'generators', 'suppressive'));
addpath(fullfile(root_path, 'utils'));
addpath(fullfile(root_path, 'utils', 'features'));

fprintf('========================================\n');
fprintf('多域信号特征提取测试\n');
fprintf('========================================\n\n');

%% 加载配置并生成基础信号
cfg = config();
params = config_to_params(cfg);
data_num = 1;
[tx, params] = generate_0base_signal(params);

fprintf('信号参数:\n');
fprintf('  采样频率: %.0f MHz\n', params.fs/1e6);
fprintf('  脉宽: %.0f us\n', params.taup*1e6);
fprintf('  带宽: %.0f MHz\n', params.B/1e6);
fprintf('  信号长度: %d 样本\n\n', params.PRI_samp);

%% 生成各类干扰信号
JNR = 10;  % 干噪比

% 1. 纯LFM回波（无干扰）
signal_lfm = tx;

% 2. CSJ 梳状谱干扰
params_csj = params;
params_csj.JNR = JNR;
params_csj.M = 5;
params_csj.Q = 2;
signal_csj = generate_csj_jamming(tx, params_csj, data_num);

% 3. DFTJ 密集假目标干扰
params_dftj = params;
params_dftj.JNR = JNR;
params_dftj.k = 5;
signal_dftj = generate_dftj_jamming(tx, params_dftj, data_num);

% 4. ISRJ 间断采样转发干扰
params_isrj = params;
params_isrj.JNR = JNR;
params_isrj.M = 3;
params_isrj.N = 100;
signal_isrj = generate_isrj_jamming(tx, params_isrj, data_num);

% 5. C&IJ 切片交替干扰
params_cij = params;
params_cij.JNR = JNR;
params_cij.a = 100;
params_cij.b = 50;
signal_cij = generate_cij_jamming(tx, params_cij, data_num);

% 6. SMSPJ 智能噪声干扰
params_smspj = params;
params_smspj.JNR = JNR;
params_smspj.M = 5;
signal_smspj = generate_smspj_jamming(tx, params_smspj, data_num);

% 7. AJ 瞄准干扰
params_aj = params;
params_aj.JNR = JNR;
params_aj.BJ = 20e6;
params_aj.Fj = params.fc;
signal_aj = generate_ab_jamming(tx, params_aj, data_num);

% 8. BJ 阻塞干扰
params_bj = params;
params_bj.JNR = JNR;
params_bj.BJ = 50e6;
params_bj.Fj = params.fc;
signal_bj = generate_ab_jamming(tx, params_bj, data_num);

% 9. NCJ 噪声卷积干扰
params_ncj = params;
params_ncj.JNR = JNR;
signal_ncj = generate_ncj_jamming(tx, params_ncj, data_num);

% 10. NFMJ 噪声调频干扰
params_nfmj = params;
params_nfmj.JNR = JNR;
params_nfmj.BJ = 20e6;
signal_nfmj = generate_nfmj_jamming(tx, params_nfmj, data_num);

% 11. SJ 扫频干扰
params_sj = params;
params_sj.JNR = JNR;
params_sj.BJ = 20e6;
signal_sj = generate_sj_jamming(tx, params_sj, data_num);

% 12. PJ 脉冲干扰
params_pj = params;
params_pj.JNR = JNR;
params_pj.BJ = 40e6;
params_pj.fc = params.fc;
signal_pj = generate_pulse_jamming(tx, params_pj, data_num);

% 13. NPJ 噪声乘积干扰
params_npj = params;
params_npj.JNR = JNR;
signal_npj = generate_npj_jamming(tx, params_npj, data_num);

% 14. NPMJ 噪声调相干扰
params_npmj = params;
params_npmj.JNR = JNR;
params_npmj.BJ = 20e6;
params_npmj.Kp = pi/2;
signal_npmj = generate_npmj_jamming(tx, params_npmj, data_num);

% 15. NAMJ 噪声调幅干扰
params_namj = params;
params_namj.JNR = JNR;
params_namj.BJ = 20e6;
signal_namj = generate_namj_jamming(tx, params_namj, data_num);

% 测试信号列表 (生成函数输出为 [data_num, N_total]，需提取第一行)
test_signals = {
    signal_lfm(1,:), 'LFM回波', ...
    signal_csj(1,:), 'CSJ', ...
    signal_dftj(1,:), 'DFTJ', ...
    signal_isrj(1,:), 'ISRJ', ...
    signal_cij(1,:), 'C&IJ', ...
    signal_smspj(1,:), 'SMSPJ', ...
    signal_aj(1,:), 'AJ', ...
    signal_bj(1,:), 'BJ', ...
    signal_sj(1,:), 'SJ', ...
    signal_pj(1,:), 'PJ', ...
    signal_ncj(1,:), 'NCJ', ...
    signal_npj(1,:), 'NPJ', ...
    signal_nfmj(1,:), 'NFMJ', ...
    signal_npmj(1,:), 'NPMJ', ...
    signal_namj(1,:), 'NAMJ'
};

num_signals = length(test_signals) / 2;
signal_data = test_signals(1:2:end);
signal_names = test_signals(2:2:end);

%% 测试特征提取
fprintf('提取各干扰信号特征...\n\n');

all_features = cell(num_signals, 1);

for i = 1:num_signals
    fprintf('--- %s ---\n', signal_names{i});
    tic;
    all_features{i} = extract_signal_features(signal_data{i}, params.fs);
    elapsed = toc;

    fprintf('  特征提取耗时: %.4f 秒\n', elapsed);
    fprintf('  时域: 偏度=%.3f, 峰度=%.3f, 包络起伏=%.3f\n', ...
        all_features{i}.time_domain.skewness, ...
        all_features{i}.time_domain.kurtosis, ...
        all_features{i}.time_domain.envelope_variation);
    fprintf('  频域: 载波因子=%.3f, AWGN因子=%.3f\n', ...
        all_features{i}.freq_domain.carrier_factor, ...
        all_features{i}.freq_domain.awgn_factor);
    fprintf('  小波: 尺度重心=%.2f, 最大奇异值=%.2f\n', ...
        all_features{i}.wavelet.scale_centroid, ...
        all_features{i}.wavelet.max_singular_value);
    fprintf('  统计: 信息熵=%.3f\n\n', ...
        all_features{i}.statistical.shannon_entropy);
end

%% 可视化特征对比
fprintf('生成特征对比可视化...\n');

figure('Name', '干扰信号特征提取结果对比', 'Position', [50, 50, 1600, 900]);

% 1. 时域: 偏度与峰度
subplot(2, 4, 1);
bar_data = zeros(num_signals, 2);
for i = 1:num_signals
    bar_data(i, 1) = all_features{i}.time_domain.skewness;
    bar_data(i, 2) = all_features{i}.time_domain.kurtosis;
end
bar(bar_data);
set(gca, 'XTickLabel', signal_names, 'XTickLabelRotation', 45);
legend('偏度', '峰度', 'Location', 'best');
title('时域: 偏度与峰度');
grid on;

% 2. 时域: 包络起伏度
subplot(2, 4, 2);
bar_data = zeros(num_signals, 1);
for i = 1:num_signals
    bar_data(i) = all_features{i}.time_domain.envelope_variation;
end
bar(bar_data);
set(gca, 'XTickLabel', signal_names, 'XTickLabelRotation', 45);
title('时域: 包络起伏度');
grid on;

% 3. 时域: 调制参数
subplot(2, 4, 3);
bar_data = zeros(num_signals, 2);
for i = 1:num_signals
    bar_data(i, 1) = all_features{i}.time_domain.modulation_bandwidth / 1e6;
    bar_data(i, 2) = all_features{i}.time_domain.modulation_rate * 100;
end
bar(bar_data);
set(gca, 'XTickLabel', signal_names, 'XTickLabelRotation', 45);
legend('调制带宽(MHz)', '调制速率×100', 'Location', 'best');
title('时域: 调制参数');
grid on;

% 4. 频域: 偏度与峰度
subplot(2, 4, 4);
bar_data = zeros(num_signals, 2);
for i = 1:num_signals
    bar_data(i, 1) = all_features{i}.freq_domain.spectral_skewness;
    bar_data(i, 2) = all_features{i}.freq_domain.spectral_kurtosis;
end
bar(bar_data);
set(gca, 'XTickLabel', signal_names, 'XTickLabelRotation', 45);
legend('频谱偏度', '频谱峰度', 'Location', 'best');
title('频域: 偏度与峰度');
grid on;

% 5. 频域: 载波因子与AWGN因子
subplot(2, 4, 5);
bar_data = zeros(num_signals, 2);
for i = 1:num_signals
    bar_data(i, 1) = all_features{i}.freq_domain.carrier_factor;
    bar_data(i, 2) = all_features{i}.freq_domain.awgn_factor;
end
bar(bar_data);
set(gca, 'XTickLabel', signal_names, 'XTickLabelRotation', 45);
legend('载波因子', 'AWGN因子', 'Location', 'best');
title('频域: 载波与噪声因子');
grid on;

% 6. 双谱域特征
subplot(2, 4, 6);
bar_data = zeros(num_signals, 2);
for i = 1:num_signals
    bar_data(i, 1) = log10(all_features{i}.bispectrum.bispectrum_variance + eps);
    bar_data(i, 2) = log10(all_features{i}.bispectrum.bispectrum_mean + eps);
end
bar(bar_data);
set(gca, 'XTickLabel', signal_names, 'XTickLabelRotation', 45);
legend('log10(方差)', 'log10(均值)', 'Location', 'best');
title('双谱域特征 (对数)');
grid on;

% 7. 小波域特征
subplot(2, 4, 7);
bar_data = zeros(num_signals, 3);
for i = 1:num_signals
    bar_data(i, 1) = all_features{i}.wavelet.scale_centroid;
    bar_data(i, 2) = all_features{i}.wavelet.max_singular_value;
    bar_data(i, 3) = all_features{i}.wavelet.variance;
end
bar(bar_data);
set(gca, 'XTickLabel', signal_names, 'XTickLabelRotation', 45);
legend('尺度重心', '最大奇异值', '方差', 'Location', 'best');
title('小波域特征');
grid on;

% 8. 统计域特征
subplot(2, 4, 8);
bar_data = zeros(num_signals, 3);
for i = 1:num_signals
    bar_data(i, 1) = all_features{i}.statistical.shannon_entropy;
    bar_data(i, 2) = all_features{i}.statistical.exponential_entropy;
    bar_data(i, 3) = all_features{i}.statistical.norm_entropy;
end
bar(bar_data);
set(gca, 'XTickLabel', signal_names, 'XTickLabelRotation', 45);
legend('信息熵', '指数熵', '范数熵', 'Location', 'best');
title('统计域特征');
grid on;

sgtitle('干扰信号多域特征提取结果对比', 'FontSize', 14, 'FontWeight', 'bold');

%% 可视化信号波形
figure('Name', '干扰信号波形对比', 'Position', [50, 50, 1800, 800]);

t_axis = params.t_total * 1e6;  % 时间轴 us
plot_range = max(1, params.pos - 500) : length( params.t_total );% min(params.PRI_samp, params.pos + params.Ntau + 500);  % LFM脉冲附近

for i = 1:num_signals
    subplot(3, 5, i);
    plot(t_axis(plot_range), real(signal_data{i}(plot_range)));
    xlabel('时间 (us)');
    ylabel('幅度');
    title(signal_names{i});
    grid on;
end

sgtitle('干扰信号时域波形', 'FontSize', 14, 'FontWeight', 'bold');

%% 保存测试结果
fprintf('保存测试结果...\n');

% 构建结果结构体
results = struct();
for i = 1:num_signals
    results(i).signal_type = signal_names{i};
    results(i).features = all_features{i};
end

% 保存为JSON
output_path = fullfile(script_path, 'test_features_output.json');
jsonStr = jsonencode(results);
fid = fopen(output_path, 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonStr);
fclose(fid);
fprintf('测试结果已保存到: %s\n', output_path);

fprintf('\n========================================\n');
fprintf('测试完成!\n');
fprintf('========================================\n');
