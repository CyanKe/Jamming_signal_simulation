function [pure_jam,jam_info] = generate_isrj_jamming(tx, params, data_num)
    % generate_isrj_jamming - 生成间歇采样干扰
    % https://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=9173164
    % tx: 包含 LFM 信号的发射数据
    % params: 参数结构体 (需包含 fs, N_total, JNR, PRI_samp, Ntau, Np, pos, M)
    % data_num: 生成样本数
    % 输出:
    %   pure_jam - 干扰信号
    %   jam_info - 干扰参数信息 (新增，用于metadata记录)

    % 解包参数
    PRI_samp = params.PRI_samp;
    N_total = params.N_total;
    As = 10^(params.SNR/20);
    Aj = 10^(params.JNR/20);
    ttau = params.ttau;
    Ntau = params.Ntau;
    fs = params.fs;
    Np = params.Np;


    % 初始化输出
    % samples = zeros(data_num, N_total);
    % labels = ones(data_num, 1) * label;
    pure_jam = zeros(data_num, N_total);
    jam_info = struct('M', {}, 'N', {});  % 新增：记录ISRJ参数

    for m = 1:data_num
        % % --- 生成噪声 ---
        % white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
        % white_noise = white_noise / std(white_noise); % 标准化

        % --- 1. 从数组中随机选择ISRJ参数 ---
        %     repetition_times_arr= [4,3,2];    %重复次数M
        % sampling_times_arr = [4,3,2];     %采样次数N
        % index1 = randi([1 4]);          % 随机选择周期 (索引1或2)
        % N = sampling_times_arr(index1);
        % 
        % index2 = randi([1 4]);      % 随机选择占空比 (索引1到4)
        % M = repetition_times_arr(index2);



        M = randi([2 4]); %转发次数
        N = randi([2 4]); %采样次数
        % M = 4;N = 3;

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

        % 循环多次转发，形成一串等间隔的假目标
        for i = 1:M
            left_range = params.pos + i * delay_samp;
            right_range = left_range + Ntau - 1;
            random_phase = exp(rand*2*pi*1i);
            jam_slice = jam_slice*random_phase;
            % 检查是否超出当前PRI的范围，避免索引错误
            if right_range <= PRI_samp
                jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj * jam_slice*exp(rand*2*pi*1i);
            else
                % 只要 lfm 的长度与目标区域的长度不一致，就取较小的那个长度
                right_boundary = min(PRI_samp, left_range + length(lfm) - 1);
                % 重新定义索引范围并赋值
                jam_pri(left_range:right_boundary) = jam_pri(left_range:right_boundary) + ...
                    Aj * jam_slice(1 : (right_boundary - left_range + 1))*exp(rand*2*pi*1i);
            end
        end

        pure_jam(m,:) = repmat(jam_pri, 1, Np);
        pure_jam(m,:) = pure_jam(m,:) / sqrt(mean(abs(pure_jam(m,:)).^2)) * Aj;

        % 记录当前样本的参数信息
        jam_info(m).M = M;  % 转发次数
        jam_info(m).N = N;  % 采样次数

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