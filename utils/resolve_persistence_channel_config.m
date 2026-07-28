function ch = resolve_persistence_channel_config(cfg_or_opts)
% RESOLVE_PERSISTENCE_CHANNEL_CONFIG 解析单/多通道 persistence 配置
%
% 输入可为:
%   - config() 返回的 cfg (读 cfg.persistence.*)
%   - 含字段的 struct / Name-Value 汇总 opts
%
% 输出 ch:
%   .channel_power_bins  - 1×C 向量
%   .target_size         - [H, W] 或 [] (单通道默认用原生尺寸)
%   .is_multichannel     - true 当 C>1
%   .num_power_bins      - 兼容字段: 取 max(channel_power_bins) 或原标量

    p = struct();
    if isstruct(cfg_or_opts) && isfield(cfg_or_opts, 'persistence')
        p = cfg_or_opts.persistence;
    elseif isstruct(cfg_or_opts)
        p = cfg_or_opts;
    end

    bins = [];
    if isfield(p, 'channel_power_bins') && ~isempty(p.channel_power_bins)
        bins = double(p.channel_power_bins(:).');
    elseif isfield(p, 'num_power_bins') && ~isempty(p.num_power_bins)
        bins = double(p.num_power_bins(:).');
    else
        bins = 224;
    end

    target_size = [];
    if isfield(p, 'target_size') && ~isempty(p.target_size)
        target_size = double(p.target_size(:).');
        if numel(target_size) ~= 2
            error('resolve_persistence_channel_config: target_size 必须是 [H, W]');
        end
    end

    is_multi = numel(bins) > 1;
    % 多通道默认目标尺寸: [max 可能的 freq 由调用方 STFT 决定; 此处仅建议 power=max(bins)]
    % 若配置了 target_size 则尊重配置; 未配置且多通道时 target_size 留空,
    % 由 compute_persistence_channels 默认 [Nfreq, max(bins)]
    if is_multi && isempty(target_size) && isfield(p, 'target_size') && isempty(p.target_size)
        % explicit empty
    end

    ch = struct();
    ch.channel_power_bins = bins;
    ch.target_size = target_size;
    ch.is_multichannel = is_multi;
    ch.num_power_bins = max(bins);  % 兼容旧代码/元数据
end
