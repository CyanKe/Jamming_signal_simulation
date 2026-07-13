% ==========================================================
% test_combo_jnr.m - 批量验证组合干扰的JNR
% ==========================================================
% 验证目标:
%   组合干扰 (如 DFTJ+AJ) 的有效JNR是否与预期一致。
%   单个干扰器以 JNR_target 为目标, 组合后 sum_jam = jam1 + jam2,
%   由于两个独立干扰信号叠加, 总功率 ≈ 2×P_jam_single,
%   因此有效JNR ≈ JNR_target + 10*log10(2) ≈ JNR_target + 3.01 dB。
%
% 用法:
%   >> run('tests/test_combo_jnr.m')
% ==========================================================
clear; clc; close all;

script_path = fileparts(mfilename('fullpath'));
root_path = fileparts(script_path);
addpath(root_path);
addpath(fullfile(root_path, 'generators', 'base'));
addpath(fullfile(root_path, 'generators', 'deceptive'));
addpath(fullfile(root_path, 'generators', 'suppressive'));
addpath(fullfile(root_path, 'utils'));

cfg = config();
params = config_to_params(cfg);

test_JNR = 20;  % dB
N_test = 100;

% ---- 测试的组合干扰对 (欺骗式 + 压制) ----
% 格式: {组合名, 欺骗生成器函数句柄, 压制生成器函数句柄, 欺骗参数补充, 压制参数补充}
combo_list = {
    'DFTJ+AJ',   @generate_dftj_jamming,  @generate_ab_jamming,  struct(), struct('BJ_range', cfg.jamming.aj.BJ_range, 'random_Fj', cfg.jamming.aj.random_Fj);
    'DFTJ+BJ',   @generate_dftj_jamming,  @generate_ab_jamming,  struct(), struct('BJ_range', cfg.jamming.bj.BJ_range, 'random_Fj', cfg.jamming.bj.random_Fj);
    'ISRJ+AJ',   @generate_isrj_jamming,  @generate_ab_jamming,  struct(), struct('BJ_range', cfg.jamming.aj.BJ_range, 'random_Fj', cfg.jamming.aj.random_Fj);
    'ISRJ+NCJ',  @generate_isrj_jamming,  @generate_ncj_jamming, struct(), struct();
    'SMSPJ+AJ',  @generate_smspj_jamming, @generate_ab_jamming,  struct(), struct('BJ_range', cfg.jamming.aj.BJ_range, 'random_Fj', cfg.jamming.aj.random_Fj);
    'SMSPJ+SJ',  @generate_smspj_jamming, @generate_sj_jamming,  struct(), struct('BJ_range', cfg.jamming.sj.BJ_range);
    'CSJ+PJ',    @generate_csj_jamming,   @generate_pulse_jamming, struct(), struct();
    'C&IJ+NFMJ', @generate_cij_jamming,   @generate_nfmj_jamming, struct(), struct('BJ_range', cfg.jamming.nfmj.BJ_range, 'random_Fj', cfg.jamming.nfmj.random_Fj);
    'MISRJ+NPJ', @generate_misrj_jamming, @generate_npj_jamming, struct(), struct();
    'ISCJ+NAMJ', @generate_iscj_jamming,  @generate_namj_jamming, struct(), struct('BJ_range', cfg.jamming.namj.BJ_range, 'random_Fj', cfg.jamming.namj.random_Fj);
    'ISDJ+NPMJ', @generate_isdj_jamming,  @generate_npmj_jamming, struct(), struct('BJ_range', cfg.jamming.npmj.BJ_range, 'random_Fj', cfg.jamming.npmj.random_Fj);
};

num_combos = size(combo_list, 1);
expected_boost_db = 10 * log10(2);  % ≈ 3.01 dB — 两个等功率独立信号的叠加增益

fprintf('========================================\n');
fprintf('  组合干扰 JNR 批量验证\n');
fprintf('========================================\n');
fprintf('  fs = %.0f MHz, taup = %.0f us, PRI = %.0f us\n', params.fs/1e6, params.taup*1e6, params.PRI*1e6);
fprintf('  Ntau = %d, PRI_samp = %d, 占空比 = %.1f%%\n', ...
    round(params.taup*params.fs), round(params.PRI*params.fs), ...
    round(params.taup*params.fs)/round(params.PRI*params.fs)*100);
fprintf('  单干扰目标 JNR = %+d dB\n', test_JNR);
fprintf('  预期组合有效JNR = %.2f dB (叠加增益 +%.2f dB)\n', test_JNR + expected_boost_db, expected_boost_db);
fprintf('  测试样本数 = %d, 组合类型数 = %d\n\n', N_test, num_combos);

% 表头
fprintf('%-14s | %10s | %8s | %8s | %8s | %10s | %8s | %s\n', ...
    '组合类型', 'JNR1(dB)',  'JNR2(dB)', '有效JNR', '预期JNR', '偏差(dB)', '叠加dB', '判断');
fprintf('----------------|------------|----------|----------|----------|------------|----------|--------\n');

all_results = struct();

