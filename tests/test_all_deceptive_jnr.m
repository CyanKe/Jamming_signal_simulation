% ==========================================================
% test_all_deceptive_jnr.m - 批量验证所有欺骗干扰的JNR
% ==========================================================
clear; clc; close all;

script_path = fileparts(mfilename('fullpath'));
root_path = fileparts(script_path);
addpath(root_path);
addpath(fullfile(root_path, 'generators', 'base'));
addpath(fullfile(root_path, 'generators', 'deceptive'));
addpath(fullfile(root_path, 'utils'));

cfg = config();
params = config_to_params(cfg);

test_JNR = 20;  % dB
params.JNR = test_JNR;

N_test = 100;

generator_list = {
    'CSJ',   @generate_csj_jamming;
    'DFTJ',  @generate_dftj_jamming;
    'ISRJ',  @generate_isrj_jamming;
    'SMSPJ', @generate_smspj_jamming;
    'CIJ',   @generate_cij_jamming;
    'RGPO',  @generate_rgpo_jamming;
    'VGPO',  @generate_vgpo_jamming;
};

fprintf('========================================\n');
fprintf('  所有欺骗干扰 JNR 批量验证\n');
fprintf('========================================\n');
fprintf('  fs = %.0f MHz, taup = %.0f us, PRI = %.0f us\n', params.fs/1e6, params.taup*1e6, params.PRI*1e6);
fprintf('  Ntau = %d, PRI_samp = %d, 占空比 = %.1f%%\n', ...
    round(params.taup*params.fs), round(params.PRI*params.fs), ...
    round(params.taup*params.fs)/round(params.PRI*params.fs)*100);
fprintf('  目标 JNR = %+d dB, 测试样本数 = %d\n\n', test_JNR, N_test);

fprintf('%-6s | %10s | %8s | %8s | %8s | %s\n', ...
    '类型', '均值(dB)', 'Std(dB)', 'Min(dB)', 'Max(dB)', '判断');
fprintf('-------|------------|----------|----------|----------|--------\n');

all_results = struct();

for g = 1:size(generator_list, 1)
    jam_name = generator_list{g, 1};
    jam_func = generator_list{g, 2};

    JNR_vals = zeros(1, N_test);

    for n = 1:N_test
        params.pos = cfg.generation.pos_range(1) + ...
                     randi([0, cfg.generation.pos_range(2) - cfg.generation.pos_range(1)]);

        % 设置各类型特有参数
        switch jam_name
            case 'RGPO'
                params.v = cfg.jamming.rgpo.v;
                params.start_time = 0;
            case 'VGPO'
                params.pull = cfg.jamming.vgpo.pull;
                params.start_time = 0;
        end

        [tx, params] = generate_0base_signal(params);

        white_noise = randn(1, params.N_total) + 1j*randn(1, params.N_total);
        white_noise = white_noise / std(white_noise);

        % 欺骗干扰返回多个输出，取第一个(pure_jam)
        outputs = cell(1, nargout(jam_func));
        [outputs{:}] = jam_func(tx, params, 1);
        pure_jam = outputs{1};

        P_jam   = mean(abs(pure_jam).^2);
        P_noise = mean(abs(white_noise).^2);
        JNR_vals(n) = 10 * log10(P_jam / P_noise);
    end

    mu  = mean(JNR_vals);
    sd  = std(JNR_vals);
    mn  = min(JNR_vals);
    mx  = max(JNR_vals);
    dev = mu - test_JNR;

    pass = abs(dev) < 1;
    flag = ternary(pass, 'OK', '!!');

    fprintf('%-6s | %8.2f dB | %6.2f dB | %6.2f dB | %6.2f dB | %s\n', ...
        jam_name, mu, sd, mn, mx, flag);

    all_results(g).name = jam_name;
    all_results(g).mean = mu;
    all_results(g).std = sd;
    all_results(g).dev = dev;
    all_results(g).pass = pass;
end

fprintf('\n========== 结论 ==========\n');
n_pass = sum([all_results.pass]);
n_total = length(all_results);
fprintf('  通过: %d/%d\n', n_pass, n_total);
if n_pass < n_total
    fprintf('  未通过:\n');
    for g = 1:n_total
        if ~all_results(g).pass
            fprintf('    %s: %+.2f dB 偏差 (期望 %.1f%% 占空比补偿)\n', ...
                all_results(g).name, all_results(g).dev, ...
                round(params.taup*params.fs)/round(params.PRI*params.fs)*100);
        end
    end
end

function out = ternary(cond, t, f)
    if cond, out = t; else, out = f; end
end
