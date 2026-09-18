local _ = require("gettext")
-- 注意：不要在 _meta.lua 里写 name 字段，PluginLoader 会打 deprecation 警告并忽略它；
-- 插件的内部名取自目录名 / 类里的 name 字段。
return {
    fullname = _("阅读足迹"),
    description = _([[轻量版阅读统计：日历阅读热力图与阅读分析，从顶部菜单进入。由 userpatch 改造为 koplugin。]]),
}
