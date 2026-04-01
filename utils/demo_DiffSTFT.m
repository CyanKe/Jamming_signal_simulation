% ==========================================================
% demo_DiffSTFT.m - 可微短时傅里叶变换演示脚本
% ==========================================================
% 演示DiffSTFT和DiffSTFT_Advanced的使用方法
% 对比传统STFT与可微STFT的差异

clear; close all; clc;

%% 参数设置
fs = 1000;              % 采样频率 (Hz)
duration = 2;           % 信号时长 (s)
t = 0:1/fs:duration-1/fs;

%% 生成测试信号
% 信号1: 线性调频信号 (Chirp)
f0 = 50; f1 = 300;
signal1 = chirp(t, f0, duration, f1);

% 信号2: 多分量信号
signal2 = sin(2*pi*100*t) + 0.5*sin(2*pi*200*t) + 0.3*sin(2*pi*350*t);

% 信号3: 非平稳信号（瞬时频率变化）
signal3 = zeros(size(t));
for i = 1:length(t)
    if t(i) < 0.5
        signal3(i) = sin(2*pi*50*t(i));
    elseif t(i) < 1.0
        signal3(i) = sin(2*pi*150*t(i));
    else
        signal3(i) = sin(2*pi*300*t(i));
    end
end

% 信号4: 调幅调频信号
signal4 = (1 + 0.5*sin(2*pi*10*t)) .* sin(2*pi*200*t + 50*sin(2*pi*5*t));

% 选择测试信号
y = signal4;
signal_name = 'AM-FM Signal';

%% ============== DiffSTFT 基础用法 ==============
fprintf('========================================\n');
fprintf('DiffSTFT 基础用法演示\n');
fprintf('========================================\n');

% 基础STFT
win_len = 256;
hop_len = 64;

tic;
[S_basic, F_basic, T_basic] = DiffSTFT(y, fs, win_len, hop_len, 'hann', false);
time_basic = toc;

fprintf('基础STFT:\n');
fprintf('  窗长: %d, 步长: %d\n', win_len, hop_len);
fprintf('  输出尺寸: %d x %d\n', size(S_basic, 1), size(S_basic, 2));
fprintf('  计算时间: %.4f 秒\n', time_basic);

% 自适应STFT
tic;
[S_adaptive, F_adaptive, T_adaptive] = DiffSTFT(y, fs, win_len, hop_len, 'hann', true);
time_adaptive = toc;

fprintf('\n自适应STFT:\n');
fprintf('  计算时间: %.4f 秒\n', time_adaptive);

%% ============== DiffSTFT_Advanced 高级用法 ==============
fprintf('\n========================================\n');
fprintf('DiffSTFT_Advanced 高级用法演示\n');
fprintf('========================================\n');

% 配置参数
params = struct();
params.win_len = 256;
params.hop_len = 64;
params.win_type = 'hann';
params.phase_correction = true;
params.normalize = false;

tic;
[S_adv, F_adv, T_adv, result] = DiffSTFT_Advanced(y, fs, params);
time_adv = toc;

fprintf('高级STFT:\n');
fprintf('  窗长: %d, 步长: %d\n', params.win_len, params.hop_len);
fprintf('  相位校正: %s\n', mat2str(params.phase_correction));
fprintf('  输出尺寸: %d x %d\n', size(S_adv, 1), size(S_adv, 2));
fprintf('  计算时间: %.4f 秒\n', time_adv);

%% ============== 特征提取 ==============
fprintf('\n========================================\n');
fprintf('特征提取演示\n');
fprintf('========================================\n');

features = learn_features(S_adv, F_adv, T_adv, fs);

fprintf('主要特征:\n');
fprintf('  频谱质心: %.2f Hz\n', features.spectral_centroid);
fprintf('  频谱带宽: %.2f Hz\n', features.spectral_bandwidth);
fprintf('  频谱平坦度: %.4f\n', features.spectral_flatness);
fprintf('  85%%滚降频率: %.2f Hz\n', features.spectral_rolloff_85);
fprintf('  时频熵: %.4f\n', features.tf_entropy);
fprintf('  主频率: %.2f Hz\n', features.peak_freq);
fprintf('  显著分量数: %d\n', features.num_significant_components);

%% ============== 可视化 ==============
figure('Name', 'DiffSTFT Demo', 'Position', [100, 100, 1400, 900]);

% 子图1: 原始信号
subplot(3, 3, 1);
plot(t, y, 'b');
xlabel('时间 (s)');
ylabel('幅度');
title(sprintf('原始信号: %s', signal_name));
grid on;
xlim([0, duration]);

% 子图2: 基础STFT时频图
subplot(3, 3, 2);
imagesc(T_basic, F_basic, 20*log10(S_basic + eps));
axis xy;
xlabel('时间 (s)');
ylabel('频率 (Hz)');
title('基础STFT时频图');
colorbar;

% 子图3: 自适应STFT时频图
subplot(3, 3, 3);
imagesc(T_adaptive, F_adaptive, 20*log10(S_adaptive + eps));
axis xy;
xlabel('时间 (s)');
ylabel('频率 (Hz)');
title('自适应STFT时频图');
colorbar;

% 子图4: 高级STFT时频图
subplot(3, 3, 4);
imagesc(T_adv, F_adv, 20*log10(S_adv + eps));
axis xy;
xlabel('时间 (s)');
ylabel('频率 (Hz)');
title('高级STFT时频图 (相位校正)');
colorbar;

