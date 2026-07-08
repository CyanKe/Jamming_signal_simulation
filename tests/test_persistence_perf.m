% test_persistence_perf.m - 验证 compute_duration_spectrum 优化后的正确性和性能
clear; clc;

% 模拟真实数据规模
Nfreq = 128;
Ntime = 125;
N_samples = 100;  % 用100个样本测试，避免跑太久

fprintf('=== 测试参数 ===\n');
fprintf('Nfreq=%d, Ntime=%d, N_samples=%d\n\n', Nfreq, Ntime, N_samples);

% 生成模拟STFT复数数据
rng(42);
stft_cells = cell(N_samples, 1);
for i = 1:N_samples
    stft_cells{i} = complex(randn(Nfreq, Ntime), randn(Nfreq, Ntime));
end

num_power_bins = 64;
power_range = [-40, 10];  % 典型dB范围

% --- 正确性验证: 对比新旧结果 ---
fprintf('=== 正确性验证 (单个样本) ===\n');
test_stft = stft_cells{1};

% 新方法 (向量化)
[pers_new, edges_new, centers_new] = compute_duration_spectrum(test_stft, num_power_bins, power_range);

% 旧方法 (逐行 histcounts) - 临时实现
mag_dB = 10 * log10(abs(test_stft).^2 + eps);
pers_old = zeros(Nfreq, num_power_bins);
power_edges_old = linspace(power_range(1), power_range(2), num_power_bins + 1);
for f = 1:Nfreq
    pers_old(f, :) = histcounts(mag_dB(f, :), power_edges_old, 'Normalization', 'probability');
end

diff_max = max(abs(pers_new(:) - pers_old(:)));
fprintf('新旧结果最大差异: %.2e\n', diff_max);
if diff_max < 1e-12
    fprintf('✓ 正确性验证通过!\n\n');
else
    fprintf('✗ 存在差异, 需检查!\n\n');
end

% --- 性能对比 ---
fprintf('=== 性能对比 (%d 样本) ===\n', N_samples);

% 新方法计时
tic;
for i = 1:N_samples
    compute_duration_spectrum(stft_cells{i}, num_power_bins, power_range);
end
t_new = toc;
fprintf('向量化方法: %.3f s (%.1f ms/sample)\n', t_new, t_new/N_samples*1000);

% 旧方法计时
tic;
for i = 1:N_samples
    mag_dB = 10 * log10(abs(stft_cells{i}).^2 + eps);
    for f = 1:Nfreq
        histcounts(mag_dB(f, :), power_edges_old, 'Normalization', 'probability');
    end
end
t_old = toc;
fprintf('旧方法:      %.3f s (%.1f ms/sample)\n', t_old, t_old/N_samples*1000);
fprintf('加速比:      %.1fx\n', t_old / t_new);

% 估算 8000 样本总耗时
est_new = t_new / N_samples * 8000;
est_old = t_old / N_samples * 8000;
fprintf('\n=== 8000样本预估 ===\n');
fprintf('向量化方法: %.1f s\n', est_new);
fprintf('旧方法:      %.1f s\n', est_old);
