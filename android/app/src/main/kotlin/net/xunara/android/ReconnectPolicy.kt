package net.xunara.android

/** 只管理连接意图，不保存账号 Session 或接入密钥。所有调用在主线程串行执行。 */
class ReconnectPolicy(private val automatic: Boolean) {
    enum class Action { KEEP, RESTART, STOP }
    var wanted = true
        private set
    var armed = false
        private set
    var pending = false
        private set
    private var fingerprint = ""

    fun started(network: String) {
        fingerprint = network
        pending = false
    }

    fun established(network: String) {
        armed = true
        fingerprint = network
    }

    fun changed(network: String): Action {
        if (!wanted || !armed || (network == fingerprint && !pending)) return Action.KEEP
        if (!automatic) {
            cancel()
            return Action.STOP
        }
        pending = true
        return Action.RESTART
    }

    fun ready(available: Boolean, running: Boolean): Boolean = wanted && armed && pending && available && !running

    fun cancel() {
        wanted = false
        pending = false
    }
}