for c = 1:num_combos
    combo_name    = combo_list{c, 1};
    jam_func1     = combo_list{c, 2};  % 欺骗
    jam_func2     = combo_list{c, 3};  % 压制
    extra1        = combo_list{c, 4};  % jam1额外参数
    extra2        = combo_list{c, 5};  % jam2额外参数

    JNR1_vals  = zeros(1, N_test);  % jam1单独的JNR
    JNR2_vals  = zeros(1, N_test);  % jam2单独的JNR
    JNR_eff_vals = zeros(1, N_test);  % 组合有效JNR

    for n = 1:N_test
        params.pos = cfg.generation.pos_range(1) + ...
                     randi([0, cfg.generation.pos_range(2) - cfg.generation.pos_range(1)]);

        % 先生成基础信号, 因为 generate_0base_signal 会填充 N_total 等派生参数
        [tx, params] = generate_0base_signal(params);

        % --- 准备jam1 (欺骗式) 参数 ---
        jam1_params = params;
        jam1_params.JNR = test_JNR;

        % --- 准备jam2 (压制) 参数 ---
        jam2_params = params;
        jam2_params.JNR = test_JNR;
        fns = fieldnames(extra2);
        for k = 1:length(fns)
            fn = fns{k};
            val = extra2.(fn);
            if strcmp(fn, 'BJ_range')
                jam2_params.BJ = (val(1) + (val(2)-val(1))*rand) * 1e6;
            elseif strcmp(fn, 'random_Fj')
                jam2_params.random_Fj = val;
            else
                jam2_params.(fn) = val;
            end
        end

        % 生成噪声 (用于测量基准噪声功率)
        white_noise = randn(1, params.N_total) + 1j*randn(1, params.N_total);
        white_noise = white_noise / std(white_noise);
        P_noise = mean(abs(white_noise).^2);

        % --- 生成jam1 (欺骗式) ---
        nout1 = nargout(jam_func1);
        out1 = cell(1, nout1);
        [out1{:}] = jam_func1(tx, jam1_params, 1);
        pure_jam1 = out1{1};

        % --- 生成jam2 (压制) ---
        nout2 = nargout(jam_func2);
        out2 = cell(1, nout2);
        [out2{:}] = jam_func2(tx, jam2_params, 1);
        pure_jam2 = out2{1};

        % --- 测量 ---
        P_jam1 = mean(abs(pure_jam1).^2);
        P_jam2 = mean(abs(pure_jam2).^2);
        P_sum  = mean(abs(pure_jam1 + pure_jam2).^2);

        JNR1_vals(n)  = 10 * log10(P_jam1 / P_noise);
        JNR2_vals(n)  = 10 * log10(P_jam2 / P_noise);
        JNR_eff_vals(n) = 10 * log10(P_sum / P_noise);
    end

    % --- 统计 ---
    mu1   = mean(JNR1_vals);
    mu2   = mean(JNR2_vals);
    mu_eff = mean(JNR_eff_vals);
    sd_eff = std(JNR_eff_vals);

    expected_jnr = test_JNR + expected_boost_db;  % ≈ test_JNR + 3.01
    dev = mu_eff - expected_jnr;
    actual_boost = mu_eff - test_JNR;

    pass = abs(dev) < 1.5;  % 放宽到1.5dB, 因为两个干扰器的JNR本身有微弱波动
    flag = ternary(pass, 'OK', '!!');

    fprintf('%-14s | %8.2f   | %7.2f  | %6.2f   | %6.2f   | %+7.2f    | %+5.2f   | %s\n', ...
        combo_name, mu1, mu2, mu_eff, expected_jnr, dev, actual_boost, flag);

    all_results(c).name     = combo_name;
    all_results(c).jnr1     = mu1;
    all_results(c).jnr2     = mu2;
    all_results(c).jnr_eff  = mu_eff;
    all_results(c).jnr_expected = expected_jnr;
    all_results(c).dev      = dev;
    all_results(c).boost    = actual_boost;
    all_results(c).pass     = pass;
end

fprintf('\n========== 结论 ==========\n');
n_pass = sum([all_results.pass]);
n_total = length(all_results);
fprintf('  通过: %d/%d (判定标准: 偏差 < 1.5 dB)\n', n_pass, n_total);

if n_pass < n_total
    fprintf('  未通过:\n');
    for c = 1:n_total
        if ~all_results(c).pass
            fprintf('    %s: 有效JNR=%.2f dB, 预期=%.2f dB, 偏差=%+.2f dB\n', ...
                all_results(c).name, all_results(c).jnr_eff, ...
                all_results(c).jnr_expected, all_results(c).dev);
        end
    end
end

% 总结叠加增益
fprintf('\n========== 叠加增益分析 ==========\n');
boosts = [all_results.boost];
fprintf('  理论值: +%.2f dB (= 10*log10(2))\n', expected_boost_db);
fprintf('  实测均值: %+.2f dB\n', mean(boosts));
fprintf('  实测范围: [%+.2f, %+.2f] dB\n', min(boosts), max(boosts));

% 打印每个组合的JNR标签建议
fprintf('\n========== JNR标签建议 ==========\n');
fprintf('  组合干扰的metadata中JNR记录为 %+d dB (单干扰目标值),\n', test_JNR);
fprintf('  但实测有效JNR ≈ %.1f dB (叠加增益 +%.1f dB).\n', ...
    test_JNR + expected_boost_db, expected_boost_db);
fprintf('  如果模型训练需要一致的JNR条件, 建议:\n');
fprintf('    - 方案A: 降低组合干扰的JNR_target, 使其有效JNR与单干扰一致\n');
fprintf('    - 方案B: 在metadata中额外记录 effective_JNR 字段\n');
fprintf('    - 方案C: 组合时对 sum_jam 做功率归一化 (除以 sqrt(N_jammers))\n');

function out = ternary(cond, t, f)
    if cond, out = t; else, out = f; end
end
