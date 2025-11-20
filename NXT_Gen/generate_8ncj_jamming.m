% ==========================================================
% generate_spot_jamming.m - 生成瞄准式干扰样本
% ==========================================================
function [pure_jam] = generate_8ncj_jamming(tx, params, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);
PRI_samp = params.PRI_samp;
taup = params.taup;
ttau = params.ttau;
Ntau = params.Ntau;
Np = params.Np;

% 初始化输出
% samples = zeros(data_num, N_total);
% labels = ones(data_num, 1) * label;
pure_jam = zeros(data_num, N_total);
for m = 1:data_num
    % % --- 生成噪声 ---
    % white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    % white_noise = white_noise / std(white_noise); % 标准化

    % --- 1. 生成用于卷积的噪声源 ---
    % 这个噪声是干扰机内部产生的，用于生成干扰信号
    % 其长度应足够长以进行有效的卷积
    convolution_noise = randn([1, PRI_samp]) + 1j*randn([1, PRI_samp]);
    convolution_noise = convolution_noise / std(convolution_noise);

    % --- 2. 创建卷积核 (间歇采样的LFM信号) ---
    % 设置间歇采样的随机参数
    sampling_period = taup / (5 + randi(10)); % 采样周期
    sampling_duty = 20 + randi(30);           % 占空比

    % 生成单极性方波门控信号
    squa = (square((1/sampling_period)*2*pi*ttau, sampling_duty) + 1) / 2;
    % 将LFM信号与门控相乘，得到卷积核
    lfm = tx(1,params.pos:params.pos+params.Ntau-1);
    jam_kernel = lfm .* squa;

    % --- 3. 执行卷积 ---
    % 将噪声源与卷积核进行卷积
    % 'same' 选项确保输出长度与第一个输入 (噪声) 相同
    jam_conv_result = conv(convolution_noise, jam_kernel, 'same');

    % --- 4. 在一个PRI内生成转发干扰串 ---
    % 我们首先在一个PRI内生成干扰，然后将其复制到所有PRI
    jam_pri = zeros(1, PRI_samp);
    repetition_times = 5 + randi(5); % 转发5-10次

    for i = 1:repetition_times
        % 设置每次转发的随机延迟 (e.g., 1us to 5us)
        delay_time = (1 + rand() * 4) * 1e-6;
        delay_samp = round(delay_time * fs);

        % 干扰切片的起始位置
        if i == 1
            left_range = params.pos + delay_samp;
        else
            left_range = last_pos + delay_samp;
        end
        right_range = left_range + Ntau - 1;

        last_pos = left_range; % 记录位置供下次使用

        % 检查是否超出当前PRI的范围
        if right_range <= PRI_samp
            % 从卷积结果中取出一个脉宽长度的片段作为干扰信号
            % 为了增加随机性，可以从jam_conv_result的不同位置开始取
            start_point = randi(length(jam_conv_result) - Ntau);
            jam_segment = jam_conv_result(start_point : start_point + Ntau - 1);

            % 为每次转发设置一个随机幅度
            Aj_rand = Aj * (0.5 + rand());
            jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj_rand * jam_segment;
        end
    end

    % --- 5. 将单个PRI的干扰模板复制到整个信号长度 ---
    jam_signal = repmat(jam_pri, 1, Np);

    pure_jam(m,:) = repmat(jam_pri, 1, Np);
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
