% ==========================================================
% generate_base_signal.m - 生成基础LFM脉冲串信号
% ==========================================================
function [tx, params_out] = generate_0base_signal(params)
    fs = params.fs;
    ts = 1/fs;
    
    % LFM脉冲
    Ntau = round(params.taup * fs);
    ttau = (-Ntau/2 : Ntau/2-1) * ts;
    lfm = exp(1j*pi*params.B/params.taup * ttau.^2);

    % 多脉冲参数
    PRI_samp = round(params.PRI * fs);
    N_total = params.Np * PRI_samp;
    t_total = (0:N_total-1) * ts; % 时间轴
    
    % 构造发射信号
    tx = zeros(1, N_total);
    target_start_idx_in_PRI = params.pos; % 目标在PRI内的固定起始位置
    for k = 0:params.Np-1
        start_idx = k * PRI_samp + target_start_idx_in_PRI;
        tx(start_idx : start_idx + Ntau - 1) = lfm;
    end
    
    % 将一些计算好的参数传回，方便后续使用
    params_out = params;
    params_out.N_total = N_total;
    params_out.t_total = t_total;
    params_out.PRI_samp = PRI_samp;
    params_out.Ntau = Ntau;
    params_out.ttau = ttau;
    params_out.target_start_idx_in_PRI = target_start_idx_in_PRI;
    params_out.lfm = lfm;
    
end