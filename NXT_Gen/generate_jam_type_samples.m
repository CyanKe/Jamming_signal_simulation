% ==========================================================
% generate_jam_type_samples.m - 根据类型生成特定干扰样本的函数
% 供 main_generator.m 调用
% ==========================================================
function [samples_out, labels_out] = generate_jam_type_samples(jam_type, tx, common_params, label, num_to_generate)
    % 初始化输出，防止在未知类型时出错
    samples_out = [];
    labels_out = [];

    fprintf('正在生成 %d 个 [%s] 类型的样本, 标签为 %d...\n', num_to_generate, jam_type, label);

    % 根据干扰类型调用相应的生成函数
    switch jam_type
        case 'spot'
            % 为瞄准干扰单独设置JNR或其他参数
            jam_specific_params = common_params;
            jam_specific_params.JNR = 50; % 瞄准干扰通常功率更集中
            % 调用瞄准干扰生成函数
            [samples_out, labels_out] = generate_spot_jamming(tx, jam_specific_params, label, num_to_generate);
        
        case 'deceptive'
            % 欺骗式干扰使用公共JNR或可以单独设置
            jam_specific_params = common_params; % 或者根据需要修改 jam_specific_params.JNR = ...
            % 调用欺骗式干扰生成函数
            [samples_out, labels_out] = generate_deceptive_jamming(tx, jam_specific_params, label, num_to_generate);
        
        % 你可以在这里添加更多干扰类型
        % case 'new_jam_type'
        %     jam_specific_params = common_params;
        %     % 根据需要修改 jam_specific_params
        %     [samples_out, labels_out] = generate_new_jamming_type(tx, jam_specific_params, label, num_to_generate);
            
        otherwise
            warning('未知干扰类型: %s. 请检查 generation_plan 或添加相应的 case。', jam_type);
    end
end