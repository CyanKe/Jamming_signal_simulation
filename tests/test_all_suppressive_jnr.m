% ==========================================================
% test_all_suppressive_jnr.m - 批量验证所有压制干扰的JNR
% ==========================================================
clear; clc; close all;

script_path = fileparts(mfilename('fullpath'));
root_path = fileparts(script_path);
addpath(root_path);
addpath(fullfile(root_path, 'generators', 'base'));
addpath(fullfile(root_path, 'generators', 'suppressive'));
addpath(fullfile(root_path, 'utils'));

cfg = config();
params = config_to_params(cfg);

test_JNR = 20;  % dB
params.JNR = test_JNR;

N_test = 100;

% 待测生成器列表
generator_list = {
    'NPJ',  @generate_npj_jamming;
    'NCJ',  @generate_ncj_jamming;
    'PJ',   @generate_pulse_jamming;
    'SJ',   @generate_sj_jamming;
    'AJ',   @generate_ab_jamming;
    'BJ',   @generate_ab_jamming;
    'NAMJ', @generate_namj_jamming;
    'NFMJ', @generate_nfmj_jamming;
    'NPMJ', @generate_npmj_jamming;
};

fprintf('========================================\n');
fprintf('  所有压制干扰 JNR 批量验证\n');
fprintf('========================================\n');
fprintf('  fs = %.0f MHz, taup = %.0f us, PRI = %.0f us\n', params.fs/1e6, params.taup*1e6, params.PRI*1e6);
fprintf('  目标 JNR = %+d dB, 测试样本数 = %d\n\n', test_JNR, N_test);

fprintf('%-6s | %10s | %8s | %8s | %8s\n', ...
    '类型', '均值(dB)', 'Std(dB)', 'Min(dB)', 'Max(dB)');
fprintf('-------|------------|----------|----------|----------\n');

all_results = struct();

for g = 1:size(generator_list, 1)
    jam_name = generator_list{g, 1};
    jam_func = generator_list{g, 2};

    JNR_vals = zeros(1, N_test);

    for n = 1:N_test
        params.pos = cfg.generation.pos_range(1) + ...
                     randi([0, cfg.generation.pos_range(2) - cfg.generation.pos_range(1)]);

        % 为AJ/BJ设置随机参数 (和multi_generation_v2一致)
        if strcmp(jam_name, 'AJ')
            BJ_range = cfg.jamming.aj.BJ_range;
            params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
            params.random_Fj = cfg.jamming.aj.random_Fj;
        elseif strcmp(jam_name, 'BJ')
            BJ_range = cfg.jamming.bj.BJ_range;
            params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
            params.random_Fj = cfg.jamming.bj.random_Fj;
        elseif strcmp(jam_name, 'SJ')
            BJ_range = cfg.jamming.sj.BJ_range;
            params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
        elseif strcmp(jam_name, 'NFMJ')
            BJ_range = cfg.jamming.nfmj.BJ_range;
            params.BJ =  (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
            params.random_Fj = cfg.jamming.nfmj.random_Fj;
        elseif strcmp(jam_name, 'NPMJ')
            BJ_range = cfg.jamming.npmj.BJ_range;
            params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
            
            params.random_Fj = cfg.jamming.npmj.random_Fj;
            if isfield(cfg.jamming.npmj, 'Kp_range') && numel(cfg.jamming.npmj.Kp_range) >= 2
                kr = cfg.jamming.npmj.Kp_range;
                params.Kp = kr(1) + (kr(2) - kr(1)) * rand;
            elseif isfield(cfg.jamming.npmj, 'Kp')
                params.Kp = cfg.jamming.npmj.Kp;
            end
        elseif strcmp(jam_name, 'NAMJ')
            BJ_range = cfg.jamming.namj.BJ_range;
            params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
            params.random_Fj = cfg.jamming.namj.random_Fj;
        end

        [tx, params] = generate_0base_signal(params);

        white_noise = randn(1, params.N_total) + 1j*randn(1, params.N_total);
        white_noise = white_noise / std(white_noise);

        pure_jam = jam_func(tx, params, 1);

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
if n_pass == n_total
    fprintf('  所有生成器JNR偏差 < 1 dB\n');
else
    fprintf('  未通过:\n');
    for g = 1:n_total
        if ~all_results(g).pass
            fprintf('    %s: %.2f dB 偏差\n', all_results(g).name, all_results(g).dev);
        end
    end
end

function out = ternary(cond, t, f)
    if cond, out = t; else, out = f; end
end
