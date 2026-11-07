% ==========================================================
% test_ncj_npj_sf.m - 验证 NCJ/NPJ 存储-转发变体
%
% 检查项:
%   1. Np=1 时与原生成器「形状一致」（相关系数 = 1，仅整体幅度不同）
%   2. 整帧 RMS 恒等于 Aj = 10^(JNR/20)（新版本归一化更严格，见下）
%   3. 时间占空比 = Ntau / PRI_samp（突发只占一个脉宽）
%   4. 脉间相关: U=1 接近 0, U=Np 精确为 1
%   5. MTD 相干增益 = 10log10(min(U,Np))
%
% 说明: 原 generate_ncj_jamming 没有帧级归一化，实际功率等于
%       Aj × (切片 std)，逐样本有约 ±0.2 dB 的随机偏差；新版统一归一化到
%       RMS = Aj。因此 Np=1 时两者波形完全相同、幅度相差一个常数。
% ==========================================================
clear; clc;

script_path = fileparts(mfilename('fullpath'));
root_path   = fileparts(script_path);
addpath(root_path);
addpath(fullfile(root_path, 'generators', 'base'));
addpath(fullfile(root_path, 'generators', 'suppressive'));
addpath(fullfile(root_path, 'utils'));

FS     = 80e6;
PRI    = 100e-6;
TAUP   = 20e-6;
B      = 10e6;
POS    = 5000;
JNR    = 0;
NP_CPI = 16;

failures = {};

fprintf('========================================\n');
fprintf('  NCJ / NPJ 存储-转发变体验证\n');
fprintf('========================================\n');
fprintf('  fs = %.0f MHz, taup = %.0f us, PRI = %.0f us, B = %.0f MHz\n\n', ...
    FS/1e6, TAUP*1e6, PRI*1e6, B/1e6);

% ---------------------------------------------------------------- 1. Np = 1
fprintf('--- 1. Np=1: 与原生成器形状一致 ---\n');
for name = {'NCJ', 'NPJ'}
    tag = name{1};
    params = base_params(FS, PRI, TAUP, B, POS, JNR, 1);
    [tx, params] = generate_0base_signal(params);

    switch tag
        case 'NCJ'
            f_old = @generate_ncj_jamming; f_new = @generate_ncj_sf_jamming;
        otherwise
            f_old = @generate_npj_jamming; f_new = @generate_npj_sf_jamming;
    end

    rng(12345); jam_old = f_old(tx, params, 1);
    rng(12345); jam_new = f_new(tx, assign(params, 'U', 1), 1);

    c = abs(sum(conj(jam_old(:)).*jam_new(:))) / ...
        sqrt(sum(abs(jam_old(:)).^2) * sum(abs(jam_new(:)).^2));
    scale_db = 20*log10(sqrt(mean(abs(jam_old(:)).^2)) / ...
                        sqrt(mean(abs(jam_new(:)).^2)));
    ok = abs(c - 1) < 1e-12;
    fprintf('  %-3s  corr = %.12f   amplitude(old/new) = %+.3f dB\n', tag, c, scale_db);
    report('shape identical', ok);
    if ~ok, failures{end+1} = [tag ' Np=1 shape mismatch']; end
end

% ---------------------------------------------------------------- 2-4. Np = 16
fprintf('\n--- 2-4. Np=16: 功率 / 占空比 / 脉间相关 ---\n');
fprintf('%-4s %4s | %14s | %8s | %10s %10s | %9s\n', ...
    'type', 'U', 'RMS vs Aj (dB)', 'duty', 'corr mean', 'corr max', 'n_blocks');
fprintf('---------------------------------------------------------------\n');
U_list = [1, 2, 4, 8, 16];

