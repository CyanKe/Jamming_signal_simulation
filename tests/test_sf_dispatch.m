% ==========================================================
% test_sf_dispatch.m - 验证 multi_generation_v2 的存储-转发开关
%
% 关键事实（本测试要确认）：
%   原生成器在每个样本内只生成一个 PRI 模板，然后 repmat 到 Np 个脉冲，
%   因此 Np>1 时**原路径本来就是 U = Np（整帧同一波形）**。
%   新开关只是把 U 变成可调参数：U=1 才是「每脉冲重新产生噪声」。
%
% 检查项：
%   1. Np=1 时设 U 不生效（走原生成器）
%   2. 设 U=Np 时：走 SF 生成器，且输出与原路径逐点一致
%   3. 设 U=1 时：脉间相干性显著下降
%   4. 不设 U 时：走原路径，metadata 无 SF 字段
% ==========================================================
clear; clc;

root_path = fileparts(fileparts(mfilename('fullpath')));
addpath(root_path);
addpath(fullfile(root_path, 'main'));
addpath(fullfile(root_path, 'generators', 'base'));
addpath(fullfile(root_path, 'generators', 'suppressive'));
addpath(fullfile(root_path, 'utils'));

failures = {};
fprintf('========================================\n');
fprintf('  multi_generation_v2 存储-转发开关验证\n');
fprintf('========================================\n\n');

for name = {'NCJ', 'NPJ'}
    tag = name{1};
    low = lower(tag);

    % ---------- 1. Np = 1, 设 U 不生效 ----------
    cfg = quiet_config();
    cfg.signal.Np = 1;
    cfg.jamming.(low).U = 16;
    cfg.jamming.JNR_values = 0;
    params = prep_params(cfg);
    rng(2024);
    [~, m1] = multi_generation_v2(tag, params, 0, 1, cfg);
    has1 = isfield(m1(1).jam_params, [low '_U']);
    fprintf('%-3s  Np=1 , U=16  ->  SF 生效: %d  (期望 0)\n', tag, has1);
    if has1, failures{end+1} = [tag ' Np=1 must not use SF']; end %#ok<SAGROW>

    % ---------- 2/3/4. Np = 16 ----------
    cfg0 = quiet_config();
    cfg0.signal.Np  = 16;
    cfg0.signal.SNR = -40;          % 压低回波，让脉间相关由干扰决定
    cfg0.jamming.JNR_values = 0;

    % 4. 不设 U
    params = prep_params(cfg0);
    rng(2024);
    [s_def, mdef] = multi_generation_v2(tag, params, 0, 1, cfg0);
    has_def = isfield(mdef(1).jam_params, [low '_U']);

    % 2. U = Np
    cfg = cfg0; cfg.jamming.(low).U = 16;
    params = prep_params(cfg);
    rng(2024);
    [s_16, m16] = multi_generation_v2(tag, params, 0, 1, cfg);

    % 3. U = 1
    cfg = cfg0; cfg.jamming.(low).U = 1;
    params = prep_params(cfg);
    rng(2024);
    [s_1, m1b] = multi_generation_v2(tag, params, 0, 1, cfg);

    PRI_samp = round(cfg0.signal.PRI * cfg0.signal.fs);
    [cm_def, cx_def] = pulse_corr(reshape(s_def, PRI_samp, []).');
    [~,      cx_16] = pulse_corr(reshape(s_16,  PRI_samp, []).');
    [cm_1,   cx_1]  = pulse_corr(reshape(s_1,   PRI_samp, []).');

    c_shape = abs(sum(conj(s_def(:)).*s_16(:))) / sqrt(sum(abs(s_def(:)).^2)*sum(abs(s_16(:)).^2));
    d_amp   = 20*log10(sqrt(mean(abs(s_def(:)).^2))/sqrt(mean(abs(s_16(:)).^2)));
    fprintf('%-3s  Np=16 不设 U  -> SF 生效:%d  corr max=%.3f\n', tag, has_def, cx_def);
    fprintf('%-3s  Np=16 U=16    -> SF 生效:%d  corr max=%.3f  n_blocks=%d  vs默认: corr=%.9f amp=%+.3f dB\n', ...
        tag, isfield(m16(1).jam_params,[low '_U']), cx_16, m16(1).jam_params.([low '_n_blocks']), c_shape, d_amp);
    fprintf('%-3s  Np=16 U=1     -> SF 生效:%d  corr max=%.3f  mean=%.3f\n\n', ...
        tag, isfield(m1b(1).jam_params,[low '_U']), cx_1, cm_1);

    if has_def, failures{end+1} = [tag ' default path must not use SF']; end %#ok<SAGROW>
    if c_shape < 0.9999
        failures{end+1} = sprintf('%s U=Np differs from default path (corr=%.6f)', tag, c_shape);
    end
    if abs(d_amp) > 0.5
        failures{end+1} = sprintf('%s U=Np amplitude differs by %.2f dB', tag, d_amp);
    end
    if cx_1 > 0.3 * cx_16
        failures{end+1} = sprintf('%s U=1 corr %.3f not clearly below U=Np %.3f', tag, cx_1, cx_16);
    end
end

fprintf('========================================\n');
if isempty(failures)
    fprintf('  ALL CHECKS PASSED\n');
else
    fprintf('  FAILURES:\n');
    for k = 1:numel(failures)
        fprintf('    - %s\n', failures{k});
    end
end
fprintf('========================================\n');

if ~isempty(failures)
    error('test_sf_dispatch: %d check(s) failed', numel(failures));
end


% ================================================================ helpers
function cfg = quiet_config()
    evalc('cfg = config();');   % config() 会打印生成计划，这里屏蔽
end

function params = prep_params(cfg)
    params = config_to_params(cfg);
    [~, params] = generate_0base_signal(params);
end

function [cmean, cmax] = pulse_corr(seg)
    seg = seg - mean(seg, 2);
    nrm = sqrt(sum(abs(seg).^2, 2));
    C   = abs(seg * seg') ./ (nrm * nrm');
    v   = C(triu(true(size(C)), 1));
    cmean = mean(v);
    cmax  = max(v);
end
