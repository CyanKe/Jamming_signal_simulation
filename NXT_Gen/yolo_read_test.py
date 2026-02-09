"""
yolo_read_test.py - 读取MATLAB 7.3格式的STFT数据并绘制bounding box

功能：
1. 读取MATLAB 7.3格式的STFT数据文件
2. 将复数信号转换为模值（绝对值）作为黑白图像
3. 读取YOLO格式的bounding box文件
4. 在图像上绘制bounding box
"""

import h5py
import numpy as np
import matplotlib.pyplot as plt
import os
from pathlib import Path


def read_matlab_stft(mat_file_path):
    """
    读取MATLAB 7.3格式的STFT数据文件

    参数:
        mat_file_path: MATLAB文件路径

    返回:
        all_stfts: STFT数据 [freq_bins, time_bins, N]
    """
    print(f"正在读取文件: {mat_file_path}")

    with h5py.File(mat_file_path, 'r') as f:
        # 查看文件中的所有数据集
        print("文件中的数据集:")
        for key in f.keys():
            print(f"  - {key}")

        # 读取STFT数据
        if 'all_stfts' in f:
            all_stfts = f['all_stfts'][:]
            print(f"STFT数据形状: {all_stfts.shape}")
            print(f"STFT数据类型: {all_stfts.dtype}")

            # 检查数据类型，如果是结构化数组（MATLAB复数格式），需要转换
            if all_stfts.dtype.names is not None:
                print("数据是MATLAB复数格式（结构化数组），转换为标准复数")
                # MATLAB复数格式通常有'imag'和'real'字段
                real_part = all_stfts['real']
                imag_part = all_stfts['imag']
                all_stfts = real_part + 1j * imag_part
                print(f"转换后的数据类型: {all_stfts.dtype}")
            elif np.iscomplexobj(all_stfts):
                print("数据是复数类型")
            else:
                print("数据已经是实数类型")

            return all_stfts
        else:
            print("错误: 未找到'all_stfts'数据集")
            return None


