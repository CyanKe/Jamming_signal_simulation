/**
 * 干扰信号可视化前端
 * - 后端按样本切片返回 float32 base64
 * - 归一化与 colormap 在浏览器端即时计算
 */

const state = {
  entries: [],
  openInfo: null,
  path: null,
  kind: "stft",
  index: 0,
  sample: null, // decoded arrays
  lastLo: null,
  lastHi: null,
  nChannels: 1,
  channelBins: null, // e.g. [224,112,32]
};

const $ = (id) => document.getElementById(id);

function setStatus(msg, type = "") {
  const el = $("status");
  el.textContent = msg;
  el.className = "status" + (type ? " " + type : "");
}

function percentile(arr, p) {
  if (!arr.length) return 0;
  const a = Float32Array.from(arr);
  a.sort();
  const idx = (p / 100) * (a.length - 1);
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  if (lo === hi) return a[lo];
  const t = idx - lo;
  return a[lo] * (1 - t) + a[hi] * t;
}

/** 对大数组做抽样百分位，避免 UI 卡顿 */
function percentileApprox(data, p, maxSamples = 200000) {
  const n = data.length;
  if (n <= maxSamples) {
    return percentile(data, p);
  }
  const step = Math.floor(n / maxSamples);
  const sample = new Float32Array(maxSamples);
  let j = 0;
  for (let i = 0; i < n && j < maxSamples; i += step) {
    sample[j++] = data[i];
  }
  return percentile(sample.subarray(0, j), p);
}

function decodeF32(encoded) {
  if (!encoded || encoded.encoding !== "base64_f32") {
    throw new Error("未知数据编码");
  }
  const bin = atob(encoded.data);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  const arr = new Float32Array(bytes.buffer);
  return { data: arr, shape: encoded.shape };
}

function reshape2d(flat, shape) {
  const [h, w] = shape;
  if (h * w !== flat.length) {
    console.warn("shape mismatch", shape, flat.length);
  }
  const rows = [];
  for (let i = 0; i < h; i++) {
    rows.push(Array.from(flat.subarray(i * w, (i + 1) * w)));
  }
  return rows;
}

/** 从 [H,W,C] 扁平数据取第 ch 通道 → Float32Array 长度 H*W */
function extractChannel(flat, shape, ch) {
  const [h, w, c] = shape;
  if (ch < 0 || ch >= c) throw new Error(`通道 ${ch} 越界 (C=${c})`);
  const out = new Float32Array(h * w);
  // 行优先: idx = (i*w + j)*c + ch
  for (let i = 0; i < h * w; i++) {
    out[i] = flat[i * c + ch];
  }
  return out;
}

function getPersChannelMode() {
  const el = document.querySelector('input[name="persChannel"]:checked');
  return el ? el.value : "0";
}

/** 根据 channel_power_bins 刷新单通道标签文案 */
function updatePersChannelUI(nChannels, bins) {
  const field = $("persChannelField");
  if (!field) return;
  const show = state.kind === "persistence" && nChannels > 1;
  field.style.display = show ? "block" : "none";
  if (!show) return;

  const labels = field.querySelectorAll('input[name="persChannel"]');
  labels.forEach((inp) => {
    const lab = inp.parentElement;
    if (inp.value === "rgb") {
      lab.style.display = nChannels >= 3 ? "" : "none";
      return;
    }
    const ch = parseInt(inp.value, 10);
    if (ch >= nChannels) {
      lab.style.display = "none";
      return;
    }
    lab.style.display = "";
    const binTxt = bins && bins[ch] != null ? ` (bins=${bins[ch]})` : "";
    lab.lastChild.textContent = ` ch${ch + 1}${binTxt}`;
  });
  const hint = $("persChannelHint");
  if (hint) {
    const binsStr = bins ? bins.join(",") : "?";
    hint.textContent = `${nChannels} 通道 · power_bins=[${binsStr}] · 单通道热图 / 三通道 RGB`;
  }
}

