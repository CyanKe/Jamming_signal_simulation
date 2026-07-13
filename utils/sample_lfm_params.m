% ==========================================================
% sample_lfm_params.m - 随机抽取 LFM 参数 (B, taup, sweep_dir)
% 使用拒绝采样确保满足约束条件
% ==========================================================
function [B, taup, sweep_dir] = sample_lfm_params(cfg_signal, fs, PRI)
    % 输入:
    %   cfg_signal - 配置结构体 (需包含 B_range, taup_range, BT_min, sweep_dir_enable)
    %   fs         - 采样频率 (Hz)
    %   PRI        - 脉冲重复间隔 (s)
    % 输出:
    %   B          - 带宽 (Hz)
    %   taup       - 脉宽 (s)
    %   sweep_dir  - 扫频方向: +1 上扫, -1 下扫

    B_range = cfg_signal.B_range;
    taup_range = cfg_signal.taup_range;
    BT_min = cfg_signal.BT_min;

    max_attempts = 100;
    for attempt = 1:max_attempts
        B = B_range(1) + (B_range(2)-B_range(1)) * rand();
        taup = taup_range(1) + (taup_range(2)-taup_range(1)) * rand();

        % 约束1: 带宽应低于 0.4*fs (防止频谱混叠)
        if B >= 0.4 * fs, continue; end
        % 约束2: 脉宽应小于 0.4*PRI (确保脉冲在PRI内)
        if taup >= 0.4 * PRI, continue; end
        % 约束3: 时间带宽积 B*taup 应足够大 (保证LFM有处理增益)
        if B * taup < BT_min, continue; end
        break;
    end

    if attempt == max_attempts
        % 回退: 使用中间值 (方案A范围下几乎不会触发)
        B = mean(B_range);
        taup = mean(taup_range);
        warning('LFM拒绝采样 %d 次耗尽，使用范围中值 B=%.1f MHz, taup=%.1f us', ...
                max_attempts, B/1e6, taup*1e6);
    end

    % 扫频方向
    if isfield(cfg_signal, 'sweep_dir_enable') && cfg_signal.sweep_dir_enable
        sweep_dir = 2 * (rand() > 0.5) - 1;  % +1 上扫, -1 下扫
    else
        sweep_dir = 1;  % 默认上扫
    end
end
