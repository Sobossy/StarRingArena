# 当前测试入口

当前默认运行`Test.ps1`：当前角色规则、云璃定向机制、技能参数保存、编辑/战斗关键流程、移动导航，以及跨进程图片和配置存档。日常快速更新用`UpdatePhone.cmd`，不重复完整测试。

阶段验证可运行`Test.ps1 -Extended`，增加八人个人/组队对战。当前规则以`current_rules.gd`为准，云璃机制见`yunli_tests.gd`，UI以`current_ui_smoke.gd`为准。

旧的`test_runner.gd`、`extension_tests.gd`、`destruction_tests.gd`、`feedback_tests.gd`、`ui_smoke.gd`等保留作历史接口参考，包含已移除的四角色及旧球棒“整趟仅一次命中”的断言，适用于之前对应Git标签，不再作为新版默认测试入口。不要用旧规则断言判断新的往返分别命中机制。
