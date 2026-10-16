const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function callbacks(source) {
  const contracts = [];
  for (const match of source.matchAll(/self\.call\(\s*"(\w+)"\s*,\s*"([^"]+)"/g)) {
    contracts.push(match[1] + match[2]);
  }
  for (const match of source.matchAll(/self\.strings\(\s*"(\w+)"\s*,\s*(None|Some\b)/g)) {
    contracts.push(`${match[1]}(${match[2] === 'None' ? '' : 'I'})Ljava/lang/String;`);
  }
  const calls = [...source.matchAll(/self\.(?:call|strings)\s*\(/g)].length;
  // 新增调用方式时必须同步检查器，不能把无法识别的 JNI 入口静默跳过。
  assert.ok(calls > 0 && contracts.length === calls, 'JNI 回调解析不完整');
  return [...new Set(contracts)].sort();
}

function verify(source, dex) {
  const expected = callbacks(source);
  const actual = new Set();
  for (const match of dex.matchAll(/^\.method\s+([^\r\n]+)/gm)) {
    const parts = match[1].trim().split(/\s+/);
    if (parts.includes('public') && !parts.includes('static')) actual.add(parts.at(-1));
  }
  const missing = expected.filter(method => !actual.has(method));
  assert.equal(missing.length, 0, `APK 缺少未改名的 JNI 回调：${missing.join(', ')}`);
  return expected.length;
}

if (require.main === module) {
  try {
    const apk = process.argv[2];
    assert.ok(apk && fs.statSync(apk).isFile(), '用法：node scripts/check-jni-contract.cjs <release.apk>');
    const sdk = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT || path.join(process.env.HOME, 'Android/Sdk');
    const analyzer = path.join(sdk, 'cmdline-tools/latest/bin/apkanalyzer');
    // 直接检查最终 DEX，不使用会掩盖名称变化的 Proguard 还原映射或 Debug 编译结果。
    const result = spawnSync(analyzer, ['dex', 'code', '--class', 'net.xunara.android.XunaraVpnService', apk], {
      encoding: 'utf8', timeout: 60_000, maxBuffer: 16 * 1024 * 1024,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, '无法检查 Release APK 的 JNI 回调');
    const source = fs.readFileSync(path.join(__dirname, '../native/src/lib.rs'), 'utf8');
    const count = verify(source, result.stdout);
    process.stdout.write(`PASS Release APK 保留全部 ${count} 个 JNI 回调及原始签名\n`);
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { callbacks, verify };