function applyMagnitudeTransform(flat, mode) {
  const out = new Float32Array(flat.length);
  const eps = 1e-12;
  if (mode === "dB") {
    for (let i = 0; i < flat.length; i++) {
      out[i] = 20 * Math.log10(Math.max(flat[i], 0) + eps);
    }
  } else {
    out.set(flat);
  }
  return out;
}

function getNormMode() {
  const el = document.querySelector('input[name="normMode"]:checked');
  return el ? el.value : "dB";
}

function getTimesView() {
  const el = document.querySelector('input[name="timesView"]:checked');
  return el ? el.value : "mag";
}

function getStftView() {
  const el = document.querySelector('input[name="stftView"]:checked');
  return el ? el.value : "mag";
}

/** 计算相位 atan2(imag, real)，返回 Float32Array */
function computePhase(realArr, imagArr) {
  const n = realArr.length;
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    out[i] = Math.atan2(imagArr[i], realArr[i]);
  }
  return out;
}

/**
 * 将三个 Float32Array 打包为 HWC [H,W,3] 扁平数据
 * 用于 STFT 三通道 RGB 可视化
 */
function packChannelsHWC(ch0, ch1, ch2, h, w) {
  const n = h * w;
  const out = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    out[i * 3] = ch0[i];
    out[i * 3 + 1] = ch1[i];
    out[i * 3 + 2] = ch2[i];
  }
  return { data: out, shape: [h, w, 3] };
}

/** 通道类型: mag 可用 dB；signed/phase 强制 linear */
function channelTransformMode(chKind, globalMode) {
  if (chKind === "mag") return globalMode;
  return "linear";
}

function getPercentiles() {
  let pLo = parseFloat($("pLo").value);
  let pHi = parseFloat($("pHi").value);
  if (Number.isNaN(pLo)) pLo = 1;
  if (Number.isNaN(pHi)) pHi = 99;
  pLo = Math.max(0, Math.min(100, pLo));
  pHi = Math.max(0, Math.min(100, pHi));
  if (pLo >= pHi) pHi = Math.min(100, pLo + 1);
  return { pLo, pHi };
}

function computeRange(transformed) {
  if ($("fixAbs").checked) {
    let lo = parseFloat($("absLo").value);
    let hi = parseFloat($("absHi").value);
    if (Number.isNaN(lo) || Number.isNaN(hi) || lo >= hi) {
      const { pLo, pHi } = getPercentiles();
      lo = percentileApprox(transformed, pLo);
      hi = percentileApprox(transformed, pHi);
    }
    return { lo, hi };
  }
  const { pLo, pHi } = getPercentiles();
  const lo = percentileApprox(transformed, pLo);
  const hi = percentileApprox(transformed, pHi);
  return { lo, hi: hi > lo ? hi : lo + 1e-6 };
}

async function api(url) {
  const res = await fetch(url);
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const j = await res.json();
      detail = j.detail || JSON.stringify(j);
    } catch (_) {}
    throw new Error(detail);
  }
  return res.json();
}

function entryKey(e) {
  return e.jnr ? `${e.dataset} / ${e.jnr}` : e.dataset;
}

function populateDatasets() {
  const sel = $("selDataset");
  sel.innerHTML = "";
  if (!state.entries.length) {
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = "(output 下未找到数据)";
    sel.appendChild(opt);
    return;
  }
  state.entries.forEach((e, i) => {
    const opt = document.createElement("option");
    opt.value = String(i);
    const nFiles = e.files.length;
    opt.textContent = `${entryKey(e)}  (${nFiles} files)`;
    sel.appendChild(opt);
  });
  updateFileList();
}

