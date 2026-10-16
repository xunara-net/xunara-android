# 这些入口由 Rust JNI 的固定符号或字符串调用，R8 不能删除或改名。
-keep class net.xunara.android.NativeBridge { *; }
-keepclassmembers class net.xunara.android.XunaraVpnService {
    public boolean protectSocket(int);
    public int configureTunnel(java.lang.String);
    public java.lang.String localNetworks();
    public java.lang.String localEndpoints(int);
    public java.lang.String dnsServers();
    public void onCoreEvent(java.lang.String);
}
