# 外置存储验证

Phase 16.7 为每个已登记媒体根目录提供 **File → 运行媒体根目录可用性诊断**。它只读取 bookmark 和目录资源值，并把小型文本报告写入 Application Support 的 logs 目录；不会复制、修改或删除原始媒体、Catalog 记录、缩略图或 Proxy。

每个根目录报告会记录：上次路径、bookmark 是否可解析/是否 stale、解析错误、`startAccessingSecurityScopedResource()` 的结果、目录存在性/读写性、卷名、卷 UUID、本地/可移除/可弹出属性、存储卷 UUID 匹配结果，以及最终 `online`、`offline` 或 `permissionRequired` 状态。

`startAccessingSecurityScopedResource()` 返回 `false` 本身不是失败：对于已经可访问的本地 URL，它可能不需要额外 scope。诊断始终还会进行实际目录存在性和资源值读取；如果 scope 成功启动，则该次读取结束时必定配对 `stopAccessingSecurityScopedResource()`。

## 自动化覆盖

- 使用真实临时目录创建、持久化并解析 security-scoped bookmark，读取目录和卷资源值，生成文本报告，并确认 Catalog 根目录保持 online。
- 在含已有 Catalog 资产的临时根目录被移除后运行诊断；根目录变为 offline、错误被保留、资产记录和相对路径仍在且只标记 offline。
- 扫描入口复用同一诊断，因此断开的根目录不会继续枚举、不会执行 `finishScan` 将所有资产错误标为 missing，也不会清空 Catalog。

## 必须人工验证的设备矩阵

对每类用户授权存储各完成一次，并保留生成的文本报告：

```text
internal SSD
external SSD
external HDD
SD card
```

每个设备依次执行：

1. 添加包含照片/视频的文件夹；重启应用，运行诊断，并确认 bookmark 可解析、根目录 online、卷 UUID 与记录一致。
2. 生成可见缩略图后断开设备；重新启动并运行诊断。根目录应为 offline（或在路径存在但无权限时为 permissionRequired）；Catalog 分组、评分、标签、编辑记录和既有派生缩略图不得消失。离线时只能浏览已缓存缩略图，不能读源文件。
3. 重新连接同一设备，运行诊断后重新扫描。确认 online，且相对路径相同的资产、编辑、评分、标签、相册和堆栈都被保留；随后实际打开编辑器并导出一个新的文件，确认源文件未被覆盖。
4. 在 Finder 中修改卷名后断开并重新连接；重启应用、运行诊断并重新扫描。确认报告记录新卷名，稳定的卷 UUID 仍可用于核对同一设备，Catalog 状态不被删除。若 bookmark 不能恢复，使用“重新定位文件夹…”只重新授权根映射，再检查资产 ID 与组织数据是否保留。

## 限制

- 自动化使用临时本地目录，不能模拟真实 USB/Thunderbolt 断连、HDD 休眠、SD 读卡器、跨进程 sandbox 授权、卷改名时的 Finder/bookmark 行为或系统权限弹窗。
- 诊断不会猜测访问原因：路径缺失时报告 offline；bookmark 失败但上次路径仍存在时报告 permissionRequired。真实设备上的恢复可靠性必须按上述矩阵人工确认。
- 重新连接后需要重新扫描，才会把此前标为 offline 的资产恢复为可编辑/可导出；诊断本身不臆测每个源文件已经回到原路径。
