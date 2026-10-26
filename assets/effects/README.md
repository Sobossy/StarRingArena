# 特效素材：迷迷拳击与灰黯之手

使用内置 imagegen 制作。当前拳击图已按用户追加意见改为参考左下角的奶白、浅粉色可爱拳击虚影，取消写实拳头结构。两张图均保留原始透明通道。

| 文件 | 当前输出 | 用法 |
| --- | --- | --- |
| `mimi_punch.png` | 1254×1254，RGBA PNG | 圆润端朝右，短尾在左；不含角色和独立速度线 |
| `ashen_hand.png` | 1254×1254，RGBA PNG | 掌根在右上，长爪朝左下；可旋转放在场地四周 |

生成时目标为1024×1024；内置工具实际返回1254×1254，交付保留高清原图及透明边缘，没有再次缩放或重绘。素材现已接入记忆·星的迷迷拳击及遐蝶的灰黯之手缩圈，角色机制见 `../../docs/记忆与遐蝶.md`。

原始参考副本存放于 `references/`，该目录通过 `.gdignore` 排除游戏导入。未修改用户原图。此前较写实的拳头试稿保留在 imagegen 默认生成目录，不作为正式素材使用。

## 迷迷拳击最终提示词

```text
Use case: precise-object-edit / stylized-concept. Asset type: a cute isolated 2D game punching AFTERIMAGE sprite on a genuine transparent background, square canvas, target 1024x1024. IMPORTANT USER CORRECTION: do not make a detailed fist or realistic hand. Look specifically at the SMALL CREAM-WHITE AND PALE-PINK PUNCHING GHOST AT THE LOWER LEFT of the supplied Mimi sticker (not the circular pink symbol at the lower right). Enlarge and faithfully redraw that simple cute effect only, removing Mimi and everything else. The effect is an airy rounded little mitten/paw-like silhouette: two or three simple rounded bumps at its leading tip, a short soft taper behind, a couple tiny pale-pink curved accent lines, cream-white main fill with a light candy-pink edge. Very simplified flat chibi sticker drawing, minimal linework and almost no shading, soft slightly translucent edges. No anatomically defined knuckles, no muscular hand, no thumb anatomy, no boxing glove, no inflated glossy 3D fist, no fur cuff, no heavy dark outline. Rotate the isolated effect so its rounded punching tip points RIGHT, with the small taper trailing LEFT. Keep it compact and charming, like a little cartoon punch ghost or soft paw swipe, matching exactly the adorable loose style of the reference's lower-left effect. Only ONE effect, centered within the central 72 percent of a square canvas with generous empty transparent margins on all four sides. No character body/head/ears, no text, no ring or badge, no extra effect symbols, no added speed lines, no detached motion trail, no backdrop, no shadow, no watermark. True transparent alpha, never a painted checkerboard.
```

## 灰黯之手最终提示词

```text
Use case: stylized-concept. Asset type: one isolated 2D game effect sprite, square canvas requested 1024x1024 PNG, genuine transparent background. Input reference: use ONLY the dark blue-gray elongated claw-hand shape inside the RED RECTANGLE at the upper right of the reference screenshot. Reconstruct that hand as a clean enlarged game sprite, closely matching its angular silhouette: a compact jagged palm and wrist at UPPER RIGHT, long thin pointed claw-like fingers extending diagonally toward LOWER LEFT, with transparent gaps between the fingers. Dark desaturated navy-blue/charcoal flat fill, narrow muted pale slate-blue edge outline, very minimal interior lines. The reference is a simple eerie silhouette, not a realistic detailed skeleton or fleshy human hand. Preserve the recognizable long tapering talons, palm shape, direction and proportions from the red-box hand. Center the COMPLETE SINGLE hand on the square canvas. IMPORTANT: the silhouette's bounding box must stay within the central 76 percent of the canvas in both axes, leaving at least 12 percent fully empty transparent margin at every edge. Nothing cropped. No wrist or fingers going off canvas. No extra hands, no arm beyond the short wrist root, no detached scratches, no particles, no glow, no environment, no game arena, no white boundary, no colored annotation rectangles, no characters, no text, no UI, no watermark, no ground shadow. True alpha transparency everywhere outside the hand and between all fingers; do not paint a checkerboard or backdrop.
```
