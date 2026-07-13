function [pure_jam, jam_info] = generate_smspj_jamming(tx, params, data_num)
    % generate_smspj_jamming: 生成弥散谱干扰
    % 弥散谱干扰（Smeared Spectrum Jamming, SMSPJ）
    % tx: 包含 LFM 信号的发射数据
    % params: 参数结构体 (需包含 fs, N_total, JNR, PRI_samp, Ntau, Np, pos, M)
    % data_num: 生成样本数
    % 输出:
    %   pure_jam - 干扰信号
    %   jam_info - 干扰参数信息 (用于metadata记录)

    % --- 解包参数 ---
    Aj      = 10^(params.JNR/20);
    B       = params.B;
    fs      = params.fs;
    Np      = params.Np; 
    Ntau    = params.Ntau;
    N_total = params.N_total;
    PRI_samp= params.PRI_samp;
    pos     = params.pos;

    % 初始化输出
    pure_jam = zeros(data_num, N_total);
    jam_info = struct('M', {}, 'slope_factor', {});  % M: 扫频分段数, slope_factor: 斜率倍增因子

    for m = 1:data_num
        % --- 1. 设置SMSPJ参数 ---
        M = randi([4 10]); % 扫频分段数 (M需为整数)

        % --- 2. 生成 SMSPJ 子波形 (核心步骤) ---
        % SMSPJ: 将 LFM 时域压缩 M 倍 (调频斜率变为 M*mu), 然后重复拼接。
        % 带宽 B 来自 params.B (当前样本随机值, 非写死)。
        T = Ntau / fs;
        mu = B / T;
        mu_prime = M * mu;            % M 倍调频斜率
        Tj_samples = floor(Ntau / M);
        t_sub = (0 : Tj_samples-1) / fs;

        % 直接生成子波形 (扫频方向跟随当前样本 LFM)
        % exp(-1j*pi*B*t) = 频率偏置 -B/2, 用于上扫将 [0,B] → [-B/2, B/2]
        % 下扫时频率从 0→-B, 需要用 +B/2 偏置 exp(1j*pi*B*t) 将其搬到 [B/2, -B/2]
        if isfield(params, 'sweep_dir') && params.sweep_dir < 0
            sub_wave = exp(-1j * pi * mu_prime * t_sub.^2) .* exp(1j * pi * B * t_sub);
        else
            sub_wave = exp(1j * pi * mu_prime * t_sub.^2) .* exp(-1j * pi * B * t_sub);
        end

        % --- 4. 重复拼接子波形 ---
        % 将压缩后的子波形重复 M 次，使其总长度回到 Ntau 左右
        smsp_pulse = repmat(sub_wave, 1, M);

        % 修正因整除导致的微小长度差异，确保与 Ntau 完全一致
        len_diff = Ntau - length(smsp_pulse);
        if len_diff > 0
            % 如果短了，补零或补齐最后一采样
            smsp_pulse = [smsp_pulse, zeros(1, len_diff)];
        elseif len_diff < 0
            % 如果长了，截断
            smsp_pulse = smsp_pulse(1 : Ntau);
        end

        % --- 5. 构造单 PRI 模板 ---
        jam_pri = zeros(1, PRI_samp);

        % 设置干扰延迟 (例如相对于目标延迟 5us)
        % 在实际对抗中，干扰通常比目标快或重合，这里设为 5us
        delay_samp = round(rand()*5e-6 * fs);
        target_pos = pos + delay_samp;

        % 确保 target_pos 在有效范围内 [1, PRI_samp-Ntau]
        target_pos = max(1, min(round(target_pos), PRI_samp - Ntau));
        right_range = target_pos + Ntau - 1;

        % 注入干扰
        jam_pri(target_pos : right_range) = Aj * smsp_pulse;

        % --- 6. 记录参数信息 ---
        jam_info(m).M = M;              % 扫频分段数
        jam_info(m).slope_factor = M;   % 斜率倍增因子

        % --- 7. 复制到所有脉冲 ---
        pure_jam(m, :) = repmat(jam_pri, 1, Np);
        pwr = mean(abs(pure_jam(m, :)).^2);
        if pwr > 0
            pure_jam(m, :) = pure_jam(m, :) / sqrt(pwr) * Aj;
        end
        
    end
end