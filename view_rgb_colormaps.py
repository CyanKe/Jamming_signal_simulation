#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
view_rgb_colormaps.py - 交互式查看STFT RGB Colormap数据

双击样本切换, 鼠标滚轮翻页, 键盘方向键导航。
自动加载同目录下的 metadata.json 显示标签和JNR信息。

用法:
    python view_rgb_colormaps.py
    python view_rgb_colormaps.py output/fixed/JNR_+10/test_echo_stfts_rgb.mat
"""

import sys
import json
from pathlib import Path
import h5py
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider, Button


class ColormapViewer:
    def __init__(self, rgb_path):
        self.rgb_path = Path(rgb_path)
        if not self.rgb_path.exists():
            raise FileNotFoundError(f"文件不存在: {rgb_path}")

        # --- 加载 RGB 数据 (所有 colormap) ---
        print(f"加载: {self.rgb_path}")
        with h5py.File(self.rgb_path, 'r') as f:
            self.colormap_names = sorted([k[4:] for k in f.keys() if k.startswith('rgb_')])
            if not self.colormap_names:
                raise ValueError("文件中没有 rgb_* 变量")

            # 读取维度信息 (从第一个 colormap)
            first = f[f'rgb_{self.colormap_names[0]}'][:]
            # HDF5: [3, W, H, N] -> Python: [N, H, W, 3]
            self.rgb_data = {}
            for name in self.colormap_names:
                arr = f[f'rgb_{name}'][:]
                self.rgb_data[name] = np.transpose(arr, (3, 2, 1, 0))  # [N, H, W, 3]

            self.n_samples = first.shape[-1]
            self.n_cmaps = len(self.colormap_names)
            self.H = first.shape[1]  # W in HDF5 -> H after transpose
            self.W = first.shape[2]  # H in HDF5 -> W after transpose

            # 坐标轴
            if 'F' in f:
                self.F = f['F'][:].squeeze()
            else:
                self.F = np.linspace(-40, 40, self.H)
            if 'T' in f:
                self.T = f['T'][:].squeeze()
            else:
                self.T = np.linspace(-50, 130, self.W)

        # --- 加载 metadata (同目录自动查找) ---
        self.metadata = None
        meta_path = self.rgb_path.parent / self.rgb_path.name.replace('_stfts_rgb.mat', '_metadata.json')
        if meta_path.exists():
            with open(meta_path, 'r', encoding='utf-8') as f:
                self.metadata = json.load(f)
            print(f"Metadata: {meta_path.name} ({len(self.metadata)} entries)")

        # --- 构建 UI ---
        self.current_idx = 0
        self._build_ui()

    def _get_label(self, idx):
        if self.metadata and idx < len(self.metadata):
            m = self.metadata[idx]
            jt = m.get('jam_types', '?')
            if isinstance(jt, list):
                jt = '+'.join(jt)
            jnr = m.get('JNR', '?')
            return f"{jt}  |  JNR={jnr:+d}dB"
        return f"sample {idx}"

    def _build_ui(self):
        self.fig = plt.figure(figsize=(18, 10))
        self.fig.canvas.manager.set_window_title(f'STFT Colormap Viewer - {self.rgb_path.name}')

        # 网格布局: 2行 x 3列 (5个colormap + 1个空白)
        ncols = 3
        nrows = 2
        self.axes = []
        for i in range(nrows * ncols):
            ax = self.fig.add_subplot(nrows, ncols, i + 1)
            self.axes.append(ax)

        # 隐藏第6个
        self.axes[5].set_visible(False)

        # 底部留空间给滑块
        plt.subplots_adjust(bottom=0.12)

        # --- 导航滑块 ---
        self.slider_ax = self.fig.add_axes([0.15, 0.04, 0.55, 0.03])
        self.slider = Slider(
            self.slider_ax, 'Sample', 0, self.n_samples - 1,
            valinit=0, valfmt='%d', valstep=1
        )
        self.slider.on_changed(self._on_slider)

        # --- 上一个/下一个 按钮 ---
        self.btn_prev_ax = self.fig.add_axes([0.72, 0.035, 0.06, 0.04])
        self.btn_prev = Button(self.btn_prev_ax, '< Prev')
        self.btn_prev.on_clicked(self._on_prev)

        self.btn_next_ax = self.fig.add_axes([0.79, 0.035, 0.06, 0.04])
        self.btn_next = Button(self.btn_next_ax, 'Next >')
        self.btn_next.on_clicked(self._on_next)

        # --- 信息文本 ---
        self.info_ax = self.fig.add_axes([0.15, 0.09, 0.70, 0.02])
        self.info_ax.axis('off')
        self.info_text = self.info_ax.text(0.5, 0.5, '', transform=self.info_ax.transAxes,
                                           ha='center', va='center', fontsize=12,
                                           fontweight='bold', fontfamily='monospace')

        # --- 键盘事件 ---
        self.fig.canvas.mpl_connect('key_press_event', self._on_key)
        self.fig.canvas.mpl_connect('scroll_event', self._on_scroll)

        # 初始渲染
        self._update()

    def _update(self):
        idx = self.current_idx
        label = self._get_label(idx)

        # 清除并重绘每个colormap
        for i, name in enumerate(self.colormap_names):
            ax = self.axes[i]
            ax.clear()
            img = self.rgb_data[name][idx]  # [H, W, 3]
            extent = [self.T[0]*1e6, self.T[-1]*1e6, self.F[-1]/1e6, self.F[0]/1e6]
            ax.imshow(img, extent=extent, aspect='auto')
            ax.set_title(name, fontsize=12, fontweight='bold')
            ax.set_xlabel('Time (us)')
            ax.set_ylabel('Freq (MHz)')

        self.info_text.set_text(f'#{idx} / {self.n_samples-1}    {label}')
        self.slider.set_val(idx)
        self.fig.canvas.draw_idle()

    def _on_slider(self, val):
        new_idx = int(round(val))
        if new_idx != self.current_idx:
            self.current_idx = new_idx
            self._update()

    def _on_prev(self, event):
        if self.current_idx > 0:
            self.current_idx -= 1
            self._update()

    def _on_next(self, event):
        if self.current_idx < self.n_samples - 1:
            self.current_idx += 1
            self._update()

    def _on_key(self, event):
        if event.key in ('right', 'down', ' '):
            if self.current_idx < self.n_samples - 1:
                self.current_idx += 1
                self._update()
        elif event.key in ('left', 'up'):
            if self.current_idx > 0:
                self.current_idx -= 1
                self._update()
        elif event.key == 'home':
            self.current_idx = 0
            self._update()
        elif event.key == 'end':
            self.current_idx = self.n_samples - 1
            self._update()

    def _on_scroll(self, event):
        if event.button == 'up':
            if self.current_idx < self.n_samples - 1:
                self.current_idx += 1
                self._update()
        elif event.button == 'down':
            if self.current_idx > 0:
                self.current_idx -= 1
                self._update()

    def show(self):
        plt.show()


def main():
    # 支持命令行参数或交互式选择
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        # 尝试自动查找最新文件
        candidates = sorted(Path('output').rglob('*_echo_stfts_rgb.mat'))
        if not candidates:
            print("未找到 *_echo_stfts_rgb.mat 文件。")
            print("用法: python view_rgb_colormaps.py <path_to_rgb.mat>")
            sys.exit(1)
        print(f"找到 {len(candidates)} 个文件, 使用最新的:")
        path = str(candidates[-1])

    viewer = ColormapViewer(path)
    print(f"\n操作说明:")
    print(f"  拖拽滑块 / ← → 方向键 / 鼠标滚轮 / Prev|Next 按钮  切换样本")
    print(f"  Home/End  跳转到首/尾")
    print(f"  样本数: {viewer.n_samples},  Colormaps: {viewer.colormap_names}")
    viewer.show()


if __name__ == '__main__':
    main()
