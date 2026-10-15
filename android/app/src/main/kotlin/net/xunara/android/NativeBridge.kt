package net.xunara.android

object NativeBridge {
    init { System.loadLibrary("xunara_android") }
    @JvmStatic external fun prepare(): Long
    @JvmStatic external fun run(configuration: String, authKey: String, callback: Any, generation: Long): String?
    @JvmStatic external fun stop(generation: Long)
    @JvmStatic external fun version(): String
}