function updateFileList() {
  const idx = parseInt($("selDataset").value, 10);
  const kind = $("selKind").value;
  const sel = $("selFile");
  sel.innerHTML = "";
  if (Number.isNaN(idx) || !state.entries[idx]) return;
  const files = state.entries[idx].files.filter((f) => f.kind === kind);
  if (!files.length) {
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = `无 ${kind} 文件`;
    sel.appendChild(opt);
    return;
  }
  files.forEach((f) => {
    const opt = document.createElement("option");
    opt.value = f.path;
    opt.textContent = `${f.name}  (${f.size_mb} MB)  [${f.split}]`;
    sel.appendChild(opt);
  });
}

async function loadDatasets() {
  setStatus("扫描数据集…", "loading");
  try {
    const data = await api("/api/datasets");
    state.entries = data.entries || [];
    populateDatasets();
    setStatus(`找到 ${state.entries.length} 个目录 · output: ${data.output_root}`);
  } catch (err) {
    setStatus("加载数据集失败: " + err.message, "error");
  }
}

async function openFile() {
  const path = $("selFile").value;
  const kind = $("selKind").value;
  if (!path) {
    setStatus("请选择有效文件", "error");
    return;
  }
  setStatus("打开文件…", "loading");
  try {
    const info = await api(
      `/api/open?path=${encodeURIComponent(path)}&kind=${encodeURIComponent(kind)}`
    );
    state.openInfo = info;
    state.path = info.path;
    state.kind = kind;
    state.index = 0;

    $("sampleSlider").max = Math.max(0, info.n_samples - 1);
    $("sampleSlider").value = 0;
    $("sampleJump").max = Math.max(0, info.n_samples - 1);
    $("sampleJump").value = 0;
    $("sampleIdxText").textContent = `0 / ${info.n_samples - 1}`;
    $("pathText").textContent = info.path;
    $("fileInfo").textContent =
      `shape ${JSON.stringify(info.shape)} · ${info.size_mb} MB · dtype ${info.dtype}` +
      (info.has_metadata ? ` · metadata ${info.metadata_count}` : " · 无 metadata");

    // persistence 默认 linear 更合理
    if (kind === "persistence") {
      document.querySelector('input[name="normMode"][value="linear"]').checked = true;
    } else if (kind === "stft") {
      document.querySelector('input[name="normMode"][value="dB"]').checked = true;
    }

    $("timesViewField").style.display = kind === "times" ? "block" : "none";
    $("stftViewField").style.display = kind === "stft" ? "block" : "none";
    // 通道面板在 loadSample 后根据 n_channels 显示
    $("persChannelField").style.display = "none";
    state.nChannels = 1;
    state.channelBins = null;

    await loadSample(0);
    setStatus(`已打开: ${info.path}  (${info.n_samples} 样本)`);
  } catch (err) {
    setStatus("打开失败: " + err.message, "error");
  }
}

async function loadSample(index) {
  if (!state.path) return;
  const n = state.openInfo ? state.openInfo.n_samples : 0;
  index = Math.max(0, Math.min(n - 1, index));
  state.index = index;
  $("sampleSlider").value = index;
  $("sampleJump").value = index;
  $("sampleIdxText").textContent = `${index} / ${Math.max(0, n - 1)}`;

  setStatus(`加载样本 ${index}…`, "loading");
  try {
    const payload = await api(
      `/api/sample?path=${encodeURIComponent(state.path)}&kind=${encodeURIComponent(
        state.kind
      )}&index=${index}`
    );

    const decoded = { kind: payload.kind, axes: payload.axes || {}, meta: payload.meta };
    decoded.mag = decodeF32(payload.mag);
    if (payload.real) decoded.real = decodeF32(payload.real);
    if (payload.imag) decoded.imag = decodeF32(payload.imag);
    // 多通道 persistence: channels shape [H,W,C]
    if (payload.channels) {
      decoded.channels = decodeF32(payload.channels);
      decoded.nChannels = payload.n_channels || decoded.channels.shape[2] || 1;
    } else {
      decoded.nChannels = payload.n_channels || 1;
    }

    state.sample = decoded;
    state.nChannels = decoded.nChannels;
    const axes = decoded.axes || {};
    state.channelBins = axes.channel_power_bins || null;
    updatePersChannelUI(state.nChannels, state.channelBins);

    $("sampleLabel").innerHTML = payload.label
      ? `<span class="label-tag">${payload.label}</span>`
      : `<span class="label-tag">sample ${index}</span>`;
    $("metaPanel").textContent = payload.meta
      ? JSON.stringify(payload.meta, null, 2)
      : "(无 metadata)";

    renderPlot();
    setStatus(`样本 ${index} 已加载` + (state.nChannels > 1 ? ` · ${state.nChannels}ch` : ""));
  } catch (err) {
    setStatus("加载样本失败: " + err.message, "error");
  }
}

