function [pure_jam] = generate_14namj_jammingr(tx, params, data_num)
    % 解包参数
    fs = params.fs;
    N_total = params.N_total;
    Aj = 10^(params.JNR/20);  % 干扰幅度
    params.random_Fj = true ;
    params.random_m_a = true ;
    params.random_BW = true ;
    params.random_envelope = true ;
    params.mix_tone = true ;
    
    % --- 1. 随机中心频率 (Fj) ---
    % 允许 Fj 在 ±5% 的采样率范围内随机跳变，如果是0则保持为0
    if isfield(params, 'random_Fj') && params.random_Fj
        Fj = (rand - 0.5) * 0.1 * fs; 
    else
        if isfield(params, 'Fj')
            Fj = params.Fj;
        else
            Fj = 0;
        end
    end

    % --- 2. 随机调制深度 (m_a) ---
    % 如果开启随机性，每个样本的 m_a 略有不同，丰富幅度特性
    if isfield(params, 'random_m_a') && params.random_m_a
        % 在 0.5 到 0.95 之间随机，避免过调制
        m_a_base = 0.5 + (0.95 - 0.5) * rand; 
    else
        if isfield(params, 'm_a')
            m_a_base = params.m_a;
        else
            m_a_base = 0.8;
        end
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
        % --- 3. 生成带随机特性的调制噪声 ---
        white_noise_real = randn([1, N_total]);
        white_noise_real = white_noise_real / std(white_noise_real);
        
        % 随机化带宽 (可选)
        if isfield(params, 'random_BW') && params.random_BW
            % 允许带宽在 ±10% 内波动
            ratio = 0.9 + 0.2 * rand; 
            N_bw = Bj_base * ratio;
        else
            N_bw = Bj_base;
        end

        % 滤波
        if N_bw < fs/2
            % 使用 fir1 + chebwin 滤波
            [b, a] = fir1(64, N_bw/fs, chebwin(65, 40));
            mod_signal = filter(b, a, white_noise_real);
            mod_signal = mod_signal / std(mod_signal); % 重新归一化
        else
            mod_signal = white_noise_real;
        end

        % --- 4. 随机包络修饰 (Random Envelope Shaping) ---
        % 引入一个随机窗函数，改变噪声的统计特性
        % 这种窗函数不是为了频谱整形，而是为了改变时域包络的起伏特性
        if isfield(params, 'random_envelope') && params.random_envelope
            % 生成一个随机的Tukey窗，随机化其衰减系数
            alpha = 0.1 + 0.1 * rand(); % 随机0.1到0.5之间的衰减
            win = tukeywin(N_total, alpha)';
            % 将窗信号与噪声混合 (注意：窗信号需要归一化并与噪声线性叠加)
            % 这里我们让噪声通过窗函数的调制，模拟非平稳环境
            mod_signal = mod_signal .* win;
            % 再次归一化以保持方差可控
            mod_signal = mod_signal / std(mod_signal);
        end

        % --- 5. 确定本次生成的调制深度 ---
        % 每个样本的小范围随机波动
        if isfield(params, 'random_m_a') && params.random_m_a
            % 稍微扰动
            m_a = m_a_base * (0.95 + 0.1 * rand());
        else
            m_a = m_a_base;
        end

        % --- 6. 幅度调制 ---
        amp_env = 1 + m_a * mod_signal;
        
        % 保护性裁剪 (绝对不要出现负幅度)
        amp_env(amp_env < 0) = 0.01; 
        
        % 载波 (如果随机 Fj 开启，此处的频率是变化的)
        carrier = exp(1j * 2 * pi * Fj * t);
        
        % 合成
        fm_jam_base = Aj * amp_env .* carrier;

        % --- 可选：混合干扰 (Compound Jamming) ---
        % 如果开启，叠加一个微弱的单频干扰，增加一点点"分量"
        if isfield(params, 'mix_tone') && params.mix_tone
            tone_amp = Aj * 0.1; % 干扰幅度的10%
            tone_freq = Fj + 0.1 * fs; % 偏移一点频率
            fm_jam_base = fm_jam_base + tone_amp * exp(1j * 2 * pi * tone_freq * t);
        end

        % --- 功率归一化 ---
        fm_jam_base = fm_jam_base / std(fm_jam_base) * Aj;

        pure_jam(m,:) = fm_jam_base;
    end
end
