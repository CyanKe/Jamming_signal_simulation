function [pure_jam,jam_info] = generate_iscj_jamming(tx, params, data_num)
    % generate_iscj_jamming - 生成间歇采样循环转发干扰 (ISCJ)
    % Interrupted Sampling Circular Jamming
    %
    % 工作原理（累积循环转发）：
    %   将LFM脉冲按采样周期等分为N个连续切片，
    %   第1轮转发切片1，第2轮转发切片1→2，...，第N轮转发切片1→N，
    %   每轮内部切片之间有小时延间隔，形成逐渐密集的假目标群。
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

    % ISCJ 固定参数集（与参考实现一致）
    period_arr = [4e-6, 5e-6, 10e-6];  % 采样脉冲周期 (s)
    duty_arr = [20, 25, 33.33, 50];    % 占空比 (%)

    % 初始化输出
    pure_jam = zeros(data_num, N_total);
    jam_info = struct('M', {}, 'N', {}, 'period', {}, 'duty', {});

    for m = 1:data_num
        % --- 1. 随机选择ISCJ参数 ---
        period = period_arr(randi(length(period_arr)));  % 采样周期 (s)
        duty = duty_arr(randi(length(duty_arr)));         % 占空比 (%)
        period_samp = round(period * fs);                 % 采样周期 (采样点)
        N = round(Ntau / period_samp);                    % 切片个数
        N = max(N, 2);                                    % 至少2个切片
        slice_len = round(Ntau / N);                       % 每个切片长度 (采样点)

        % 切片间转发时延: delay = period * duty * 0.01
        delay_time = period * duty * 0.01;                % 时延 (s)
        delay_samp = max(1, ceil(delay_time * fs));       % 时延 (采样点，至少1点)

        % --- 2. 从LFM信号中提取N个连续切片 ---
        lfm = tx(1, params.pos:params.pos+params.Ntau-1);
        sampled_slices = cell(1, N);
        for s = 1:N
            idx_start = (s-1) * slice_len + 1;
            idx_end = min(s * slice_len, Ntau);
            sampled_slices{s} = lfm(idx_start:idx_end);
        end

        % --- 3. ISCJ核心：累积循环转发 ---
        jam_pri = zeros(1, PRI_samp);

        current_pos = params.pos;  % 从脉冲起始位置开始转发

        for rd = 1:N
            for s = 1:rd
                % 除第1轮第1个切片外，每个切片前加时延
                if s > 1 || rd > 1
                    current_pos = current_pos + delay_samp;
                end

                slice_data = sampled_slices{s};
                slen = length(slice_data);

                % 检查边界，防止超出PRI
                if current_pos + slen - 1 <= PRI_samp
                    jam_pri(current_pos : current_pos + slen - 1) = ...
                        jam_pri(current_pos : current_pos + slen - 1) + Aj * slice_data;
                else
                    right_boundary = min(PRI_samp, current_pos + slen - 1);
                    copy_len = right_boundary - current_pos + 1;
                    if copy_len > 0
                        jam_pri(current_pos : right_boundary) = ...
                            jam_pri(current_pos : right_boundary) + Aj * slice_data(1:copy_len);
                    end
                end

                current_pos = current_pos + slen;
            end
        end

        % --- 4. 复制到所有PRI + 功率归一化 ---
        pure_jam(m,:) = repmat(jam_pri, 1, Np);
        pure_jam(m,:) = pure_jam(m,:) / sqrt(mean(abs(pure_jam(m,:)).^2)) * Aj;

        % 记录参数
        jam_info(m).M = N;        % 转发轮数 (= 切片个数)
        jam_info(m).N = N;        % 切片个数
        jam_info(m).period = period;
        jam_info(m).duty = duty;
    end
    end
