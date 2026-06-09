function [phi, delta_f] = gen_modulation_phase(N_samples, fs, mod_params)
% gen_modulation_phase - 基于频率累积的调制相位序列生成
%
% 离散化设计方法：
%   1. 将时宽 T_c 分成 N_samples 个时间采样点 t_n
%   2. 为每个时间点直接指定期望频移 Δf(t_n)
%   3. 通过累加构造相位序列：
%      φ(t_n) = 2π * Σ_{k=0}^{n} Δf(t_k) * Δt
%
% 输入:
%   N_samples - 采样点数 (切片时宽对应的采样数)
%   fs        - 采样频率 (Hz)
%   mod_params - 调制参数结构体:
%       .type   - 调制类型字符串:
%           'doppler'    - 恒频移 (多普勒式)
%           'linear'     - 线性调频 (chirp)
%           'sinusoidal' - 正弦调频
%           'stepped'    - 阶梯调频
%           'random'     - 随机频点
%       (类型特定参数见各case)
%
% 输出:
%   phi     - 调制相位序列 [1, N_samples] (弧度)
%   delta_f - 频移序列 [1, N_samples] (Hz), 用于metadata记录/验证

dt = 1 / fs;
t = (0:N_samples-1) * dt;  % 时间轴

switch mod_params.type
    case 'doppler'
        % 恒频移: Δf(t) = f_d (常数)
        % 参数: .f_d - 多普勒频移 (Hz)
        delta_f = mod_params.f_d * ones(1, N_samples);

    case 'linear'
        % 线性调频: Δf(t) = f0 + k*t
        % 参数: .k  - 调频率 (Hz/s)
        %       .f0 - 初始频偏 (Hz), 默认 0
        if ~isfield(mod_params, 'f0'), mod_params.f0 = 0; end
        delta_f = mod_params.f0 + mod_params.k * t;

    case 'sinusoidal'
        % 正弦调频: Δf(t) = A * sin(2π*f_m*t + φ0)
        % 参数: .A    - 频偏幅度 (Hz)
        %       .f_m  - 调制频率 (Hz)
        %       .phi0 - 初始相位 (rad), 默认 0
        if ~isfield(mod_params, 'phi0'), mod_params.phi0 = 0; end
        delta_f = mod_params.A * sin(2*pi*mod_params.f_m * t + mod_params.phi0);

    case 'stepped'
        % 阶梯调频: 每 step_len 个采样点切换一次频率
        % 参数: .steps    - 频点数组 [f1, f2, ...] (Hz)
        %       .step_len - 每阶持续采样点数
        delta_f = zeros(1, N_samples);
        steps = mod_params.steps;
        step_len = mod_params.step_len;
        for k = 1:length(steps)
            idx_start = (k-1) * step_len + 1;
            idx_end = min(k * step_len, N_samples);
            if idx_start <= N_samples
                delta_f(idx_start:idx_end) = steps(k);
            end
        end

    case 'random'
        % 随机频点: 在 [f_min, f_max] 范围内均匀随机
        % 参数: .f_range - [f_min, f_max] (Hz)
        f_range = mod_params.f_range;
        delta_f = f_range(1) + (f_range(2) - f_range(1)) * rand(1, N_samples);

    otherwise
        error('未知调制类型: %s', mod_params.type);
end

% 核心: 频率累积 → 相位
% φ(t_n) = 2π * Σ Δf(t_k) * Δt
phi = 2 * pi * cumsum(delta_f) * dt;
end