% 子图5: 相位谱
subplot(3, 3, 5);
imagesc(T_adv, F_adv, result.phase);
axis xy;
xlabel('时间 (s)');
ylabel('频率 (Hz)');
title('相位谱');
colormap(gca, 'hsv');
colorbar;

% 子图6: 平均频谱
subplot(3, 3, 6);
plot(F_adv, mean(S_adv, 2), 'b', 'LineWidth', 1.5);
xlabel('频率 (Hz)');
ylabel('幅度');
title('平均频谱');
grid on;

% 子图7: 瞬时频率
subplot(3, 3, 7);
plot(T_adv, features.instantaneous_freq, 'r', 'LineWidth', 1.5);
xlabel('时间 (s)');
ylabel('瞬时频率 (Hz)');
title('瞬时频率估计');
grid on;

% 子图8: 能量包络
subplot(3, 3, 8);
plot(T_adv, features.energy_envelope, 'g', 'LineWidth', 1.5);
xlabel('时间 (s)');
ylabel('能量');
title('能量包络');
grid on;

% 子图9: 特征统计
subplot(3, 3, 9);
bar([features.spectral_centroid, features.spectral_bandwidth, ...
     features.spectral_rolloff_85, features.spectral_rolloff_95]);
set(gca, 'XTickLabel', {'质心', '带宽', '85%滚降', '95%滚降'});
ylabel('频率 (Hz)');
title('频域特征统计');
grid on;

sgtitle('可微短时傅里叶变换 (DiffSTFT) 演示', 'FontSize', 14, 'FontWeight', 'bold');

%% ============== 与CWD对比 ==============
fprintf('\n========================================\n');
fprintf('与传统CWD时频分析对比\n');
fprintf('========================================\n');

% 计算CWD
tic;
[C_cwd, F_cwd, T_cwd] = CWD(y, fs, 1, 256, 128);
time_cwd = toc;

fprintf('CWD:\n');
fprintf('  输出尺寸: %d x %d\n', size(C_cwd, 1), size(C_cwd, 2));
fprintf('  计算时间: %.4f 秒\n', time_cwd);

% 对比图
figure('Name', 'DiffSTFT vs CWD', 'Position', [100, 100, 1200, 500]);

subplot(1, 2, 1);
imagesc(T_adv, F_adv, 20*log10(S_adv + eps));
axis xy;
xlabel('时间 (s)');
ylabel('频率 (Hz)');
title(sprintf('DiffSTFT (%.4f s)', time_adv));
colorbar;

subplot(1, 2, 2);
imagesc(T_cwd, F_cwd, abs(C_cwd));
axis xy;
xlabel('时间 (s)');
ylabel('频率 (Hz)');
title(sprintf('CWD (%.4f s)', time_cwd));
colorbar;

sgtitle('DiffSTFT 与 CWD 时频分析对比', 'FontSize', 14, 'FontWeight', 'bold');

%% ============== 自适应分解演示 ==============
fprintf('\n========================================\n');
fprintf('自适应信号分解演示\n');
fprintf('========================================\n');

% 使用多分量信号
y_multi = signal2;
fprintf('测试信号: 多分量正弦信号\n');
fprintf('  分量: 100Hz, 200Hz, 350Hz\n');

[components, residual, info] = adaptive_decompose(y_multi, fs, 5, 256, 64);

fprintf('分解结果:\n');
fprintf('  提取分量数: %d\n', info.num_components);
for i = 1:info.num_components
    fprintf('  分量 %d: 主频 = %.2f Hz, 能量 = %.4f\n', ...
        i, info(i).dominant_freq, info(i).energy);
end

% 显示分解结果
figure('Name', 'Adaptive Decomposition', 'Position', [100, 100, 1000, 700]);

subplot(3, 2, 1);
plot(t, y_multi, 'b');
xlabel('时间 (s)');
ylabel('幅度');
title('原始多分量信号');
grid on;

for i = 1:min(3, size(components, 2))
    subplot(3, 2, i+1);
    plot(t, components(:, i), 'r');
    xlabel('时间 (s)');
    ylabel('幅度');
    title(sprintf('提取分量 %d (%.1f Hz)', i, info(i).dominant_freq));
    grid on;
end

subplot(3, 2, 5);
plot(t, residual, 'g');
xlabel('时间 (s)');
ylabel('幅度');
title('残差信号');
grid on;

subplot(3, 2, 6);
stem([info.dominant_freq], [info.energy], 'filled');
xlabel('频率 (Hz)');
ylabel('能量');
title('提取分量能量分布');
grid on;

sgtitle('自适应信号分解结果', 'FontSize', 14, 'FontWeight', 'bold');

%% ============== 不同窗函数对比 ==============
fprintf('\n========================================\n');
fprintf('不同窗函数对比\n');
fprintf('========================================\n');

window_types = {'hann', 'hamming', 'gaussian'};
win_colors = {'b', 'r', 'g'};

figure('Name', 'Window Comparison', 'Position', [100, 100, 1200, 400]);

for i = 1:length(window_types)
    [S_win, F_win, T_win] = DiffSTFT(y, fs, win_len, hop_len, window_types{i}, false);

    subplot(1, 3, i);
    imagesc(T_win, F_win, 20*log10(S_win + eps));
    axis xy;
    xlabel('时间 (s)');
    ylabel('频率 (Hz)');
    title(sprintf('%s 窗', window_types{i}));
    colorbar;

    fprintf('%s 窗: 分辨率 = %.2f Hz\n', window_types{i}, fs/win_len);
end

sgtitle('不同窗函数的时频分析结果', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('\n========================================\n');
fprintf('演示完成!\n');
fprintf('========================================\n');