% ==========================================================
% generate_spot_jamming.m - 生成瞄准式干扰样本
% ==========================================================
function [pure_jam] = generate_2isrj_jamming(tx, params, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);
PRI_samp = params.PRI_samp;
ttau = params.ttau;
Ntau = params.Ntau;
Np = params.Np;
repetition_times_arr=[4,3,2,1];   %重复次数
period_arr=[25e-7, 5e-6, 10e-6];    %采样脉冲周期 taup / period = 4 或 2，表示采样次数
duty_arr=[20,25,33.33,50];  %占空比


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
    sampling_period = period_arr(index1);

    index2 = randi([1 4]);      % 随机选择占空比 (索引1到4)
    sampling_duty = duty_arr(index2);

    % 关键：转发次数与占空比通过同一个索引index2关联
    repetition_times = repetition_times_arr(index2);

    % --- 2. 生成采样方波并对LFM信号进行切片 ---
    % 使用与LFM脉冲相同的时间轴ttau来生成方波
    squa = (square((1/sampling_period)*2*pi*ttau, sampling_duty) + 1) / 2; % 单极性方波

    % 得到被采样/切片的LFM信号，这是我们要转发的干扰基本单元
    lfm = tx(1,params.pos:params.pos+params.Ntau-1);
    jam_slice = lfm .* squa;

    % --- 3. 在一个PRI内生成转发干扰串 ---
    % 我们首先在一个PRI内生成干扰，然后将其复制到所有PRI
    jam_pri = zeros(1, PRI_samp);

    % 计算每次转发的固定延迟时间，即采样脉冲的宽度 ("on" time)
    delay_time = sampling_period * (sampling_duty / 100);
    delay_samp = round(delay_time * fs); % 转换为采样点数

    % 循环多次转发，形成一串等间隔的假目标
    for i = 1:repetition_times+1
        % 干扰切片的起始位置 = 真实目标位置 + 累积的延迟
        left_range = params.pos + i * delay_samp;
        right_range = left_range + Ntau - 1;

        % 检查是否超出当前PRI的范围，避免索引错误
        if right_range <= PRI_samp
            jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj * jam_slice;
        end
    end
    
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
