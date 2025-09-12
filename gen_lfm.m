function lfm = gen_lfm(cfg)
    % cfg: 从JSON加载的参数结构体
    fs = cfg.fs;
    taup = cfg.taup;
    B = cfg.B;
    ts = 1/fs;
    Ntau = round(taup*fs);
    ttau = (-Ntau/2:Ntau/2-1)*ts;

    % LFM信号
    lfm = exp(1j*pi*B/taup*ttau.^2);
end
