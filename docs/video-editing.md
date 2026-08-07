# Video Editing

## 非破坏性状态

每个视频的 `VideoEditState` 单独保存在 Catalog SQLite v10 的
`video_edit_states` 表中。状态包含 trim、裁剪、90° 旋转、翻转、曝光、
对比度、饱和度、色温、色调、Creative LUT 和强度、静音、音频增益与速度。
应用不会写回、移动、重命名或覆盖引用的视频源文件。

## AVFoundation 管线

```text
AVURLAsset
→ trim composition（视频与所有可用音轨使用同一时间范围）
→ composition time scale（速度同时作用于音频和视频）
→ Core Image video composition（颜色 / Creative LUT / 裁剪 / 变换）
→ AVPlayer preview 或新的 MP4 文件
```

`VideoFramePipeline` 与照片 `PhotoImagePipeline` 分离；它们只复用
Creative LUT 的模型、解析器和强度语义。Technical LUT 不进入本阶段的视频
创意槽位，避免把带输入/输出色彩契约的转换错误当成普通 look 使用。

导出读取视频轨的 `preferredTransform`，先计算显示方向尺寸，再应用用户的
裁剪与四分之一转变换。这样旋转拍摄的源视频不会因 raw natural size 而被
强制回横向画布。

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
- Catalog v10 持久化及 Videos 的 Edited 查询；
- Core Image 调色与 Creative LUT intensity；
- 实际 H.264 和 HEVC MP4 导出、trim + speed 时长、裁剪后尺寸、输出编码与源文件字节不变；
- 对源 URL 的导出覆盖请求被拒绝。

已检测的 HDR 视频继续使用原生播放，但会明确禁止进入本阶段的 SDR 编辑/导出，
以避免生成色彩不可靠的文件；HDR 视频处理与 Technical LUT 会在 Phase 10 单独
实现。真实有音频、旋转、4K、外置盘与权限组合仍需在用户授权的媒体上人工验证；
见开发进度记录。
