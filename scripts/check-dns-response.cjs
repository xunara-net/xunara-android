const assert = require('node:assert/strict');
const fs = require('node:fs');

let bytes = fs.readFileSync(process.argv[2]);
if (process.argv[3] === 'tcp') {
  assert.ok(bytes.length >= 2, 'DNS TCP response missing');
  assert.ok(bytes.length >= bytes.readUInt16BE(0) + 2, 'DNS TCP response incomplete');
  bytes = bytes.subarray(2, bytes.readUInt16BE(0) + 2);
}
assert.ok(bytes.length >= 12, 'DNS response missing');
assert.equal(bytes.readUInt16BE(0), 0x1234);
assert.ok(bytes[2] & 0x80, 'not a DNS response');
const expected = process.argv[4];
const codes = { NXDOMAIN: 3, SERVFAIL: 2 };
assert.equal(bytes[3] & 15, codes[expected] ?? 0);
if (!(expected in codes)) {
  assert.ok(bytes.readUInt16BE(6) > 0, 'DNS answer missing');
  const address = Buffer.from(expected.split('.').map(Number));
  assert.ok(bytes.includes(address), 'expected address missing');
}
