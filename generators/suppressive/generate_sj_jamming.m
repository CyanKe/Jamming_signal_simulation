function [pure_jam] = generate_sj_jamming(tx, params, data_num)
    % generate_sj_jamming - 生成扫频干扰(Sweeping Jamming, SJ) 
    % tx: 包含 LFM 信号的发射数据
    % params: 参数结构体 (需包含 fs, N_total, JNR, PRI_samp, Ntau, Np, pos, M)
    % data_num: 生成样本数
    % 输出:
    %   pure_jam - 干扰信号
    %   jam_info - 干扰参数信息 (用于metadata记录)

    % --- 解包参数 ---
    fs = params.fs;
    N_total = params.N_total;
    As = 10^(params.SNR/20);
    Aj = 10^(params.JNR/20);
    Bj = params.BJ; % 瞄准带宽
    fjc = 0;   % 干扰中心频率

    % 初始化输出
    % samples = zeros(data_num, N_total);
    % labels = ones(data_num, 1) * label;
    pure_jam = zeros(data_num, N_total);
    for m = 1:data_num
        % % --- 生成噪声 ---
        % white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
        % white_noise = white_noise / std(white_noise); % 标准化

        % --- 生成扫频干扰 ---
        % 扫频带宽: ≤ fs 避免频谱混叠
        jam_BW = params.fs; % * (0.1 + 0.5 * rand());  % 0.5~1.0×fs = 40~80 MHz
        % 随机上下扫: +1 上扫 (低→高), -1 下扫 (高→低)
        sweep_dir = 2 * (rand() > 0.5) - 1;
        f0 = -sweep_dir * jam_BW/2;    % 起始频率（相对基带）
        % 扫频周期: 基于 PRI 而非 taup, 限制 ≤ PRI/2 确保 ≥2 个完整周期
        T_sweep_raw = params.PRI * (0.25 + 0.25 * rand());  % 0.15~0.50 × PRI
        T_sweep = round(T_sweep_raw * fs) / fs;  % 对齐采样网格
        K = sweep_dir * jam_BW / T_sweep;  % 调频斜率 (带方向)
        tj = (0:N_total-1)/fs;         % 时间轴

        % 将时间折返到每个扫频周期内
        t_mod = mod(tj, T_sweep);

        % 生成扫频载波（周期性线性调频）
        sweep_carrier = exp(1j*2*pi*(f0*t_mod + 0.5*K*t_mod.^2));

        % 叠加宽带噪声包络（可选）
        sp = randn([1,N_total]) + 1j*randn([1,N_total]);
        sp = sp / std(sp);
        lpFilt = fir1(34, Bj/fs, chebwin(35,30));
        sp_env = filter(lpFilt, 1, sp);
        sp_env = sp_env / std(sp_env);  % FIR滤波后功率归一化

        % 扫频干扰信号
        sp_j = sweep_carrier .* sp_env;
        jam_signal = Aj * (sp_j .* exp(1j*2*pi*fjc*tj));

        pure_jam(m,:) = jam_signal;

        % % --- 混合信号 ---
        % pure_echo = As * tx;
        % rx = pure_echo + jam_signal + white_noise;
        % 
        % % --- 归一化 (防止梯度爆炸) ---
        % rx = rx / max(abs(rx));
        % 
        % samples(m, :) = rx;
    end
end