function oneHotLabels = convertLabelsToOneHot(labels, numClasses)
% CONVERTLABELSTOONEHOT 将多标签一维向量转换为多热编码
%
%   oneHotLabels = CONVERTLABELSTOONEHOT(labels, numClasses)
%
%   输入:
%     labels     - 包含多标签的一维向量的单元格数组，例如 {[1], [1,5,9], [2,3]}
%     numClasses - 标签的最大类别数，例如如果标签是1-9，则为9
%
%   输出:
%     oneHotLabels - 转换后的多热编码矩阵，每行代表一个样本，每列代表一个类别。

    numSamples = length(labels);
    oneHotLabels = zeros(numSamples, numClasses); % 初始化一个全零矩阵

    for i = 1:numSamples
        currentLabels = labels{i}; % 获取当前样本的标签
        for j = 1:length(currentLabels)
            labelIndex = currentLabels(j); % 获取当前标签的值
            if labelIndex >= 1 && labelIndex <= numClasses
                oneHotLabels(i, labelIndex) = 1; % 将对应位置设置为1
            else
                warning('标签值 %d 超出有效范围 [1, %d] 或小于1，已忽略。', labelIndex, numClasses);
            end
        end
    end
end