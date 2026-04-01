% =====================================================================
% generate_11cij_jamming.m - 生成切片与交织干扰干扰样本
% =====================================================================
function [pure_jam, jam_info] = generate_11cij_jamming(tx, params, data_num)
% generate_11cij_jamming - 生成切片交织干扰
% 输出:
%   pure_jam - 干扰信号
%   jam_info - 干扰参数信息 (用于metadata记录)
%
% CIJ特点：转发片段之间无采样间隔，STFT图表现为连续信号
% 与ISRJ区别：ISRJ转发片段之间有间隔，STFT图不连续

% 解包参数
fs = params.fs;
N_total = params.N_total;
Aj = 10^(params.JNR/20);
PRI_samp = params.PRI_samp;
Ntau = params.Ntau; % 雷达脉冲宽度 (采样点数 T)
Np = params.Np;

% --- 1. 定义 C&IJ 公式中的核心参数 ---
% a: 每个段的时隙数 (每个采样片重复填充的总次数)
% b: 采样段数 (整个脉冲内进行采样的次数)
a = randi([2 4]); 
b = randi([2 4]); 

% 计算总分段数
total_segments = a * b;

% 计算每一个小切片的宽度 (T/ab)
T_seg_samp = floor(Ntau / total_segments);

% 初始化输出
pure_jam = zeros(data_num, N_total);
jam_info = struct('a', {}, 'b', {}, 'total_segments', {}, 'is_continuous', {});  % CIJ参数

for d = 1:data_num
    jam_pri = zeros(1, PRI_samp);
    
    % 提取单个干净的 LFM 信号 S(t)
    lfm = tx(1, params.pos : params.pos + Ntau - 1);

    % --- 2. 实现公式 (7) 的采样和公式 (6) 的重组 ---
    
    % 外层循环 i: 对应公式中的 b，即采样过程
    for i = 0 : b-1
        % 计算当前采样的起始位置 (在原始脉冲中的位置)
        % 每个大周期长度是 a * T_seg_samp，采样其中的第一段
        sample_start = i * a * T_seg_samp + 1;
        sample_end   = sample_start + T_seg_samp - 1;
        
        % 提取切片 p(t) —— 对应公式 (7)
        if sample_end <= length(lfm)
            current_slice = lfm(sample_start : sample_end);
        else
            continue; % 防止越界
        end
        
        % 内层循环 k: 对应公式 (6) 中的 summation a-1
        % 将提取到的切片重复填充到紧随其后的 a 个位置中
        for k = 0 : a-1
            % 计算转发的延迟量 (k * T/ab)
            % 注意：这里相对于采样点的偏移是 k*T_seg_samp
            % 相对于脉冲起点的总偏移是 (i*a + k) * T_seg_samp
            
            delay_samp = (i * a + k) * T_seg_samp;
            
            % 放置到干扰信号向量中
            left_range = params.pos + delay_samp;
            right_range = left_range + T_seg_samp - 1;
            
            if right_range <= PRI_samp
                % C&IJ 通常是直接填充覆盖，形成连续信号
                jam_pri(left_range:right_range) = Aj * current_slice;
            end
        end
    end

    % --- 3. 记录CIJ参数信息 ---
    jam_info(d).a = a;                      % 每段的时隙数
    jam_info(d).b = b;                      % 采样段数
    jam_info(d).total_segments = a * b;     % 总分段数
    jam_info(d).is_continuous = true;       % CIJ特点：转发无间隔，STFT连续

    % --- 4. 复制到所有脉冲 ---
    pure_jam(d,:) = repmat(jam_pri, 1, Np);
end

end