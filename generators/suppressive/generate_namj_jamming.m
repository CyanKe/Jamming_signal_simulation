function [pure_jam] = generate_namj_jamming(tx, params, data_num)
    % generate_csj_jamming - 生成噪声调幅干扰(Noise Amplitude Modulation Jamming, NAMJ) 
    % tx: 包含 LFM 信号的发射数据
    % params: 参数结构体 (需包含 fs, N_total, JNR, PRI_samp, Ntau, Np, pos, M)
    % data_num: 生成样本数
    % 输出:
    %   pure_jam - 干扰信号
    %   jam_info - 干扰参数信息 (用于metadata记录)

    % --- 解包参数 ---
    Aj = 10^(params.JNR/20);  % 干扰幅度
    fs = params.fs;
    N_total = params.N_total;

    % --- 1. 随机中心频率 (Fj) ---
    if isfield(params, 'random_Fj') && params.random_Fj
        Fj = (rand - 0.5) * 0.1 * fs;
    else
        if isfield(params, 'Fj')
            Fj = params.Fj;
        else
            Fj = 0;
        end
    end

    % --- 2. 调制深度 (m_a) ---
    % 优先使用 m_a_range 样本级随机，其次 m_a 固定值，缺省 0.8
    if isfield(params, 'm_a_range') && numel(params.m_a_range) >= 2
        m_a_base = params.m_a_range(1) + (params.m_a_range(2) - params.m_a_range(1)) * rand;
    elseif isfield(params, 'm_a')
        m_a_base = params.m_a;
    else
        m_a_base = 0.8;
    end
    m_a_base = min(max(m_a_base, 0.01), 1.0);

    % 调制噪声带宽控制
    if isfield(params, 'BJ')
        Bj_base = params.BJ;
    else
        Bj_base = fs * 0.1;
    end

    % 初始化输出
    pure_jam = zeros(data_num, N_total);
    t = (0:N_total-1) / fs;

    for m = 1:data_num
        % --- 3. 生成调制噪声 ---
        white_noise = randn([1,N_total]);
        white_noise = white_noise / std(white_noise);

        % 噪声带宽 (±10% 随机抖动)
        ratio = 0.9 + 0.2 * rand;
        N_bw = Bj_base * ratio;
        if N_bw < fs/2
            [b, a] = fir1(64, N_bw/fs, chebwin(65, 40));
            mod_signal = filter(b, a, white_noise);
            mod_signal = mod_signal / std(mod_signal);
        else
            mod_signal = white_noise;
        end

        % --- 4. 幅度调制 ---
        amp_env = 1 + m_a_base * mod_signal;
        amp_env(amp_env < 0) = 0.01;

        carrier = exp(1j * 2 * pi * Fj * t);
        fm_jam_base = Aj * amp_env .* carrier;

        % --- 功率归一化 ---
        fm_jam_base = fm_jam_base / std(fm_jam_base) * Aj;

        pure_jam(m,:) = fm_jam_base;
    end
end
