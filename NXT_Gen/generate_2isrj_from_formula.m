% =====================================================================
% generate_isrj_from_formula.m - 严格根据ISRJ公式生成干扰样本
% =====================================================================
function [pure_jam] = generate_2isrj_from_formula(tx, params, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
Aj = 10^(params.JNR/20);
PRI_samp = params.PRI_samp;
Ntau = params.Ntau; % 雷达脉冲宽度 (采样点数)
Np = params.Np;

% --- 1. 定义ISRJ公式中的核心参数 ---
% 这些参数可以设置为固定值，或者像原代码一样从数组中随机选择
M = 2; % M: 切片总数 (Number of slices)
N = 4; % N: 每个切片的转发次数 (Number of forwarding), 公式中n从0到N，所以是N+1次

% Ti: 每个切片的宽度 (时间)。这里我们根据总脉宽Ntau和切片数M来计算
% 确保所有切片加起来正好是整个脉冲
Ti_samp = floor(Ntau / M); % 每个切片的宽度 (采样点数)
Ti = Ti_samp / fs;         % 每个切片的宽度 (秒)

% --- 安全检查: 确保参数合理 ---
if M * Ti_samp > Ntau
    error('参数错误: 切片总长度超过了原始脉冲宽度!');
end

% 初始化输出
pure_jam = zeros(data_num, N_total);

for d = 1:data_num
    % 在一个PRI内生成干扰，之后再复制
    jam_pri = zeros(1, PRI_samp);
    
    % 提取单个干净的LFM脉冲信号
    lfm = tx(1, params.pos : params.pos + Ntau - 1);

    % --- 2. 实现公式中的双重循环 ---
    % 外层循环: 遍历每一个切片 (对应公式中的 Σ_m)
    for m = 1:M
        % --- 步骤 2.1: 从LFM信号中提取第 m 个切片 ---
        % 计算切片在lfm信号中的起始和结束索引
        slice_start_idx = (m-1) * Ti_samp + 1;
        slice_end_idx = m * Ti_samp;
        
        % 得到第m个切片的内容 S(t - mT_i)
        current_slice = lfm(slice_start_idx : slice_end_idx);
        
        % 内层循环: 对当前切片进行 N+1 次转发 (对应公式中的 Σ_n)
        for n = 0:N
            % --- 步骤 2.2: 计算当前转发的延迟时间 ---
            % 根据公式 rect( (t - (nM+n+m)Ti) / Ti )
            % 延迟项为 time_delay = (n*M + n + m) * Ti
            % 注意：公式中 S(t-mTi) 暗示第m个切片本身就有一个m*Ti的固有延迟，
            % 而 rect(...) 定义了转发窗的中心。为简化，我们将总延迟视为窗的起始位置。
            % 延迟的起点是真实信号的起点 params.pos
            
            % 总延迟 (单位: 秒)
            delay_time = (n * M + n + m) * Ti;
            % 转换为采样点数
            delay_samp = round(delay_time * fs);
            
            % --- 步骤 2.3: 将切片放置到延迟后的位置 ---
            % 计算切片在jam_pri向量中的放置位置
            left_range = params.pos + delay_samp;
            right_range = left_range + Ti_samp - 1;
            
            % 检查是否超出当前PRI的范围，避免索引错误
            if right_range <= PRI_samp
                % 使用加法，因为不同切片的不同转发可能会在时间上重叠
                jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj * current_slice;
            end
        end
    end
    
    % --- 3. 将单个PRI的干扰模板复制到整个信号长度 ---
    pure_jam(d,:) = repmat(jam_pri, 1, Np);
end

end
