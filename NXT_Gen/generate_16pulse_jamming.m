% ==========================================================
% Constant-Center-Frequency Pulse Jamming (CCF-PJ)
% 固定中心频率脉冲干扰
% ==========================================================
function [pure_jam] = generate_16pulse_jamming(tx, params, data_num)

% -------- 参数解包 --------
fs       = params.fs;
fc       = 0;params.fc;           % 干扰中心频率
Np       = params.Np;
PRI_samp = params.PRI_samp;
Ntau     = params.Ntau;
pos      = params.pos;
N_total  = params.N_total;

Aj = 10^(params.JNR/20);

pure_jam = zeros(data_num, N_total);

% 全时间轴（一个 PRI）
t_pri = (0:PRI_samp-1) / fs;

for m = 1:data_num

    % ---------- 1. 脉冲参数 ----------
    PRP_ratio = 0.05 + 0.1 * rand();     % 相对 PRI
    duty      = 0.1  + 0.4 * rand();

    PRP_samp  = max(5, round(PRP_ratio * PRI_samp));
    Ton_samp  = max(1, round(duty * PRP_samp));

    % ---------- 2. 脉冲门控 ----------
    pulse_gate = zeros(1, PRI_samp);
    idx = pos;

    while idx <= PRI_samp
        pulse_gate(idx : min(idx+Ton_samp-1, PRI_samp)) = 1;
        idx = idx + PRP_samp;
    end

    % ---------- 3. 固定频率载波 ----------
    cw = exp(1j * 2*pi*fc * t_pri);

    jam_pri = Aj * pulse_gate .* cw;

    % ---------- 4. 复制 ----------
    pure_jam(m, :) = repmat(jam_pri, 1, Np);

end
end