for name = {'NCJ', 'NPJ'}
    tag = name{1};
    switch tag
        case 'NCJ', f_new = @generate_ncj_sf_jamming;
        otherwise,  f_new = @generate_npj_sf_jamming;
    end

    for U = U_list
        params = base_params(FS, PRI, TAUP, B, POS, JNR, NP_CPI);
        [tx, params] = generate_0base_signal(params);
        rng(4321);
        [jam, info] = f_new(tx, assign(params, 'U', U), 1);

        rms_db = 20*log10(sqrt(mean(abs(jam).^2)) / 10^(JNR/20));
        seg    = reshape(jam, round(PRI*FS), []).';
        duty   = mean(mean(abs(seg) > 0, 2));
        [cm, cx] = pulse_corr(seg);

        fprintf('%-4s %4d | %14.2e | %8.3f | %10.3f %10.3f | %9d\n', ...
            tag, U, rms_db, duty, cm, cx, info(1).n_blocks);

        if abs(rms_db) > 1e-9
            failures{end+1} = sprintf('%s U=%d RMS off by %.2e dB', tag, U, rms_db);
        end
        if abs(duty - params.Ntau/params.PRI_samp) > 1e-3
            failures{end+1} = sprintf('%s U=%d duty %.4f', tag, U, duty);
        end
        if U == 1 && cm > 0.15
            failures{end+1} = sprintf('%s U=1 inter-pulse corr %.3f too high', tag, cm);
        end
        if U == NP_CPI && cx < 0.999999
            failures{end+1} = sprintf('%s U=Np corr %.6f not 1', tag, cx);
        end
    end
end

% ---------------------------------------------------------------- 5. MTD gain
fprintf('\n--- 5. MTD 相干增益 (干扰单独, 无回波无噪声) ---\n');
fprintf('%-4s %4s | %10s | %10s | %8s\n', ...
    'type', 'U', 'gain(dB)', 'theory(dB)', 'dev(dB)');
fprintf('------------------------------------------------\n');
for name = {'NCJ', 'NPJ'}
    tag = name{1};
    switch tag
        case 'NCJ', f_new = @generate_ncj_sf_jamming;
        otherwise,  f_new = @generate_npj_sf_jamming;
    end
    for U = U_list
        params = base_params(FS, PRI, TAUP, B, POS, JNR, NP_CPI);
        [tx, params] = generate_0base_signal(params);
        rng(999);
        jam = f_new(tx, assign(params, 'U', U), 1);
        seg = reshape(jam, round(PRI*FS), []).';

        % 无偏相干增益: 相干叠加功率 / 非相干功率和
        num = mean(abs(sum(seg, 1)).^2);
        den = sum(mean(abs(seg).^2, 2));
        gain = 10*log10(num/den);
        th   = 10*log10(min(U, NP_CPI));
        fprintf('%-4s %4d | %10.2f | %10.2f | %8.2f\n', tag, U, gain, th, gain-th);
        if abs(gain - th) > 1.0
            failures{end+1} = sprintf('%s U=%d MTD gain %.2f vs %.2f', tag, U, gain, th);
        end
    end
end

% ---------------------------------------------------------------- summary
fprintf('\n========================================\n');
if isempty(failures)
    fprintf('  ALL CHECKS PASSED\n');
else
    fprintf('  FAILURES (%d):\n', numel(failures));
    for k = 1:numel(failures)
        fprintf('    - %s\n', failures{k});
    end
end
fprintf('========================================\n');

if ~isempty(failures)
    error('test_ncj_npj_sf: %d check(s) failed', numel(failures));
end


% ================================================================ helpers
function p = base_params(fs, PRI, taup, B, pos, jnr, Np)
    p = struct('fs', fs, 'PRI', PRI, 'taup', taup, 'B', B, 'pos', pos, ...
               'JNR', jnr, 'SNR', -5, 'Np', Np, 'sweep_dir', 1);
end

function p = assign(p, field, value)
    p.(field) = value;
end

function [cmean, cmax] = pulse_corr(seg)
    seg = seg - mean(seg, 2);
    nrm = sqrt(sum(abs(seg).^2, 2));
    C   = abs(seg * seg') ./ (nrm * nrm');
    v   = C(triu(true(size(C)), 1));
    cmean = mean(v);
    cmax  = max(v);
end

function report(msg, ok)
    if ok
        fprintf('  PASS  %s\n', msg);
    else
        fprintf('  FAIL  %s\n', msg);
    end
end
