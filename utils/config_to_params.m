% ==========================================================
% 辅助函数: 将配置转换为params结构体 (兼容现有代码)
% ==========================================================
function params = config_to_params(cfg)
    % 信号参数
    params.fs = cfg.signal.fs;
    params.fc = cfg.signal.fc;
    params.B = cfg.signal.B;
    params.taup = cfg.signal.taup;
    params.Np = cfg.signal.Np;
    params.PRI = cfg.signal.PRI;
    params.SNR = cfg.signal.SNR;
    params.pos = cfg.signal.pos;
    params.numClasses = cfg.jamming.numClasses;
end