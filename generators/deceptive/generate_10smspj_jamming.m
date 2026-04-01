function [pure_jam, jam_info] = generate_10smspj_jamming(tx, params, data_num)
% generate_smspj_jamming: 利用已有的发射信号片段生成 SMSPJ 干扰
% tx: 包含 LFM 信号的发射数据
% params: 参数结构体 (需包含 fs, N_total, JNR, PRI_samp, Ntau, Np, pos, M)
% data_num: 生成样本数
% 输出:
%   pure_jam - 干扰信号
%   jam_info - 干扰参数信息 (用于metadata记录)

% --- 解包参数 ---
fs = params.fs;
N_total = params.N_total;
Aj = 10^(params.JNR/20);
PRI_samp = params.PRI_samp;
Ntau = params.Ntau;
Np = params.Np; 
pos = params.pos;
B = params.B;
M = randi([4 8]); % 扫频分段数 (M需为整数)

% 初始化输出
pure_jam = zeros(data_num, N_total);
jam_info = struct('M', {}, 'slope_factor', {});  % M: 扫频分段数, slope_factor: 斜率倍增因子

for m = 1:data_num
    % --- 1. 提取原波形 ---
    % 假设 tx 的 pos 处是纯净的 LFM 信号
    lfm = tx(1, pos : pos + Ntau - 1);

    % --- 2. 设置SMSPJ参数 ---
    M = randi([4 8]); % 扫频分段数 (M需为整数)

    % --- 3. 生成 SMSPJ 子波形 (核心步骤) ---
    % 通过抽取(1:M:end)实现时域压缩 M 倍，斜率变为 M*mu
    % 抽取后的长度约为 Ntau/M
    T = Ntau / fs;
    mu = B / T;
    mu_prime = M * mu; % 斜率只增加 M 倍
    Tj_samples = floor(Ntau / M);
    t_sub = (0 : Tj_samples-1) / fs;

    % 直接生成子波形
    sub_wave = exp(1j * pi * mu_prime * t_sub.^2).* exp(-1j * pi * B * t_sub);

    % --- 4. 重复拼接子波形 ---
    % 将压缩后的子波形重复 M 次，使其总长度回到 Ntau 左右
    smsp_pulse = repmat(sub_wave, 1, M);

    % 修正因整除导致的微小长度差异，确保与 Ntau 完全一致
    len_diff = Ntau - length(smsp_pulse);
    if len_diff > 0
        % 如果短了，补零或补齐最后一采样
        smsp_pulse = [smsp_pulse, zeros(1, len_diff)];
    elseif len_diff < 0
        % 如果长了，截断
        smsp_pulse = smsp_pulse(1 : Ntau);
    end

    % --- 5. 构造单 PRI 模板 ---
    jam_pri = zeros(1, PRI_samp);

    % 设置干扰延迟 (例如相对于目标延迟 10us)
    % 在实际对抗中，干扰通常比目标快或重合，这里设为 5us
    delay_samp = round(randn()*5e-6 * fs);
    target_pos = pos + delay_samp;

    right_range = target_pos + Ntau - 1;

    % 检查是否越界并注入干扰
    if right_range <= PRI_samp
        jam_pri(target_pos : right_range) = Aj * smsp_pulse;
    end

    % --- 6. 记录参数信息 ---
    jam_info(m).M = M;              % 扫频分段数
    jam_info(m).slope_factor = M;   % 斜率倍增因子

    % --- 7. 复制到所有脉冲 ---
    pure_jam(m, :) = repmat(jam_pri, 1, Np);
end

end