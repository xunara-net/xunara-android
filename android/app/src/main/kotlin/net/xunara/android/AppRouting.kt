package net.xunara.android

enum class AppRoutingMode(val value: String) {
    ALL("all"), EXCLUDE("exclude"), ONLY("only");

    companion object {
        fun parse(value: String): AppRoutingMode = entries.firstOrNull { it.value == value }
            ?: error("应用分流方式无效，请重新设置")
    }
}

data class AppRouting(val mode: AppRoutingMode = AppRoutingMode.ALL, val packages: List<String> = emptyList()) {
    fun validated(): AppRouting {
        require(packages.size <= 256) { "最多选择 256 个应用" }
        require(packages.all { it.length <= 255 && it.matches(Regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+")) }) { "应用标识无效" }
        require("net.xunara.android" !in packages) { "玄序自身始终通过底层网络连接" }
        require(mode != AppRoutingMode.ALL || packages.isEmpty()) { "全部应用模式不能附带应用清单" }
        require(mode != AppRoutingMode.ONLY || packages.isNotEmpty()) { "请至少选择一个使用私有网络的应用" }
        return copy(packages = packages.distinct().sorted())
    }

    fun plan(installed: Set<String>, ownPackage: String): AppRoutingPlan {
        val policy = validated()
        val available = policy.packages.filter { it in installed && it != ownPackage }
        // Android 的空允许清单表示全部应用，而非零应用，必须在建 TUN 前失败关闭。
        if (mode == AppRoutingMode.ONLY) {
            check(available.isNotEmpty()) { "所选应用已卸载或不可用，请重新选择应用后连接" }
            return AppRoutingPlan(available, emptyList())
        }
        return AppRoutingPlan(emptyList(), (available + ownPackage).distinct().sorted())
    }
}

data class AppRoutingPlan(val allowed: List<String>, val disallowed: List<String>)
