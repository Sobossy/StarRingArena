# 新角色与新技能：风行者

这是一个可直接运行的第五角色示例，默认不出现在选角菜单。它使用已有战场接口实现范围伤害、击退和治疗，没有修改战斗核心。

## 加入选角

在 `data/roster.gd` 的 `CHARACTERS` 数组中加入：

```gdscript
preload("res://examples/wind_pulse/wind_walker.tres"),
```

重新运行工程即可看到“风行者（扩展示例）”；发行版需重新打包。

0.2.0 的角色库继续兼容这个旧场景例子。若还希望在角色编辑页自由添加此技能，请在 `scripts/core/skill_catalog.gd` 的 `ITEMS` 注册 `{ "id": "wind_pulse", "name": "风之脉冲", "type": "主动", "scene": "res://examples/wind_pulse/wind_pulse.tscn" }`，并将示例技能 `tick` 内的 `activate(target)` 改为 `request_cast(target)` 以接入蓄力流程。新建角色后从模板列表选择即可保存。

## 换成自己的角色

1. 复制本目录并修改角色资源的 `id` 和 `display_name`，确保 ID 唯一。
2. 将透明 PNG 放入工程素材目录，在 Godot 中打开角色 `.tres`，把图片拖入 `portrait`。用 `portrait_size` 与 `portrait_offset` 调整显示，用 `radius` 独立设置碰撞大小。
3. 在角色资源中修改生命、攻击、速度、主题颜色。`default_movement` 可设为 `bounce`（反弹）、`chase`（追击）、`kite`（保持距离）或 `wander`（游走）。
4. 打开技能场景调整脉冲半径、冷却、伤害倍率、击退和治疗；或修改技能脚本实现全新行为。
5. 把新角色资源加入登记表，然后运行并测试。不要把当前生命、技能计时器等运行时数据保存在共享角色资源中。

## 技能工作方式

`setup` 为每个战斗实例初始化状态；`tick` 由固定战斗时间步调用；`activate` 请求战场统一结算伤害、治疗并播放效果。游戏暂停或倍速变化时，不使用独立系统计时器，所以技能与战斗时钟始终一致。

`arena.apply_damage` 排队结算伤害，`arena.get_targets` 返回可攻击目标。反击类技能必须检查伤害事件的 `allow_reaction`，并用 `false` 发送反击，避免循环。命中伤害、爆炸与状态都应经过战场接口，不要直接扣改目标生命。

新增脚本属于工程代码，需要重新运行或导出。首版不提供运行时加载外部脚本或可视化技能编辑器。
