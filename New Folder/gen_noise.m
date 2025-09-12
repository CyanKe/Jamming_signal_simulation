function [sp, pure_echo, noise_echo] = gen_noise(cfg, lfm)
    fs = cfg.fs;
    samp_num = cfg.samp_num;
    SNR = cfg.SNR;
    JNR = cfg.JNR;
    Bj = cfg.Bj;

    % 噪声基底
    sp = randn([1,samp_num]) + 1j*randn([1,samp_num]);
    sp = sp/std(sp);

    % 幅度因子
    As = 10^(SNR/20); % 目标回波幅度
    Aj = 10^(JNR/20); % 干扰回波幅度

    % 瞄准带宽滤波器
    lpFilt = fir1(34, Bj/fs, chebwin(35,30)); 
    sp1 = filter(lpFilt, 1, sp);

    % 加入目标回波
    range_tar = 1 + round(rand(1,1)*4000);
    sp(1+range_tar:length(lfm)+range_tar) = ...
        sp(1+range_tar:length(lfm)+range_tar) + As*lfm;

    pure_echo = zeros(1, samp_num);
    pure_echo(1+range_tar:length(lfm)+range_tar) = ...
        pure_echo(1+range_tar:length(lfm)+range_tar) + As*lfm;

    noise_echo = Aj * sp1;
    sp = sp + noise_echo;

    % 归一化
    sp = sp / max(abs(sp));
end
