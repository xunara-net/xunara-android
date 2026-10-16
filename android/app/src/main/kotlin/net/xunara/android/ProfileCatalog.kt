package net.xunara.android

data class ProfileCatalog(val current: Profile, val profiles: List<Profile>) {
    fun validated(): ProfileCatalog {
        require(profiles.isNotEmpty() && profiles.size <= 16) { "常用服务器数量须在 1–16 个之间" }
        val entries = profiles.map { it.validated() }
        val active = current.validated()
        require(entries.map { it.server }.distinct().size == entries.size) { "常用服务器不能重复" }
        require(entries.count { it == active } == 1) { "当前服务器不在已保存配置中" }
        return ProfileCatalog(active, entries)
    }

    fun save(profile: Profile): ProfileCatalog {
        val next = profile.validated()
        val saved = profiles.filter { it.server != next.server } + next
        return ProfileCatalog(next, saved).validated()
    }

    fun select(server: String): ProfileCatalog {
        val canonical = current.copy(server = server).validated().server
        return copy(current = profiles.firstOrNull { it.server == canonical } ?: error("该服务器尚未保存")).validated()
    }

    fun remove(server: String): ProfileCatalog {
        val canonical = current.copy(server = server).validated().server
        require(canonical != current.server) { "不能移除当前服务器，请先切换到其他服务器" }
        require(profiles.any { it.server == canonical }) { "该服务器已不存在，请刷新列表" }
        // 这里只删除连接偏好，不接触对应控制面的机器私钥或服务端设备。
        return copy(profiles = profiles.filter { it.server != canonical }).validated()
    }
}