function renderPlot() {
  if (!state.sample) return;
  const kind = state.kind;
  const cmap = $("selCmap").value;

  if (kind === "times") {
    renderTimes(cmap);
  } else {
    renderHeatmap(cmap);
  }
}

function resolveHeatmapPlane() {
  /** 返回 { flat, h, w, chLabel } 用于单通道热图或 RGB 源 */
  const kind = state.kind;
  const sample = state.sample;

  if (kind === "persistence" && sample.channels && sample.nChannels > 1) {
    const mode = getPersChannelMode();
    const { data, shape } = sample.channels;
    const [h, w, c] = shape;
    if (mode === "rgb") {
      return {
        mode: "rgb",
        flat: data,
        shape,
        h,
        w,
        c,
        chLabel: "RGB",
        chKinds: ["mag", "mag", "mag"],
      };
    }
    const ch = parseInt(mode, 10) || 0;
    const flat = extractChannel(data, shape, ch);
    const bins = state.channelBins;
    const binTxt = bins && bins[ch] != null ? `bins=${bins[ch]}` : `ch${ch + 1}`;
    return {
      mode: "single",
      flat,
      h,
      w,
      chLabel: `ch${ch + 1} (${binTxt})`,
      chKind: "mag",
    };
  }

  // ---- STFT: 模值 / I/Q / 相位 及三通道组合 ----
  if (kind === "stft") {
    const view = getStftView();
    const mag = sample.mag;
    const [h, w] = mag.shape;
    const realData = sample.real ? sample.real.data : null;
    const imagData = sample.imag ? sample.imag.data : null;
    const hasIQ = realData && imagData;

    if (view === "mag") {
      return {
        mode: "single",
        flat: mag.data,
        h,
        w,
        chLabel: "|S|",
        chKind: "mag",
      };
    }
    if (view === "real") {
      if (!hasIQ) {
        return {
          mode: "single",
          flat: mag.data,
          h,
          w,
          chLabel: "real (无 I/Q，回退|S|)",
          chKind: "mag",
        };
      }
      return {
        mode: "single",
        flat: realData,
        h,
        w,
        chLabel: "Re(S)",
        chKind: "signed",
      };
    }
    if (view === "imag") {
      if (!hasIQ) {
        return {
          mode: "single",
          flat: mag.data,
          h,
          w,
          chLabel: "imag (无 I/Q，回退|S|)",
          chKind: "mag",
        };
      }
      return {
        mode: "single",
        flat: imagData,
        h,
        w,
        chLabel: "Im(S)",
        chKind: "signed",
      };
    }
    if (view === "phase") {
      if (!hasIQ) {
        return {
          mode: "single",
          flat: mag.data,
          h,
          w,
          chLabel: "phase (无 I/Q，回退|S|)",
          chKind: "mag",
        };
      }
      return {
        mode: "single",
        flat: computePhase(realData, imagData),
        h,
        w,
        chLabel: "∠S (rad)",
        chKind: "phase",
      };
    }
    // 三通道 RGB
    if (!hasIQ) {
      // 无 I/Q 时退回 mag×3
      const packed = packChannelsHWC(mag.data, mag.data, mag.data, h, w);
      return {
        mode: "rgb",
        flat: packed.data,
        shape: packed.shape,
        h,
        w,
        c: 3,
        chLabel: "RGB 模值×3 (无 I/Q)",
        chKinds: ["mag", "mag", "mag"],
      };
    }
    if (view === "magx3") {
      const packed = packChannelsHWC(mag.data, mag.data, mag.data, h, w);
      return {
        mode: "rgb",
        flat: packed.data,
        shape: packed.shape,
        h,
        w,
        c: 3,
        chLabel: "RGB [mag,mag,mag]",
        chKinds: ["mag", "mag", "mag"],
      };
    }
    if (view === "mag_ri") {
      const packed = packChannelsHWC(mag.data, realData, imagData, h, w);
      return {
        mode: "rgb",
        flat: packed.data,
        shape: packed.shape,
        h,
        w,
        c: 3,
        chLabel: "RGB [|S|, Re, Im]",
        chKinds: ["mag", "signed", "signed"],
      };
    }
    if (view === "phase_ri") {
      const phase = computePhase(realData, imagData);
      const packed = packChannelsHWC(phase, realData, imagData, h, w);
      return {
        mode: "rgb",
        flat: packed.data,
        shape: packed.shape,
        h,
        w,
        c: 3,
        chLabel: "RGB [∠S, Re, Im]",
        chKinds: ["phase", "signed", "signed"],
      };
    }
    // 未知 view 回退
    return {
      mode: "single",
      flat: mag.data,
      h,
      w,
      chLabel: "|S|",
      chKind: "mag",
    };
  }

  const { mag } = sample;
  const [h, w] = mag.shape;
  return { mode: "single", flat: mag.data, h, w, chLabel: "", chKind: "mag" };
}

