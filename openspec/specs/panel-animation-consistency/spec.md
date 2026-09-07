# panel-animation-consistency Specification

## Purpose
Defines version-aware panel animation behavior so detail disclosure, expansion, and progress-meter transitions stay smooth and consistent across supported macOS versions.

## Requirements

### Requirement: Version-aware detail disclosure transition
The system SHALL share a single `detailDisclosure` transition across all expandable sections in the panel (`MetricGlassRow`, `NetworkGlassRow`, `BatteryGlassRow`, and `DisplayControlsSection`). Because the panel is now hosted in a self-owned `NSPanel` whose height is animated at the window layer (see `fluid-menu-bar-panel`), the transition SHALL be identical on macOS 15 and macOS 26+ and SHALL NOT branch by OS version.

#### Scenario: Unified transition on all supported versions
- **WHEN** any expandable row is expanded or collapsed on macOS 15 or macOS 26+
- **THEN** the content transition SHALL be the same definition on both versions
- **AND** the transition SHALL NOT introduce geometric interpolation that competes with the window-layer height animation

#### Scenario: Height change is smooth without flicker
- **WHEN** a row is expanded or collapsed
- **THEN** the panel height SHALL interpolate smoothly via the window layer
- **AND** no leftover removal frame SHALL be rendered against a mismatched window size

### Requirement: Version-aware expansion animation
The system SHALL drive expansion state changes through a shared helper. Because the window layer now provides the smooth height interpolation with the top edge anchored (see `fluid-menu-bar-panel`), the helper SHALL mutate expansion state without OS-version branching and without per-version geometric animation, on both macOS 15 and macOS 26+.

#### Scenario: Expansion toggles uniformly
- **WHEN** a row is toggled on macOS 15 or macOS 26+
- **THEN** the expansion state SHALL update through the shared helper on both versions
- **AND** the resulting height change SHALL be interpolated by the window layer, not by a per-version SwiftUI geometry animation

#### Scenario: Top edge stays anchored during animation
- **WHEN** the panel grows or shrinks from an expansion toggle
- **THEN** the top edge SHALL remain anchored at the menu bar throughout the animation

### Requirement: Progress meter smooth transition
The system SHALL animate the progress bar width change in `ProgressMeter` when the value changes.

#### Scenario: Progress bar animates value change
- **WHEN** the `value` parameter of `ProgressMeter` changes
- **THEN** the width transition SHALL animate with `.easeInOut(duration: 0.3)`

### Requirement: 多行同时展开时滚动揭示目标确定
当一次操作展开多个可折叠行时，面板滚动揭示的目标 SHALL 是确定的（指向实际新展开的内容），不得是不确定的任意行。

#### Scenario: 双击展开全部行
- **WHEN** 用户在面板高度受屏幕限制时双击表头一次性展开全部行
- **THEN** 面板滚动到新展开内容的位置，新内容可见
- **AND** 不会停留在与本次展开无关的任意行

### Requirement: 显示器信息分区参与展开状态重置
面板的显示器信息分区的展开状态 SHALL 与其余分区一致地参与面板隐藏重置与默认展开设置，两种分发构建下行为一致。

#### Scenario: 沙盒构建重开面板
- **WHEN** App Store（沙盒）构建下用户展开显示器信息分区、关闭面板再重新打开
- **THEN** 该分区按当前默认展开设置呈现（与 Direct 构建行为一致）
- **AND** 不保留上次会话的临时展开状态
