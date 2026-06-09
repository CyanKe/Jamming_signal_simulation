function [pure_jam] = generate_ab_jamming(tx, params, data_num)
    % generate_ab_jamming - 生成瞄准干扰(Aimed Jamming/[Spot Jamming], AJ/[SJ])或阻塞干扰(Blocking Jamming/Barrage Jamming, BJ))
    % tx: 包含 LFM 信号的发射数据
    % params: 参数结构体 (需包含 fs, N_total, JNR, PRI_samp, Ntau, Np, pos, M)
    % data_num: 生成样本数
    % 输出:
    %   pure_jam - 干扰信号
    %   jam_info - 干扰参数信息 (用于metadata记录)

    % 解包参数
    Aj      = 10^(params.JNR/20);
    Bj      = params.BJ; % 瞄准/阻塞带宽
    fs      = params.fs;
    N_total = params.N_total;

    % --- 随机中心频率 (Fj) ---
    if isfield(params, 'random_Fj') && params.random_Fj
        Fj = (rand - 0.5) * 0.1 * fs;
    else
        if isfield(params, 'Fj')
            Fj = params.Fj;
        else
            Fj = 0;
        end
    end

    % 初始化输出
    pure_jam = zeros(data_num, N_total);
    t = (0:N_total-1) / fs;

    for m = 1:data_num
        % --- 生成噪声 ---
        white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
        white_noise = white_noise / std(white_noise); % 标准化

        % --- 生成瞄准/阻塞干扰 ---
        lpFilt = fir1(34, Bj/fs, chebwin(35,30));
        sp_j = filter(lpFilt, 1, white_noise); % 使用同一个噪声源滤波
        sp_j = sp_j / std(sp_j);  % FIR滤波后功率归一化

        % 载波
        carrier = exp(1j * 2 * pi * Fj * t);
        jam_signal = Aj * sp_j .* carrier;

        pure_jam(m,:) = jam_signal;
    end
end