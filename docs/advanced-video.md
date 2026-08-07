# Advanced Video

## Phase 10 scope

本阶段实现高频、非破坏性的单段视频能力：画面淡入/淡出、音频淡入/淡出和
4K/大文件的本地 Proxy 预览工作流。没有把项目扩展为完整 NLE；多段时间线、
切分、重排和转场仍不是当前实现范围。

## Fades

`VideoEditState` v2 保存画面和音频的独立淡入/淡出秒数。视频通过 Core Image
composition 乘以黑场淡化包络；音频通过 `AVAudioMix` 音量坡道处理。淡化以 trim
和速度处理后的输出时间线为准，且不会修改原始视频或其音轨。

## Proxy workflow

用户可以在视频预览中选择“生成 Proxy”。应用用原始视频创建 H.264、中等质量、
最长边最多 1280px 的派生 MP4，保存到：

```text
~/Library/Application Support/MacPhotoStudio/video-proxies/
```

Catalog v11 的 `video_proxies` 只保存 asset ID、源文件大小/修改时间签名、相对
派生路径和尺寸。预览只在签名匹配且文件仍在受控 Proxy 目录时使用它；源文件
修改、记录失配或 Proxy 丢失会自动回退到原视频。用户可删除 Proxy，该操作只删除
应用派生目录文件和其 Catalog 记录。编辑器与最终导出始终读取原视频。

Proxy 生成在统一后台任务中心运行，可显示进度和取消。已检测的 HDR 视频不生成
SDR Proxy，以避免伪造或损坏其色彩契约。

## Verification boundary

自动化测试使用系统临时目录生成短 H.264 视频，验证派生文件、Catalog 签名、
失效和删除行为以及原视频字节不变。真实 4K/长视频、外置卷、含音轨素材和 HDR
素材仍需要用户授权的 macOS 环境进行人工验证。
