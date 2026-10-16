package net.xunara.android

data class ProfileCatalog(val current: Profile, val profiles: List<Profile>) {
    fun validated(): ProfileCatalog {
        require(profiles.isNotEmpty() && profiles.size <= 16) { "账号配置数量须在 1–16 个之间" }
        val entries = profiles.map { it.validated() }
        val active = current.validated()
        require(entries.map { it.id }.distinct().size == entries.size) { "账号配置标识不能重复" }
        require(entries.count { it == active } == 1) { "当前服务器不在已保存配置中" }
        return ProfileCatalog(active, entries)
    }

    fun save(profile: Profile): ProfileCatalog {
        val next = profile.validated()
        require(profiles.none { it.id == next.id && it.server != next.server }) { "更换控制地址请新增账号配置，避免串用设备身份" }
        val saved = profiles.filter { it.validated().id != next.id } + next
        return ProfileCatalog(next, saved).validated()
    }

    fun select(id: String): ProfileCatalog {
        return copy(current = profiles.firstOrNull { it.validated().id == id } ?: error("该账号配置尚未保存")).validated()
    }

    fun remove(id: String): ProfileCatalog {
        require(id != current.validated().id) { "不能移除当前账号，请先切换到其他账号" }
        require(profiles.any { it.validated().id == id }) { "该账号配置已不存在，请刷新列表" }
        // 这里只删除连接偏好，不接触对应控制面的机器私钥或服务端设备。
        return copy(profiles = profiles.filter { it.validated().id != id }).validated()
    }
}