def read_yolo_bbox(bbox_file_path):
    """
    读取YOLO格式的bounding box文件

    参数:
        bbox_file_path: YOLO bbox文件路径

    返回:
        bboxes: bounding box列表 [N, 5]，格式: [class_id, x_center, y_center, width, height]
    """
    print(f"正在读取bounding box文件: {bbox_file_path}")

    if not os.path.exists(bbox_file_path):
        print(f"警告: 文件不存在 {bbox_file_path}")
        return None

    bboxes = []
    with open(bbox_file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                # 解析YOLO格式: class_id x_center y_center width height
                parts = line.split()
                if len(parts) == 5:
                    bbox = [float(p) for p in parts]
                    bboxes.append(bbox)

    bboxes = np.array(bboxes)
    print(f"读取到 {len(bboxes)} 个bounding box")
    return bboxes


def convert_to_grayscale(stft_data):
    """
    将STFT数据转换为灰度图像

    参数:
        stft_data: STFT数据（实数或复数）

    返回:
        gray_image: 灰度图像
    """
    # 如果是复数，计算模值
    if np.iscomplexobj(stft_data):
        magnitude = np.abs(stft_data)
    else:
        magnitude = stft_data

    # 归一化到0-255
    if magnitude.max() > 0:
        gray_image = (magnitude / magnitude.max() * 255).astype(np.uint8)
    else:
        gray_image = np.zeros_like(magnitude, dtype=np.uint8)

    return gray_image


def draw_bbox_on_image(image, bboxes, time_bins, freq_bins, time_range=None, freq_range=None):
    """
    在图像上绘制bounding box

    参数:
        image: 灰度图像
        bboxes: YOLO格式的bounding box [N, 5]
        time_bins: 时间维度的bin数量
        freq_bins: 频率维度的bin数量
        time_range: 时间范围 [t_min, t_max] (μs)
        freq_range: 频率范围 [f_min, f_max] (MHz)

    返回:
        fig: matplotlib figure对象
    """
    fig, ax = plt.subplots(figsize=(12, 6))

    # 转置图像以匹配参考代码的行为（时间轴在x轴，频率轴在y轴）
    image = image.T

    # 显示图像
    if time_range is not None and freq_range is not None:
        extent = [time_range[0], time_range[1], freq_range[0], freq_range[1]]
        ax.imshow(image, aspect='auto', cmap='gray', extent=extent)
        ax.set_xlabel('Time (μs)')
        ax.set_ylabel('Frequency (MHz)')
    else:
        ax.imshow(image, aspect='auto', cmap='gray')
        ax.set_xlabel('Time (bins)')
        ax.set_ylabel('Frequency (bins)')

    # 绘制bounding box
    if bboxes is not None and len(bboxes) > 0:
        for bbox in bboxes:
            class_id = int(bbox[0])
            x_center = bbox[1]
            y_center = bbox[2]
            width = bbox[3]
            height = bbox[4]

            # 转换为像素坐标
            x_min = (x_center - width/2) * time_bins
            x_max = (x_center + width/2) * time_bins
            y_min = (y_center - height/2) * freq_bins
            y_max = (y_center + height/2) * freq_bins

            # 转换为实际坐标（如果提供了范围）
            if time_range is not None and freq_range is not None:
                t_min = time_range[0] + (x_min / time_bins) * (time_range[1] - time_range[0])
                t_max = time_range[0] + (x_max / time_bins) * (time_range[1] - time_range[0])
                f_min = freq_range[0] + (y_min / freq_bins) * (freq_range[1] - freq_range[0])
                f_max = freq_range[0] + (y_max / freq_bins) * (freq_range[1] - freq_range[0])

                # 绘制矩形
                rect = plt.Rectangle((t_min, f_min), t_max-t_min, f_max-f_min,
                                   fill=False, edgecolor='red', linewidth=2)
                ax.add_patch(rect)

                # 添加标签
                ax.text(t_min, f_max + 0.5, f'Class:{class_id}',
                       color='red', fontsize=8, fontweight='bold')
            else:
                # 绘制矩形（像素坐标）
                rect = plt.Rectangle((x_min, y_min), x_max-x_min, y_max-y_min,
                                   fill=False, edgecolor='red', linewidth=2)
                ax.add_patch(rect)

                # 添加标签
                ax.text(x_min, y_max + 1, f'Class:{class_id}',
                       color='red', fontsize=8, fontweight='bold')

    ax.set_title('STFT with YOLO Bounding Boxes')
    plt.colorbar(ax.images[0], ax=ax, label='Magnitude (dB)')
    plt.tight_layout()

    return fig


def main():
    """
    主函数：读取数据并绘制图像
    """
    # 设置路径
    base_dir = Path(r'd:\VScode\Jamming_signal_simulation\NXT_Gen')
    jnr_dir = base_dir / '260207' / 'JNR_+50'

    # 文件路径
    mat_file = jnr_dir / 'val_echo_stfts.mat'
    bbox_dir = jnr_dir / 'bbox_labels'

    # 检查文件是否存在
    if not mat_file.exists():
        print(f"错误: 文件不存在 {mat_file}")
        return

    # 读取STFT数据
    all_stfts = read_matlab_stft(mat_file)

    if all_stfts is None:
        return

    # 获取STFT尺寸 (freq_bins, time_bins, N)
    freq_bins, time_bins, N = all_stfts.shape
    print(f"STFT尺寸: {freq_bins} 频率bins, {time_bins} 时间bins, {N} 个样本")

    # 设置时间范围和频率范围（根据实际参数）
    # 假设采样频率80MHz，PRI=100μs，中心频率40MHz，带宽10MHz
    fs = 80e6  # 采样频率
    PRI = 100e-6  # 脉冲重复间隔
    fc = 40e6  # 中心频率
    B = 10e6  # 带宽

    time_range = [0, PRI * 1e6]  # μs
    freq_range = [(fc - B/2) / 1e6, (fc + B/2) / 1e6]  # MHz

    print(f"时间范围: {time_range} μs")
    print(f"频率范围: {freq_range} MHz")

    # 创建输出目录
    output_dir = base_dir / 'output_images'
    output_dir.mkdir(exist_ok=True)

    # 处理多个样本
    num_samples_to_plot = min(5, N)  # 最多绘制5个样本
    for sample_idx in range(num_samples_to_plot):
        print(f"\n--- 处理样本 {sample_idx+1}/{num_samples_to_plot} ---")

        # 读取bounding box
        bbox_file = bbox_dir / f'sample_{sample_idx+1:06d}.txt'
        bboxes = read_yolo_bbox(bbox_file)

        # 获取样本的STFT数据 (freq_bins, time_bins)
        stft_data = all_stfts[:, :, sample_idx]

        # 转换为灰度图像
        gray_image = convert_to_grayscale(stft_data)

        # 绘制图像
        fig = draw_bbox_on_image(gray_image, bboxes, time_bins, freq_bins, time_range, freq_range)

        # 保存图像
        output_file = output_dir / f'stft_bbox_sample_{sample_idx+1}.png'
        fig.savefig(output_file, dpi=150, bbox_inches='tight')
        print(f"图像已保存到: {output_file}")

        # 打印bounding box信息
        if bboxes is not None and len(bboxes) > 0:
            print(f"Bounding Box信息 (样本 {sample_idx+1}):")
            for i, bbox in enumerate(bboxes):
                print(f"  Box {i+1}: class={int(bbox[0])}, "
                      f"x_center={bbox[1]:.4f}, y_center={bbox[2]:.4f}, "
                      f"width={bbox[3]:.4f}, height={bbox[4]:.4f}")
        else:
            print(f"样本 {sample_idx+1} 没有bounding box")

        # 关闭figure以释放内存
        plt.close(fig)

    print(f"\n=== 完成 ===")
    print(f"所有图像已保存到: {output_dir}")


if __name__ == '__main__':
    main()
