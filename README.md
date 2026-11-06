# 词光 · 音乐歌词播放器

> 非官方移植 · 致敬原作者 · 领航云工作室出品

纯本地、零联网、零内置内容的音乐播放器，专注于逐字歌词体验。

## 特性

- **逐字歌词**：支持 QRC / YRC / TTML / 增强 LRC（`<mm:ss.xx>` 逐字时间戳）格式，逐字跟唱渲染
- **歌词三入口**：同名歌词文件自动匹配 / 文件导入 / 剪贴板粘贴
- **多歌词风格**：烬语（Fume）· 萤川（Luminous）· 镜渊（Diorama 3D 走廊）
- **流动渐变背景**：Metal 实现的 Latent 流动背景，支持多预设配色
- **海报墙首页**：无限随机海报墙，点卡居中交互
- **AVAudioEngine 播放内核**：FLAC 精确 seek，渲染时钟驱动歌词同步

## 系统要求

- iOS 17+ / iPadOS 17+（同时支持 Mac：Designed for iPad）
- Xcode 16+ 构建

## 构建

```bash
git clone <repo>
open LyricGlow.xcodeproj
# Xcode 中选择 LyricGlow scheme，⌘R 运行
```

## 隐私

词光不联网：不请求数据、不收集数据、不内置任何音频或歌词内容。所有文件仅保存在你的设备本地，卸载即删除。

## 许可

本项目基于开源项目 **folia-major**（AGPL-3.0）移植，属其派生作品，遵循同一协议发布：[LICENSE](LICENSE)

    词光 (LyricGlow)
    Copyright (C) 2026 领航云工作室

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as
    published by the Free Software Foundation, either version 3 of the
    License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.