function renderHeatmap(cmap) {
  const kind = state.kind;
  const axes = state.sample.axes || {};
  const plane = resolveHeatmapPlane();
  const mode = getNormMode();
  const label =
    ($("sampleLabel").textContent || "").trim() || `sample ${state.index}`;

  let x = null;
  let y = null;
  let xTitle = "time index";
  let yTitle = "freq index";
  const h = plane.h;
  const w = plane.w;

  if (kind === "stft") {
    if (axes.T && axes.T.length === w) {
      x = axes.T.map((t) => t * 1e6);
      xTitle = "Time (µs)";
    }
    if (axes.F && axes.F.length === h) {
      y = axes.F.map((f) => f / 1e6);
      yTitle = "Freq (MHz)";
    }
  } else if (kind === "persistence") {
    if (axes.power_centers && axes.power_centers.length === w) {
      x = axes.power_centers;
      xTitle = "Power (dB)";
    }
    if (axes.F && axes.F.length === h) {
      y = axes.F.map((f) => f / 1e6);
      yTitle = "Freq (MHz)";
    }
  }

  // ---- 三通道 RGB 显示 ----
  if (plane.mode === "rgb") {
    const { flat, shape } = plane;
    const [, , c] = shape;
    const nCh = Math.min(3, c);
    const chKinds = plane.chKinds || ["mag", "mag", "mag"];
    // 每通道独立归一化到 0..255；signed/phase 强制 linear
    const rgb = new Array(h);
    const { pLo, pHi } = getPercentiles();
    const chRanges = [];
    for (let ch = 0; ch < nCh; ch++) {
      const chFlat = extractChannel(flat, shape, ch);
      const chMode = channelTransformMode(chKinds[ch] || "mag", mode);
      const transformed = applyMagnitudeTransform(chFlat, chMode);
      let lo, hi;
      if ($("fixAbs").checked && ch === 0) {
        // 绝对范围仅绑定 ch0（模值/相位），其余通道仍用百分位
        lo = parseFloat($("absLo").value);
        hi = parseFloat($("absHi").value);
        if (Number.isNaN(lo) || Number.isNaN(hi) || lo >= hi) {
          lo = percentileApprox(transformed, pLo);
          hi = percentileApprox(transformed, pHi);
        }
      } else {
        lo = percentileApprox(transformed, pLo);
        hi = percentileApprox(transformed, pHi);
        if (hi <= lo) hi = lo + 1e-6;
      }
      chRanges.push({ lo, hi, transformed, chMode });
    }
    state.lastLo = chRanges[0].lo;
    state.lastHi = chRanges[0].hi;
    $("rangeText").textContent = chRanges
      .map((r, i) => `ch${i + 1}:${r.lo.toFixed(3)}~${r.hi.toFixed(3)}`)
      .join(" | ");

    for (let i = 0; i < h; i++) {
      rgb[i] = new Array(w);
      for (let j = 0; j < w; j++) {
        const pix = [0, 0, 0];
        for (let ch = 0; ch < nCh; ch++) {
          const { lo, hi, transformed } = chRanges[ch];
          const v = transformed[i * w + j];
          const t = Math.max(0, Math.min(1, (v - lo) / (hi - lo)));
          pix[ch] = Math.round(t * 255);
        }
        rgb[i][j] = pix;
      }
    }

    const data = [
      {
        type: "image",
        z: rgb,
        colormodel: "rgb",
        hovertemplate: "x=%{x}<br>y=%{y}<extra></extra>",
      },
    ];
    const titleExtra = plane.chLabel ? ` · ${plane.chLabel}` : "";
    const layout = {
      title: {
        text: `${String(kind).toUpperCase()} · ${label}${titleExtra}`,
        font: { size: 14, color: "#e7ecf3" },
      },
      paper_bgcolor: "#0f1419",
      plot_bgcolor: "#0f1419",
      margin: { l: 60, r: 40, t: 48, b: 50 },
      xaxis: {
        title: xTitle + (x ? "" : " (pixel)"),
        color: "#8b9bb4",
        gridcolor: "#243044",
        scaleanchor: "y",
        scaleratio: 1,
      },
      yaxis: {
        title: yTitle + (y ? "" : " (pixel)"),
        color: "#8b9bb4",
        gridcolor: "#243044",
        autorange: "reversed",
      },
      font: { color: "#e7ecf3" },
    };
    Plotly.react("plot", data, layout, { responsive: true, displayModeBar: true });
    return;
  }

  // ---- 单通道热图 ----
  const flat = plane.flat;
  const chKind = plane.chKind || "mag";
  const singleMode = channelTransformMode(chKind, mode);
  const transformed = applyMagnitudeTransform(flat, singleMode);
  const { lo, hi } = computeRange(transformed);
  state.lastLo = lo;
  state.lastHi = hi;
  $("rangeText").textContent = `${lo.toFixed(3)} ~ ${hi.toFixed(3)}`;

  const z = reshape2d(transformed, [h, w]);
  const titleExtra = plane.chLabel ? ` · ${plane.chLabel}` : "";
  let cbarTitle = "mag";
  if (chKind === "phase") cbarTitle = "rad";
  else if (chKind === "signed") cbarTitle = "I/Q";
  else if (singleMode === "dB") cbarTitle = "dB";

  const data = [
    {
      type: "heatmap",
      z,
      x: x || undefined,
      y: y || undefined,
      colorscale: cmap,
      zmin: lo,
      zmax: hi,
      colorbar: {
        title: { text: cbarTitle, side: "right" },
        thickness: 14,
      },
      hovertemplate: "x=%{x}<br>y=%{y}<br>z=%{z:.3f}<extra></extra>",
    },
  ];

  const layout = {
    title: {
      text: `${String(kind).toUpperCase()} · ${label}${titleExtra}`,
      font: { size: 14, color: "#e7ecf3" },
    },
    paper_bgcolor: "#0f1419",
    plot_bgcolor: "#0f1419",
    margin: { l: 60, r: 40, t: 48, b: 50 },
    xaxis: { title: xTitle, color: "#8b9bb4", gridcolor: "#243044" },
    yaxis: { title: yTitle, color: "#8b9bb4", gridcolor: "#243044" },
    font: { color: "#e7ecf3" },
  };

  Plotly.react("plot", data, layout, { responsive: true, displayModeBar: true });
}

