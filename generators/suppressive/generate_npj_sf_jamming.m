function [pure_jam, jam_info] = generate_npj_sf_jamming(tx, params, data_num)
    % generate_npj_sf_jamming - 噪声乘积干扰（NPJ）的存储-转发变体
    %
    % 与 generate_npj_jamming 的唯一区别：一个「存储块」的波形在 U 个 PRI 内
    % 完全复用，而不是原版的「每个样本抽一次噪声再 repmat」。
    %
    %   U = Np（缺省）→ 整帧同一段存储波形，与原版一致
    %   U = 1        → 每脉冲重新产生噪声（真实噪声干扰机）
    %   1 < U < Np   → 每 U 个 PRI 换一次
    %
    % 注意原版 generate_npj_jamming 在 Np>1 时没有做帧级归一化，
    % 总功率会变成 Aj²/Np；本版统一归一化到整帧 RMS = Aj（Np=1 时与原版等价，
    % 因为原版在 Np=1 下恰好也是 Aj）。
    %
    % 约定：输出整帧 RMS 归一化到 Aj = 10^(JNR/20)。

    fs       = params.fs;
    N_total  = params.N_total;
    Aj       = 10^(params.JNR/20);
    PRI_samp = params.PRI_samp;
    Ntau     = params.Ntau;
    Np       = params.Np;

    U = Np;
    if isfield(params, 'U') && ~isempty(params.U)
        U = round(params.U);
    end
    U = min(max(U, 1), max(Np, 1));

    drift = 0;
    if isfield(params, 'drift_per_pulse') && ~isempty(params.drift_per_pulse)
        drift = params.drift_per_pulse;
    end

    pure_jam = zeros(data_num, N_total);
    jam_info = struct('U', {}, 'n_blocks', {}, 'delay_samp', {}, 'random_phase', {});

    for m = 1:data_num
        jam_frame = zeros(1, N_total);
        stored_seg   = [];
        stored_delay = 0;
        stored_phase = 1;
        n_blocks     = 0;

        for p = 0:Np-1
            % ---- 块边界：抽一次噪声，块内复用 ----
            if mod(p, U) == 0
                n_blocks = n_blocks + 1;

                % 随机数调用顺序与原版 generate_npj_jamming 保持一致
                product_noise = randn([1, PRI_samp]) + 1j*randn([1, PRI_samp]);
                product_noise = product_noise / std(product_noise);

                lfm = tx(1, params.pos : params.pos + Ntau - 1);

                delay_time   = (-2 + rand() * 4) * 1e-7;
                stored_delay = round(delay_time * fs);

                noise_start  = randi([1, PRI_samp - Ntau + 1]);
                noise_segment = product_noise(noise_start : noise_start + Ntau - 1);

                stored_phase = exp(rand() * 2 * pi * 1i);

                npj_segment = lfm .* noise_segment;
                npj_segment = npj_segment / std(npj_segment) * stored_phase;
                stored_seg  = npj_segment;
            end

            left  = params.pos + stored_delay;
            right = left + Ntau - 1;
            if left < 1 || right > PRI_samp
                continue;   % 与原版一致：越界则本脉冲不放置
            end

            seg = Aj * sqrt(PRI_samp / Ntau) * stored_seg .* exp(1j * drift * p);
            idx = p * PRI_samp + (left:right);
            jam_frame(idx) = jam_frame(idx) + seg;
        end

        pwr = mean(abs(jam_frame).^2);
        if pwr > 0
            jam_frame = jam_frame / sqrt(pwr) * Aj;
        end
        pure_jam(m, :) = jam_frame;

        jam_info(m).U            = U;
        jam_info(m).n_blocks     = n_blocks;
        jam_info(m).delay_samp   = stored_delay;
        jam_info(m).random_phase = stored_phase;
    end
end
