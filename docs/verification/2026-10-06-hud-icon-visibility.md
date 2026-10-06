# HUD 图标区域显示模式验证记录

对应规格：`docs/plan/2026-10-06-hud-icon-visibility.md`。

## 开发阶段与提交

| 阶段 | 内容 | 验证结果 | 提交 |
| --- | --- | --- | --- |
| 一 | 三值枚举、独立偏好键、保存恢复和非法值回退 | 偏好测试 15 项通过 | `0491489` |
| 二 | 外观判定及几何状态接入模式 | 外观和几何测试共 11 项通过 | `0cad6c5` |
| 三 | 应用模型、控制器订阅、初始化、动画及窗口替换接入模式 | 窗口控制测试 18 项，16 通过、2 因录屏权限跳过、0 失败 | `527990e` |
| 四 | 设置页新增三段选择、标签及阈值说明 | `swift build` 通过；代码核查原生语义控件、顺序和直接模型绑定 | `17f4e0d` |
| 五 | 补充复杂状态转换和实屏测试入口，相关回归与构建验证 | 相关测试 67 项，63 通过、4 因录屏权限跳过、0 失败；构建通过 | 本记录所在提交 |

每阶段提交后连续进入下一阶段。构建初次因沙箱无法写编译缓存失败，经允许在沙箱外执行后通过；不是源代码编译错误。

## 最终验证命令

```sh
swift test --filter 'HUDPreferencesTests|HUDBackgroundAppearanceTests|HUDGeometryStateTests|HUDLayoutControllerTests|HUDPlaceholderHandoffTests|HUDMenuTests'
swift build
git diff --check
```

测试运行时间：2026-10-06，最终相关回归耗时约 34 秒。保留已有屏幕截图 API 弃用警告，本功能没有修改截图基础设施。

## 已验证的功能与边界

- 偏好不存在、字符串无效、数字或布尔值时回退自动；三模式跨偏好实例恢复，不影响透明度。
- 三种模式 × 0%、79%、80%、81%、100% × 四种布局，包含尺寸、固定边及参考矩形往返。
- 背景透明度、材质值独立于图标模式；100% 始终显示、0% 始终隐藏正确。
- 应用启动时直接恢复正确图标比例；模式属性只保存选择，窗口控制器管理后续动画。
- 图标模式切换保持同一窗口，四布局中的显示与隐藏尺寸正确，背景继续按透明度变化。
- 连续切换和反向动画从当前可见状态继续，最终采用最后一次选择。
- 拖动中多次更改模式不改变当前尺寸，松手后使用最新模式；正常拖动保存位置，尺寸过渡不覆盖位置。
- 隐藏期间更改模式不主动显示 HUD；再次显示保持最新模式，钉住及鼠标穿透继续有效。
- 手动模式及自动阈值两侧，在四布局、无会话到有会话及返回无会话的窗口替换中保持正确状态。
- 尺寸动画被布局或会话展示模式改变中断后，新窗口尺寸和图标比例一致。
- 既有窗口回收、标题展示交接、屏幕边缘参考位置和菜单功能回归通过。

## 未验证项与验收边界

四项测试因 `CGPreflightScreenCaptureAccess()` 返回 false 跳过：

- `HUDLayoutControllerTests.testScreenCompositeAfterPanelReplacementLayoutSwitch`。
- `HUDLayoutControllerTests.testScreenCompositeForIconModesAndRapidLayoutChanges`，本需求新增，包含四布局的自动 79%／80%、100% 始终显示、0% 始终隐藏及快速布局切换。
- `HUDLayoutControllerTests.testScreenLayoutChangesAfterCrossScreenRoundTrip`。
- `HUDPlaceholderHandoffTests.testScreenFirstShortTitleHandoffWithoutLayoutChangeOrMovement`。

因此真实桌面合成画面中的残影、图标视觉裁切和留白尚未通过截图验收。窗口几何和状态测试通过不能代替这些结论。设置控件在不同主题下的实屏外观及 VoiceOver 实际朗读未人工验收。减少动态效果使用原有系统判断和已通过的纯过渡终态测试，未修改用户系统设置来强制验收。

获得录屏权限后可重跑上述截图测试；在四种布局手工检查设置控件及显示切换。没有自动安装、部署或发布。
