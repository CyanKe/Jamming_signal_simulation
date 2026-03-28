function oneHotLabels = convertLabelsToOneHot(labels, numClasses)
% CONVERTLABELSTOONEHOT 将多标签一维向量转换为多热编码
%
%   oneHotLabels = CONVERTLABELSTOONEHOT(labels, numClasses)
%
%   输入:
%     labels     - 包含多标签的一维向量的单元格数组 (例如 {[1], [1,5,9], [2,3]})
%                  或者一个普通行向量，表示单个样本的标签 (例如 [1] 或 [1,5,9])
%     numClasses - 标签的最大类别数，例如如果标签是1-9，则为9
%
%   输出:
%     oneHotLabels - 转换后的多热编码矩阵，每行代表一个样本，每列代表一个类别。

    if iscell(labels)
        % 如果是单元格数组，按多个样本处理
        numSamples = length(labels);
        oneHotLabels = zeros(numSamples, numClasses);

        for i = 1:numSamples
            currentLabels = labels{i}; % 获取当前样本的标签 (使用花括号索引)
            
            % 确保 currentLabels 是行向量，以防万一它被创建为列向量
            if iscolumn(currentLabels)
                currentLabels = currentLabels'; 
            end

            for j = 1:length(currentLabels)
                labelIndex = currentLabels(j); % 获取当前标签的值
                if labelIndex >= 1 && labelIndex <= numClasses
                    oneHotLabels(i, labelIndex) = 1; % 将对应位置设置为1
                else
                    warning('样本 %d, 标签值 %d 超出有效范围 [1, %d] 或小于1，已忽略。', i, labelIndex, numClasses);
                end
            end
        end
    else
        % 如果不是单元格数组，假定它是单个样本的标签向量
        numSamples = 1; % 只有一个样本
        oneHotLabels = zeros(numSamples, numClasses);
        
        currentLabels = labels; % 直接使用输入的 labels 作为当前样本的标签 (不使用花括号索引)

        % 确保 currentLabels 是行向量
        if iscolumn(currentLabels)
            currentLabels = currentLabels'; 
        end

        for j = 1:length(currentLabels)
            labelIndex = currentLabels(j); % 获取当前标签的值
            if labelIndex >= 1 && labelIndex <= numClasses
                oneHotLabels(1, labelIndex) = 1; % 将对应位置设置为1 (只有一行)
            else
                warning('标签值 %d 超出有效范围 [1, %d] 或小于1，已忽略。', labelIndex, numClasses);
            end
        end
    end
end
