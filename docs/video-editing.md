# Video Editing

## 非破坏性状态

每个视频的 `VideoEditState` 单独保存在 Catalog SQLite v10 的
`video_edit_states` 表中。状态包含 trim、裁剪、90° 旋转、翻转、曝光、
对比度、饱和度、色温、色调、Creative LUT 和强度、静音、音频增益、速度，
以及画面/音频淡入淡出时长。
应用不会写回、移动、重命名或覆盖引用的视频源文件。

## AVFoundation 管线

```text
AVURLAsset
→ trim composition（视频与所有可用音轨使用同一时间范围）
→ composition time scale（速度同时作用于音频和视频）
→ Core Image video composition（颜色 / Creative LUT / 裁剪 / 变换 / 画面淡入淡出）
→ AVPlayer preview 或新的 MP4 文件
```

`VideoFramePipeline` 与照片 `PhotoImagePipeline` 分离；它们只复用
Creative LUT 的模型、解析器和强度语义。Technical LUT 不进入本阶段的视频
创意槽位，避免把带输入/输出色彩契约的转换错误当成普通 look 使用。

导出读取视频轨的 `preferredTransform`，先计算显示方向尺寸，再应用用户的
裁剪与四分之一转变换。这样旋转拍摄的源视频不会因 raw natural size 而被
强制回横向画布。

`VideoGeometry` 是显示尺寸的唯一计算入口：它以 `naturalSize` 和
`preferredTransform` 计算经过方向变换后的几何尺寸。扫描入库的 Catalog
metadata、Inspector、最终导出的 render canvas 和生成后的 Proxy metadata 都使用
该入口，因此竖拍 1920×1080 源会按 1080×1920 显示和输出，而不会在任一路径
回退到未变换的 encoded size。

## 编辑预览状态恢复

调色、裁剪或 LUT 改动会重建 composition 和 `AVPlayerItem`，但不会重建
`AVPlayer`。替换前 `VideoPlaybackSession` 保存播放头、播放状态、倍率、静音和
音量；替换后先 seek 到同一输出时间（仅在新 trim/speed composition 更短时裁剪），
再恢复上述状态。replace generation 会忽略已被更新请求取代的异步 seek completion，
因此连续拖动滑块不会由旧预览恢复覆盖最新预览状态。

## Player item observation

每个 `AVPlayerItem` 的结束通知、status、duration 和 error 都由
`VideoPlaybackSession.observeCurrentItem` 统一管理。replace 前先移除旧 item 的
Notification/KVO observation，再为新 item 注册；所有异步回调均核对
`player.currentItem` 身份。新 item 的 duration 会在可用时更新控制条，failed 状态会
停止播放并在 Preview/Editor 中显示错误，避免替换后的 item 播放结束仍显示为播放中。

## 淡入淡出

画面淡入/淡出在 composition 的**输出时间线**上渲染到黑场，因此在 trim 和
speed 之后仍和实际输出时长一致。音频由独立的 `AVAudioMix` 音量坡道处理；
淡入和淡出重叠时会生成与画面一致的三角包络，而不是让两个 AVFoundation
坡道覆盖彼此。

音频音量目前只支持 `-60...0 dB` 衰减，换算后的 `AVAudioMix` volume 永远位于
`0...1`。正增益（例如 +6 dB）需要独立的离线/实时 audio processing、峰值检测和
limiter 才能避免削波；当前没有该管线，因此 UI、持久化解码与输出都会将旧的正值
归一为 0 dB，而不会错误声称已提升音量。

## 导出与安全

导出服务通过 AVFoundation 的受支持 preset 选择 H.264 或 HEVC，并创建
新的 MP4。可选择保留分辨率或最长边 resize、质量 preset、命名与冲突策略。
服务先写入目标目录内唯一的临时文件，只有成功后才移动或在用户明确允许时
替换目标；任何与源视频相同的 URL 都会先被拒绝。

视频导出作为统一 Background Task 运行：报告进度、允许取消，并将错误返回
资料库的任务状态。取消会调用 `AVAssetExportSession.cancelExport()`；临时文件
由服务清理。

## 自动化覆盖

`VideoEditingTests` 使用临时目录生成小型 H.264 MOV（不提交媒体文件），验证：

- 状态、trim/speed 限制、输出方向/尺寸计算；
- Catalog v11（含 video proxy）持久化及 Videos 的 Edited 查询；
- Core Image 调色与 Creative LUT intensity；
- 画面淡入/淡出包络与实际 Core Image 黑场渲染；
- 实际 H.264 和 HEVC MP4 导出、trim + speed 时长、裁剪后尺寸、输出编码与源文件字节不变；其中 H.264 fixture 含真实 AAC 音轨，验证 trim、速度、画面/音频淡入淡出、旋转、翻转、调色与 resize 后输出同时存在音视频轨且两者时长同步；
- 实际 H.264 Proxy 生成、签名失效、删除和源文件字节不变；
- 对源 URL 的导出覆盖请求被拒绝。

已检测的 HDR 视频继续使用原生播放，但会明确禁止进入当前 SDR 编辑、导出和
Proxy 路径，以避免生成色彩不可靠的文件。自动化以临时 AAC 音轨验证导出轨道与
时长同步；真实有音频、旋转、4K、外置盘、权限与听感组合仍需在用户授权的媒体上
人工验证；见开发进度记录。