function downsample1d(x, y, maxPts = 8000) {
  if (y.length <= maxPts) return { x, y };
  const step = Math.ceil(y.length / maxPts);
  const xs = [];
  const ys = [];
  for (let i = 0; i < y.length; i += step) {
    // 取窗内 max |y| 点，保留尖峰
    let best = i;
    let bestAbs = Math.abs(y[i]);
    const end = Math.min(y.length, i + step);
    for (let j = i + 1; j < end; j++) {
      const a = Math.abs(y[j]);
      if (a > bestAbs) {
        bestAbs = a;
        best = j;
      }
    }
    xs.push(x[best]);
    ys.push(y[best]);
  }
  return { x: xs, y: ys };
}

function renderTimes() {
  const view = getTimesView();
  const n = state.sample.mag.shape[0] || state.sample.mag.data.length;
  const fs = 80e6; // 与 config 默认一致，仅作时间轴参考
  const t = new Float32Array(n);
  for (let i = 0; i < n; i++) t[i] = (i / fs) * 1e6; // µs

  const mode = getNormMode();
  const traces = [];
  const label =
    ($("sampleLabel").textContent || "").trim() || `sample ${state.index}`;

  function prep(arr, name, color) {
    let y = arr;
    if (view === "mag" && mode === "dB") {
      y = applyMagnitudeTransform(arr, "dB");
    }
    // 对 real/imag 在 dB 模式下仍显示线性，避免负值 log
    if (view !== "mag") {
      y = arr;
    }
    const { x: xs, y: ys } = downsample1d(Array.from(t), Array.from(y));
    traces.push({
      type: "scatter",
      mode: "lines",
      name,
      x: xs,
      y: ys,
      line: { width: 1, color },
    });
  }

  if (view === "mag") {
    prep(state.sample.mag.data, mode === "dB" ? "|s| dB" : "|s|", "#22d3ee");
    // 归一化范围展示（对 mag）
    const transformed =
      mode === "dB"
        ? applyMagnitudeTransform(state.sample.mag.data, "dB")
        : state.sample.mag.data;
    const { lo, hi } = computeRange(transformed);
    state.lastLo = lo;
    state.lastHi = hi;
    $("rangeText").textContent = `${lo.toFixed(3)} ~ ${hi.toFixed(3)}`;
  } else if (view === "real") {
    prep(state.sample.real.data, "real", "#3b82f6");
    $("rangeText").textContent = "— (I/Q 线性)";
  } else if (view === "imag") {
    prep(state.sample.imag.data, "imag", "#f472b6");
    $("rangeText").textContent = "— (I/Q 线性)";
  } else {
    prep(state.sample.real.data, "real", "#3b82f6");
    prep(state.sample.imag.data, "imag", "#f472b6");
    $("rangeText").textContent = "— (I/Q 线性)";
  }

  // 固定绝对范围时缩放 y 轴（仅 mag）
  let yRange = undefined;
  if (view === "mag" && $("fixAbs").checked && state.lastLo != null) {
    yRange = [state.lastLo, state.lastHi];
  }

  const layout = {
    title: { text: `TIME · ${label}`, font: { size: 14, color: "#e7ecf3" } },
    paper_bgcolor: "#0f1419",
    plot_bgcolor: "#0f1419",
    margin: { l: 60, r: 20, t: 48, b: 50 },
    xaxis: { title: "Time (µs)", color: "#8b9bb4", gridcolor: "#243044" },
    yaxis: {
      title: view === "mag" && mode === "dB" ? "Amplitude (dB)" : "Amplitude",
      color: "#8b9bb4",
      gridcolor: "#243044",
      range: yRange,
    },
    legend: { orientation: "h", y: 1.08 },
    font: { color: "#e7ecf3" },
  };

  Plotly.react("plot", traces, layout, { responsive: true, displayModeBar: true });
}

