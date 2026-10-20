package net.xunara.android

internal object UnderlayFingerprint {
    fun of(selected: Long?, name: String?, addresses: List<String>, localNetworks: List<String>): String =
        "$selected/$name/${addresses.distinct().sorted()}:${localNetworks.distinct().sorted()}"
}
