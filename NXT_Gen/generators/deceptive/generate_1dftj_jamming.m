function [pure_jam,bbox_info,jam_info] = generate_1dftj_jamming(tx, params, data_num)
% generate_1dftj_jamming - 生成密集假目标干扰
% 输出:
%   pure_jam - 干扰信号
%   bbox_info - 边界框信息
%   jam_info - 干扰参数信息 (新增，用于metadata记录)

% 解包参数
fs = params.fs;
N_total = params.N_total;
As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);
PRI_samp = params.PRI_samp;
Ntau = params.Ntau;
Np = params.Np;
pos = params.pos;
B = params.B;

% 初始化输出
% samples = zeros(data_num, N_total);
% labels = ones(data_num, 1) * label;
pure_jam = zeros(data_num, N_total);
jam_info = struct('k', {}, 'delay_times', {});  % 新增：记录参数信息

for m = 1:data_num
    % --- 生成噪声 ---
    % white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    % white_noise = white_noise / std(white_noise); % 标准化

    % --- 1. 设置假目标参数 ---
    k = randi([4, 8]);  % 随机产生4-8个假目标
    delay_times = zeros(1, k);  % 记录每个假目标的延迟时间

    % --- 2. 创建一个PRI长度的干扰信号模板 ---
    % 我们首先在一个PRI内生成假目标，然后将其复制到所有PRI
    jam_pri = zeros(1, PRI_samp);

    % 存储bounding box信息
    bbox_info = [];
    x_min = inf; x_max = -inf;
    y_min = inf; y_max = -inf;

    % --- 3. 循环生成每个假目标并放入模板 ---
    for i = 1:k
        % 随机延迟时间 (1-10us)，并转换为采样点数
        delay_time = randi([4, 10])*1e-6 ;
        delay_times(i) = delay_time;  % 记录延迟时间
        delay_samp = round(delay_time * fs);
        if i == 1
            % 第一个假目标相对于真实目标的位置
            left_range = pos + delay_samp*i;
        else
            % 后续假目标相对于前一个假目标的位置
            left_range = last_pos + delay_samp;
        end
        right_range = left_range + Ntau - 1;

        % 记录当前假目标的位置，供下一个假目标参考
        last_pos = left_range;

        % 检查假目标是否超出当前PRI的范围，如果超出则不添加
        if left_range <= PRI_samp
            % 为每个假目标设置一个随机幅度 (0.5到1.5倍的Aj)
            % Aj_rand = Aj * (0.5 + rand());
            random_phase = exp(rand*2*pi*1i);
            lfm = tx(1, pos : pos + Ntau - 1)*random_phase;
            if right_range <= PRI_samp
                jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj * lfm;
            else
                % 只要 lfm 的长度与目标区域的长度不一致，就取较小的那个长度
                right_boundary = min(PRI_samp, left_range + length(lfm) - 1);
                % 重新定义索引范围并赋值
                jam_pri(left_range:right_boundary) = jam_pri(left_range:right_boundary) + ...
                    Aj * lfm(1 : (right_boundary - left_range + 1));
            end
        end
        % 计算bounding box
        % 时域范围
        x_min = min(x_min,left_range);
        x_max = max(x_max,right_range);
        x_max = min(x_max,PRI_samp);

        % 频域范围（LFM信号带宽）
        y_min = min(y_min,- B / 2);  % 最低频率
        y_max = max(y_max, B / 2);  % 最高频率
    end

    % 添加到bounding box列表
    bbox_info = [bbox_info; x_min, y_min, x_max, y_max];

    % 复制到所有PRI
    jam_signal = repmat(jam_pri, 1, Np);

    % 【修正】功率归一化到目标JNR
    actual_power = mean(abs(jam_signal).^2);  % 实际功率
    target_power = Aj^2;                       % 目标功率
    if actual_power > 0
        jam_signal = jam_signal * sqrt(target_power / actual_power);
    end

    pure_jam(m,:) = jam_signal;

    % 记录当前样本的参数信息
    jam_info(m).k = k;
    jam_info(m).delay_times = delay_times;  % 单位：秒

    % % --- 4. 将单个PRI的干扰模板复制到整个信号长度 ---
    % jam_signal = repmat(jam_pri, 1, Np);
    %
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
