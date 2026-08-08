# 静态图像色彩验证

Phase 16.5 提供 **File → 运行静态图像色彩验证…**。该命令用于对用户授权的真实静态图像执行可复查的色彩验证，而不是根据文件扩展名或 ICC 名称猜测结果。

选择一个 JPEG、HEIC/HEIF、PNG 或 TIFF 源文件，再选择一个输出文件夹。应用会在该文件夹创建唯一的：

```text
MacPhotoStudio-Still-Color-Validation-<source>-<UUID>/
```

子目录。它绝不会覆盖源文件或已有导出。对每种下列 SDR 输出设置，命令会运行一次实际预览、一次全分辨率导出，并通过 ImageIO 重新打开预览数据和每一张导出文件，记录实际嵌入的 ICC profile：

```text
sRGB
Display P3
Rec.709
Rec.2020 SDR
```

当前产品导出器会为每个输出设置创建 JPEG、HEIF/HEIC（仅系统 ImageIO 支持时）和 TIFF。导出目录中的文件名为 `sRGB.jpg`、`displayP3.heic`、`rec709.tiff` 等。命令还会将小型 UTF-8 报告写入：

```text
~/Library/Application Support/MacPhotoStudio/logs/
```

报告包含源格式、尺寸、ImageIO 读取到的源色彩空间、严格的 `PhotoColorDescriptor` 匹配状态、每个预览的实际 profile、每个导出的实际 profile 与请求 profile 的逐字节 ICC 比较、输出目录，以及源文件大小/修改时间的前后比较。报告不嵌入任何源像素。

## 真实文件步骤

对以下每个用户授权文件分别运行该命令，并保留报告和输出目录：

- JPEG sRGB
- JPEG Display P3
- HEIC sRGB
- HEIC Display P3
- PNG
- TIFF

对每次运行：

1. 检查源 profile 具有预期的严格 descriptor；未知或缺失 ICC 会被记录并停止验证，不会假定为 sRGB。
2. 检查报告中四个 Preview 行和每个支持的 Export 行都为 `PASS`，且 `actual ICC` 与请求输出一致。
3. 若该文件已在资料库索引中，在照片编辑器选择同一个输出空间并检查应用预览；否则先把包含它的文件夹作为引用目录加入资料库（不会复制文件）。然后使用颜色管理的参考应用（例如 Preview、ColorSync Utility 或受控的专业编辑器）打开同名新文件，比较中性灰、饱和红/绿/蓝、肤色和高光。记录显示器、macOS 版本、参考应用与任何差异。
4. 比较源文件字节（或至少报告中的签名并结合用户自己的校验工具），确认源文件未被修改。验证输出是新文件，可以按用户意愿保留或删除。

## 限制与边界

- 这是 identity 编辑状态的色彩管线验证；创意调整、技术 LUT、局部蒙版和 RAW 在各自的手工验证流程中另行验证。
- PNG 在此流程中是受支持的**输入**格式。当前产品的仍图导出格式是 JPEG、HEIF/HEIC 与 TIFF，因此该工作流不会声称创建 PNG 导出文件。
- HEIF/HEIC 行仅在当前 macOS 的 ImageIO encoder 可用时执行；不可用会在报告中明确写为失败/不支持，而不会伪造结果。
- ImageIO ICC 重读证明文件携带了请求的 ColorSync profile，不能替代真实显示器上的视觉比较，也不能证明第三方应用、网页浏览器或未受色彩管理的查看器会正确显示它。
- Rec.2020 行仍是 **SDR**：Rec.2020 primaries 使用 BT.709 SDR transfer function。它不生成 HDR、PQ、HLG 或 gain-map 图像，也不表示 HDR mastering 已获得支持。
