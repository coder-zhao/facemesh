# FaceMesh Android/iOS 可交互贴图 Demo

这是一个基于 **MediaPipe Face Landmarker** 的实时相机贴图 Demo，贴图会跟随 FaceMesh（Android 已升级为 **多点分片仿射**，iOS 目前为三点锚定）。

## 已实现

- 前置相机实时预览（Android CameraX / iOS AVFoundation）
- 实时人脸关键点检测（MediaPipe Tasks Vision）
- 贴图（PNG）跟随 mesh：
  - Android：`8~20` 点级别的分片三角形仿射跟随（当前用 9 点网格）
  - iOS：三点仿射锚定（`33/263/168`）
- Android 可交互控制：
  - 开关贴图显示
  - 滑条调整 mesh 缩放

## Mesh 跟随方案（关键）

### Android（已升级）

Android 已实现 **9 点 + 分片三角形（piecewise affine）**：

- 关键点：`33/263/168/133/362/105/334/127/356`
- 每个小三角形单独 `Matrix.setPolyToPoly(..., 3)`
- 逐三角形裁剪绘制，贴图会随局部 mesh 产生更自然的非刚性变化

### iOS（当前）

iOS 仍为三点仿射（`33/263/168`），适合快速 Demo。

## 要应对头部各种动作，多少点位才够？

结论先说：**3 点只够做“平面近似”的 Demo，不够应对大幅转头导致的非线性变形**。

可按目标效果分档：

1. **基础可用（轻微转头）**：`3~5` 点
   - 3 点仿射：可跟随平移/旋转/缩放/剪切；
   - 增加到 4 点可做透视（四点映射），对 yaw/pitch 会更稳一点。

2. **中等真实（常见头动）**：`8~20` 点 + 分片三角形
   - 将贴图区域切成多个小三角形（piecewise affine）；
   - 每个小三角形各自跟随对应 mesh 点，能明显改善转头、嘴角/脸颊附近拉伸。

3. **高真实（大角度、表情丰富）**：`20~60+` 点（或整块区域网格）
   - 贴图按 UV 贴到人脸网格区域（类似 AR mask）；
   - 再叠加遮挡处理（深度/分层）与时序平滑，效果最稳定。

### 推荐实践（眼镜贴图）

- 快速版本：继续用 `33/263/168`（当前实现）。
- 想显著抗转头：至少增加到“眼周 + 鼻梁 + 太阳穴”约 `8~12` 点并做分片仿射。
- 若目标是“看起来像真戴在脸上”：建议走网格贴图方案（`20+` 点起步）。

## Android release APK 构建

### 运行前准备

1. 安装 Android Studio（JDK 17）
2. 放置模型：`android-demo/app/src/main/assets/face_landmarker.task`
3. 可选放置贴图：`android-demo/app/src/main/assets/glasses.png`

> 若不提供 `glasses.png`，Demo 会自动使用程序内置眼镜占位图。

### Debug

```bash
cd android-demo
gradle assembleDebug
```

输出：`app/build/outputs/apk/debug/app-debug.apk`

### Release（unsigned）

```bash
cd android-demo
gradle assembleRelease
```

输出：`app/build/outputs/apk/release/app-release-unsigned.apk`

### Release（signed）

```bash
keytool -genkeypair -v -keystore facemesh-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias facemesh
export FACEMESH_STORE_FILE=/abs/path/facemesh-release.jks
export FACEMESH_STORE_PASSWORD=******
export FACEMESH_KEY_ALIAS=facemesh
export FACEMESH_KEY_PASSWORD=******
cd android-demo
gradle assembleRelease
```
