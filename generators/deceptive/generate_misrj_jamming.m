function [pure_jam,bbox_info,jam_info] = generate_misrj_jamming(tx, params, data_num)
    % generate_misrj_jamming - 生成调制间歇采样转发干扰 (MISRJ)
    % Modulated Interrupted Sampling Repeater Jamming
    %
    % 工作原理：
    %   从LFM脉冲前沿截取60%~80%时宽的切片，将切片划分为K个小段，
    %   对每一小段施加随机频移（调制），然后以5%~10%脉宽的时延转发M次。
    %   同一采样的信号在每次转发时保持一致（无额外随机化）。
    %
    % 输入:
    %   tx: 包含 LFM 信号的发射数据
    %   params: 参数结构体 (需包含 fs, N_total, JNR, PRI_samp, Ntau, Np, pos, B)
    %   data_num: 生成样本数
    % 输出:
    %   pure_jam - 干扰信号
    %   bbox_info - 边界框信息
    %   jam_info - 干扰参数信息 (用于metadata记录)

    % 解包参数
    PRI_samp = params.PRI_samp;
    N_total = params.N_total;
    Aj = 10^(params.JNR/20);
    Ntau = params.Ntau;
    fs = params.fs;
    Np = params.Np;
    B = params.B;

    % 初始化输出
    pure_jam = zeros(data_num, N_total);
    jam_info = struct('M', {}, 'K', {}, 'slice_ratio', {}, 'delay_ratio', {});

    % 初始化bounding box
    bbox_info = zeros(data_num, 4);

    for m = 1:data_num
        % --- 1. 随机选择MISRJ参数 ---
        M = randi([3 5]);  % 转发次数
        K = 16;            % 子段划分数：将切片等分为K段，每段施加独立随机频移

        % 切片时宽：完整信号的 60% ~ 80%
        slice_ratio = 0.6+ rand() * 0.2;
        slice_width = round(Ntau * slice_ratio);

        % 干扰时延：完整信号的 5% ~ 10%
        delay_ratio = 0.3 + rand() * 0.05;
        delay_samp = round(Ntau * delay_ratio);

        % --- 2. 从LFM信号前沿截取切片 ---
        lfm = tx(1, params.pos:params.pos+params.Ntau-1);
        jam_slice_raw = lfm(1:slice_width);

        % --- 3. MISRJ核心：将切片划分为K段，每段施加随机频移 ---
        seg_len = floor(slice_width / K);
        t = (0:slice_width-1) / fs;  % 时间向量（用于频移相位计算）
        jam_slice = zeros(1, slice_width);

        for k = 1:K
            idx_start = (k-1) * seg_len + 1;
            if k == K
                idx_end = slice_width;  % 最后一段取到末尾，包含余数
            else
                idx_end = k * seg_len;
            end

            % 随机频移
            delta_f = randn() * B * 0.1;

            % 对该段施加频移: s_mod(t) = s(t) * exp(j*2*pi*delta_f*t)
            seg_t = t(idx_start:idx_end);
            jam_slice(idx_start:idx_end) = jam_slice_raw(idx_start:idx_end) .* ...
                exp(1j * 2 * pi * delta_f * seg_t);
        end

        % --- 4. 在一个PRI内生成转发干扰串 ---
        jam_pri = zeros(1, PRI_samp);

        x_min = inf; x_max = -inf;
        y_min = inf; y_max = -inf;

        % 循环多次转发，每次转发的信号完全一致（无额外随机化）
        for i = 1:M
            left_range = params.pos + i * delay_samp;
            right_range = left_range + slice_width - 1;

            if right_range <= PRI_samp
                jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj * jam_slice;
            else
                right_boundary = min(PRI_samp, left_range + slice_width - 1);
                jam_pri(left_range:right_boundary) = jam_pri(left_range:right_boundary) + ...
                    Aj * jam_slice(1:(right_boundary - left_range + 1));
            end

            % 计算bounding box — 时域范围
            x_min = min(x_min, left_range);
            x_max = max(x_max, right_range);
            x_max = min(x_max, PRI_samp);

            % 频域范围（LFM信号带宽）
            y_min = min(y_min, -B / 2);
            y_max = max(y_max, B / 2);
        end

        % 复制到所有PRI
        pure_jam(m,:) = repmat(jam_pri, 1, Np);

        % 功率归一化到目标JNR
        pure_jam(m,:) = pure_jam(m,:) / sqrt(mean(abs(pure_jam(m,:)).^2)) * Aj;

        % 记录bounding box
        bbox_info(m,:) = [x_min, y_min, x_max, y_max];

        % 记录当前样本的参数信息
        jam_info(m).M = M;                    % 转发次数
        jam_info(m).K = K;                    % 子段划分数
        jam_info(m).slice_ratio = slice_ratio; % 切片占空比
        jam_info(m).delay_ratio = delay_ratio; % 时延占空比
    end
    end
    