function resetNorm() {
  document.querySelector('input[name="normMode"][value="dB"]').checked =
    state.kind !== "persistence";
  if (state.kind === "persistence") {
    document.querySelector('input[name="normMode"][value="linear"]').checked = true;
  }
  $("pLo").value = 1;
  $("pHi").value = 99;
  $("fixAbs").checked = false;
  $("absLo").disabled = true;
  $("absHi").disabled = true;
  $("selCmap").value = "Jet";
  renderPlot();
}

function captureAbs() {
  if (state.lastLo == null || state.lastHi == null) {
    renderPlot();
  }
  if (state.lastLo != null && state.lastHi != null) {
    $("fixAbs").checked = true;
    $("absLo").disabled = false;
    $("absHi").disabled = false;
    $("absLo").value = state.lastLo.toFixed(6);
    $("absHi").value = state.lastHi.toFixed(6);
    renderPlot();
  }
}

function bindEvents() {
  $("btnRefresh").addEventListener("click", loadDatasets);
  $("selDataset").addEventListener("change", updateFileList);
  $("selKind").addEventListener("change", updateFileList);
  $("btnOpen").addEventListener("click", openFile);

  $("sampleSlider").addEventListener("input", (e) => {
    $("sampleIdxText").textContent = `${e.target.value} / ${$("sampleSlider").max}`;
  });
  $("sampleSlider").addEventListener("change", (e) => {
    loadSample(parseInt(e.target.value, 10));
  });
  $("btnPrev").addEventListener("click", () => loadSample(state.index - 1));
  $("btnNext").addEventListener("click", () => loadSample(state.index + 1));
  $("btnJump").addEventListener("click", () =>
    loadSample(parseInt($("sampleJump").value, 10))
  );

  document.querySelectorAll('input[name="normMode"]').forEach((el) => {
    el.addEventListener("change", renderPlot);
  });
  document.querySelectorAll('input[name="timesView"]').forEach((el) => {
    el.addEventListener("change", renderPlot);
  });
  document.querySelectorAll('input[name="stftView"]').forEach((el) => {
    el.addEventListener("change", renderPlot);
  });
  document.querySelectorAll('input[name="persChannel"]').forEach((el) => {
    el.addEventListener("change", renderPlot);
  });
  ["pLo", "pHi", "selCmap", "absLo", "absHi"].forEach((id) => {
    $(id).addEventListener("change", renderPlot);
    $(id).addEventListener("input", () => {
      // 数值滑条式输入：防抖
      clearTimeout(window.__normTimer);
      window.__normTimer = setTimeout(renderPlot, 120);
    });
  });
  $("fixAbs").addEventListener("change", () => {
    const on = $("fixAbs").checked;
    $("absLo").disabled = !on;
    $("absHi").disabled = !on;
    if (on && ( !$("absLo").value || !$("absHi").value) && state.lastLo != null) {
      $("absLo").value = state.lastLo.toFixed(6);
      $("absHi").value = state.lastHi.toFixed(6);
    }
    renderPlot();
  });
  $("btnResetNorm").addEventListener("click", resetNorm);
  $("btnCaptureAbs").addEventListener("click", captureAbs);

  document.addEventListener("keydown", (e) => {
    if (e.target.matches("input, select, textarea")) return;
    if (e.key === "ArrowLeft") loadSample(state.index - 1);
    if (e.key === "ArrowRight") loadSample(state.index + 1);
  });
}

async function init() {
  bindEvents();
  try {
    const h = await api("/api/health");
    $("healthBadge").textContent = "服务正常";
    $("healthBadge").classList.add("ok");
  } catch {
    $("healthBadge").textContent = "服务不可用";
  }
  await loadDatasets();
}

init();
