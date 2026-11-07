function [power_range, info] = resolve_custom_power_range(stft_ref, opts)
% RESOLVE_CUSTOM_POWER_RANGE 确定 custom persistence 的功率轴 [lo, hi] (dB)
%
% 输入:
%   stft_ref - 参考 STFT 复数矩阵 [Nfreq, Ntime] (mode='auto' 时使用; fixed 可传 [])
%   opts     - struct, 字段:
%     .power_range_mode   - 'fixed' | 'auto' (默认 'auto')
%     .power_range_db     - [lo, hi] dB, mode='fixed' 时使用 (默认 [0, 70])
%     .power_percentile_lo - auto 下界百分位 (默认 1)
%     .power_margin_db    - auto 余量 (默认 3); 下界/上界均 +margin 以抬高噪声底
%
% 输出:
%   power_range - [lo, hi] dB
%   info        - 说明结构体 (mode, 源参数等)

    if nargin < 2 || isempty(opts)
        opts = struct();
    end

    mode = 'auto';
    if isfield(opts, 'power_range_mode') && ~isempty(opts.power_range_mode)
        mode = lower(char(opts.power_range_mode));
    end

    info = struct();
    info.mode = mode;

    if strcmp(mode, 'fixed')
        if isfield(opts, 'power_range_db') && ~isempty(opts.power_range_db)
            power_range = double(opts.power_range_db(:).');
        else
            power_range = [0, 70];
        end
        if numel(power_range) ~= 2
            error('resolve_custom_power_range: power_range_db 必须是 [lo, hi] 长度2向量');
        end
        if power_range(1) >= power_range(2)
            error('resolve_custom_power_range: 需要 lo < hi, 收到 [%.2f, %.2f]', ...
                power_range(1), power_range(2));
        end
        info.source = 'cfg.persistence.power_range_db';
        info.power_range_db = power_range;
        return;
    end

    if ~strcmp(mode, 'auto')
        error('resolve_custom_power_range: power_range_mode 必须是 ''fixed'' 或 ''auto'', 收到: %s', mode);
    end

    if isempty(stft_ref)
        error('resolve_custom_power_range: mode=''auto'' 时需要提供参考 STFT');
    end

    pct_lo = 1;
    if isfield(opts, 'power_percentile_lo') && ~isempty(opts.power_percentile_lo)
        pct_lo = opts.power_percentile_lo;
    end
    margin = 3;
    if isfield(opts, 'power_margin_db') && ~isempty(opts.power_margin_db)
        margin = opts.power_margin_db;
    end

    pow_db = 10 * log10(abs(stft_ref).^2 + eps);
    pwr_lo = prctile(pow_db(:), pct_lo);
    pwr_hi = max(pow_db(:));
    % 下界也 +margin：抬高功率轴底端，抑制低功率噪声占满下方 bins
    power_range = [pwr_lo + margin, pwr_hi + margin];
    if power_range(1) >= power_range(2)
        power_range(2) = power_range(1) + 1;
    end

    info.source = 'auto_from_ref_sample';
    info.percentile_lo = pct_lo;
    info.margin_db = margin;
    info.raw_p1 = pwr_lo;
    info.raw_max = pwr_hi;
    info.power_range_db = power_range;
end
