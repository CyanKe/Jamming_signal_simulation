% ==========================================================
% generate_spot_jamming.m - 生成瞄准式干扰样本
% ==========================================================
function [pure_jam,bbox_info] = generate_2isrj_jamming(tx, params, data_num)
% 解包参数
PRI_samp = params.PRI_samp;
N_total = params.N_total;
As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);
ttau = params.ttau;
Ntau = params.Ntau;
fs = params.fs;
Np = params.Np;
B = params.B;

repetition_times_arr= [5,4,3,2];    %重复次数M
sampling_times_arr = [4,3,2,1];     %采样次数N

% 初始化输出
% samples = zeros(data_num, N_total);
% labels = ones(data_num, 1) * label;
pure_jam = zeros(data_num, N_total);

for m = 1:data_num
    % % --- 生成噪声 ---
    % white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    % white_noise = white_noise / std(white_noise); % 标准化

    % --- 1. 从数组中随机选择ISRJ参数 ---
    index1 = randi([1 4]);          % 随机选择周期 (索引1或2)
    N = sampling_times_arr(index1);

    index2 = randi([1 4]);      % 随机选择占空比 (索引1到4)
    M = repetition_times_arr(index2);
    M = 4;N = 3;

    % --- 2. 生成采样方波并对LFM信号进行切片 ---
    % 使用与LFM脉冲相同的时间轴ttau来生成方波
    [squa,delay_samp] = gen_square_wave(M+1, N, Ntau);

    % 得到被采样/切片的LFM信号，这是我们要转发的干扰基本单元
    lfm = tx(1,params.pos:params.pos+params.Ntau-1);
    jam_slice = lfm .* squa;

    % plot(real(lfm))
    % --- 3. 在一个PRI内生成转发干扰串 ---
    % 我们首先在一个PRI内生成干扰，然后将其复制到所有PRI
    jam_pri = zeros(1, PRI_samp);

    % 存储bounding box信息
    bbox_info = [];
    x_min = inf; x_max = -inf;
    y_min = inf; y_max = -inf;


    % 循环多次转发，形成一串等间隔的假目标
    for i = 1:M
        % 干扰切片的起始位置 = 真实目标位置 + 累积的延迟
        % if i~=1
            left_range = params.pos + i * delay_samp;
            right_range = left_range + Ntau - 1;

            % 检查是否超出当前PRI的范围，避免索引错误
            if right_range <= PRI_samp
                jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj * jam_slice;
            else
                % 只要 lfm 的长度与目标区域的长度不一致，就取较小的那个长度
                right_boundary = min(PRI_samp, left_range + length(lfm) - 1);
                % 重新定义索引范围并赋值
                jam_pri(left_range:right_boundary) = jam_pri(left_range:right_boundary) + ...
                    Aj * jam_slice(1 : (right_boundary - left_range + 1));
            end
        % 计算bounding box
        % 时域范围
        x_min = min(x_min,left_range);
        x_max = max(x_max,right_range);
        x_max = min(x_max,PRI_samp);

        % 频域范围（LFM信号带宽）
        y_min = min(y_min,- B / 2);  % 最低频率
        y_max = max(y_max, B / 2);  % 最高频率
        % end

    end

    pure_jam(m,:) = repmat(jam_pri, 1, Np);
    % 添加到bounding box列表
    bbox_info = [bbox_info; x_min, y_min, x_max, y_max];
    pure_jam(m,:) = repmat(jam_pri, 1, Np);

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
