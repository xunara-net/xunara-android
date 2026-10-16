const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { callbacks, verify } = require('./check-jni-contract.cjs');

const source = fs.readFileSync(path.join(__dirname, '../native/src/lib.rs'), 'utf8');
const declarations = callbacks(source).map(method => `.method public final ${method}`);

test('从实际 Rust 调用点提取原始 JNI 名称和签名', () => {
  assert.ok(callbacks(source).includes('dnsServers()Ljava/lang/String;'));
  assert.ok(callbacks(source).includes('localEndpoints(I)Ljava/lang/String;'));
  assert.ok(callbacks(source).includes('configureTunnel(Ljava/lang/String;)I'));
  assert.equal(verify(source, declarations.join('\n')), declarations.length);
});

test('拒绝 0.3.0 Release 中被删除的 DNS 回调', () => {
  const dex = declarations.filter(method => !method.includes('dnsServers')).join('\n');
  assert.throws(() => verify(source, dex), /dnsServers/);
});

test('拒绝被改名、改签名、变为静态或不再公开的回调', () => {
  for (const replacement of [
    '.method public final a()Ljava/lang/String;',
    '.method public final dnsServers(I)Ljava/lang/String;',
    '.method public static dnsServers()Ljava/lang/String;',
    '.method private final dnsServers()Ljava/lang/String;',
  ]) {
    const dex = declarations.map(method => method.includes('dnsServers') ? replacement : method).join('\n');
    assert.throws(() => verify(source, dex), /dnsServers/);
  }
});

test('新增 Rust 回调也必须出现在 APK 中', () => {
  assert.throws(() => verify(`${source}\nself.strings("newCallback", None)`, declarations.join('\n')), /newCallback/);
});

test('无法解析的动态 JNI 调用失败关闭', () => {
  assert.throws(() => callbacks(`${source}\nself.call(dynamicName, signature)`), /解析不完整/);
  assert.throws(() => callbacks(''), /解析不完整/);
});
