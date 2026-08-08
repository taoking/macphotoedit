# 视频真实媒体验证

Phase 16.6 保持现有的非破坏性单段视频边界，并把自动化验证与必须在真实媒体上完成的项目分开记录。应用始终读取引用源视频；Proxy 只写入 Application Support 的派生目录，导出只创建新的 MP4，绝不覆盖源视频。

## 已自动执行的验证

测试临时生成短 H.264 MOV（其中包含带 AAC 音轨和竖向 `preferredTransform` 的素材），并实际交给 AVFoundation：

- ImageIO/AVFoundation metadata 读取和 `preferredTransform` 后的竖向显示尺寸；
- seek、逐帧步进、播放倍率、静音/音量、重复 `AVPlayerItem` 重建后的播放头/播放状态/倍率/静音/音量恢复；旧 item 的结束通知不会影响最新 item，最新 item 的结束通知会正确停止播放；
- trim + speed + 真实 AAC 音轨 + 画面/音频淡入淡出 + 衰减 + resize 后，输出音视频轨存在且时长同步；
- 竖向 + resize 输出尺寸；Creative LUT + crop + resize 后的实际 H.264 导出帧颜色；
- H.264 导出，系统支持时的 HEVC 导出，Proxy 生成/签名失效/删除，以及源文件字节不变；
- 音频增益严格限制为 `-60 dB ... 0 dB`。没有正增益、自动增益、normalization、DSP 或 limiter 路径。

这些临时测试媒体不会被提交，也不能代表来自 iPhone、Sony、外置存储或实际 4K 负载的结果。

## 真实文件矩阵

使用每一种可获得的用户授权媒体：

```text
iPhone MOV
Sony MP4
H.264
HEVC
horizontal
vertical
30 fps
60 fps
4K
with audio
without audio
```

每个文件执行下列检查，并记录 macOS、硬件、显示器、codec、分辨率、帧率和结果：

1. 导入/扫描后核对 Inspector 的时长、codec、帧率和方向后的 metadata dimensions。竖向文件必须显示 `preferredTransform` 后的宽高，而非编码的横向 natural size。
2. 在预览中播放、暂停、seek、前后逐帧、切换 0.5×/1×/1.5×/2×、静音和音量；无音轨文件必须没有崩溃或伪造音频。
3. 分别验证 trim、speed、crop、90°/180°/270° rotate、两种 flip、曝光/对比度/色温、Creative LUT、`-60/-6/0 dB` 衰减、画面淡入淡出和音频淡入淡出。不要尝试或期待正音频增益。
4. 特别执行：`trim + speed + audio`、`vertical + resize`、`LUT + crop + export`。用可播放的输出 MP4 核对音视频轨、方向、输出尺寸、时长和听感同步。
5. 播放至约 35 秒（若素材足够长），连续调整调色、LUT 强度和裁剪以反复重建 preview。每次重建后应在有效范围内保留输出时间、播放/暂停、倍率、静音和音量；停止播放/旧 item 的结束通知不能污染最新 `AVPlayerItem` 状态。
6. 对 4K 或长视频生成 Proxy，比较 Proxy 预览与原片预览；确认最终编辑/导出仍读取原视频。删除 Proxy 后只会删除派生文件。

## 限制

- 自动化临时资产使用短小 H.264/AAC，不覆盖真实 iPhone/Sony 的 H.264/HEVC、60 fps、4K、复杂音轨、长时播放或外置硬盘行为。
- HEVC 导出仍依赖当前 macOS 和源文件兼容的 `AVAssetExportSession` preset；不可用时必须明确失败，不会回退并标为 HEVC。
- HDR 视频可以走原生播放，但当前 SDR 编辑、Proxy 与导出明确不支持；本流程不把 HLG/PQ 或 Rec.2020 标签误写为 HDR 编辑/导出支持。
- 正音频增益仍未实现。实现它需要独立的 audio DSP、峰值分析和 limiter，不能用大于 1 的 `AVAudioMix` volume 假装完成。
