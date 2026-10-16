package net.xunara.android

import org.json.JSONObject

object VpnState {
    private var value = JSONObject().put("phase", "disconnected")

    @Synchronized fun snapshot(): String = value.toString()

    @Synchronized fun phase(): String = value.optString("phase", "disconnected")

    @Synchronized fun begin(generation: Long = 0, reconnecting: Boolean = false) {
        value = JSONObject().put("phase", if (reconnecting) "reconnecting" else "connecting")
            .put("generation", generation).put("message", "正在安全连接服务器")
    }

    @Synchronized fun generation(): Long = value.optLong("generation")

    @Synchronized fun network(label: String, reconnects: Int) {
        value.put("network_label", label).put("reconnects", reconnects)
    }

    @Synchronized fun reconnecting(message: String) {
        value.put("phase", "reconnecting").put("message", message)
        value.remove("status")
        value.remove("authorization_url")
    }

    @Synchronized fun stopping() {
        value.put("phase", "stopping").remove("authorization_url")
    }

    @Synchronized fun finish(error: String? = null, generation: Long? = null) {
        if (generation != null && generation != generation()) return
        value = JSONObject().put("phase", if (error == null) "disconnected" else "error")
        if (error != null) value.put("message", error)
    }

    @Synchronized fun update(event: JSONObject) {
        if (phase() == "stopping") return
        when (event.optString("type")) {
            "configuration" -> value.put("skipped_routes", event.optJSONArray("skipped_routes") ?: org.json.JSONArray())
            "authorization" -> {
                value.put("phase", "authorizing").put("authorization_url", event.getString("url"))
                    .put("message", "请在浏览器中登录并批准这台设备")
            }
            "reconnecting" -> {
                if (!value.has("authorization_url")) value.put("phase", "reconnecting")
                value.put("message", event.optString("message"))
            }
            "status" -> {
                value.put("status", event)
                if (event.optBoolean("online")) {
                    value.put("phase", "connected").put("message", "设备已通过授权，组网已连接")
                    value.remove("authorization_url")
                } else if (phase() == "connected") {
                    value.put("phase", "reconnecting").put("message", "网络映射已失效，暂停转发并重连")
                }
            }
        }
    }
}
