'use strict';
// AWS Signature Version 4, enough for S3 PUT uploads and presigned GET links; works with any S3-compatible store (MinIO, R2, Ceph…).
// A port of the native app's SigV4.swift, checked against AWS's published examples in test/upload.test.js.
const crypto = require('crypto');

const pad = n => String(n).padStart(2, '0');
const amzDate = d => `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
const dateStamp = d => amzDate(d).slice(0, 8);
const sha256Hex = data => crypto.createHash('sha256').update(data).digest('hex');
const hmac = (key, msg) => crypto.createHmac('sha256', key).update(msg, 'utf8').digest();

/** RFC 3986 percent-encoding as SigV4 requires (A–Z a–z 0–9 - _ . ~ stay); `/` is kept only inside paths. */
function uriEncode(s, keepSlash = false) {
  let out = '';
  for (const byte of Buffer.from(String(s), 'utf8')) {
    const c = String.fromCharCode(byte);
    if (/[A-Za-z0-9\-_.~]/.test(c) || (keepSlash && c === '/')) out += c;
    else out += '%' + byte.toString(16).toUpperCase().padStart(2, '0');
  }
  return out;
}

class SigV4 {
  constructor({ accessKey, secretKey, region, service = 's3' }) { Object.assign(this, { accessKey, secretKey, region, service }); }
  scope(date) { return `${dateStamp(date)}/${this.region}/${this.service}/aws4_request`; }
  signingKey(date) {
    const k1 = hmac('AWS4' + this.secretKey, dateStamp(date)), k2 = hmac(k1, this.region), k3 = hmac(k2, this.service);
    return hmac(k3, 'aws4_request');
  }
  static canonicalQuery(items) {
    return items.map(([n, v]) => [uriEncode(n), uriEncode(v)])
      .sort((a, b) => (a[0] === b[0] ? (a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0) : a[0] < b[0] ? -1 : 1))
      .map(([n, v]) => `${n}=${v}`).join('&');
  }
  /** `path` is the unencoded absolute path ("/bucket/my file.png"). Returns { signature, signedHeaders }. */
  sign({ method, path, query = [], headers, payloadHash, date }) {
    const norm = headers.map(([n, v]) => [n.toLowerCase(), String(v).trim()]).sort((a, b) => (a[0] < b[0] ? -1 : 1));
    const canonicalHeaders = norm.map(([n, v]) => `${n}:${v}\n`).join('');
    const signedHeaders = norm.map(([n]) => n).join(';');
    const canonicalRequest = [method, uriEncode(path, true), SigV4.canonicalQuery(query), canonicalHeaders, signedHeaders, payloadHash].join('\n');
    const stringToSign = ['AWS4-HMAC-SHA256', amzDate(date), this.scope(date), sha256Hex(canonicalRequest)].join('\n');
    return { signature: hmac(this.signingKey(date), stringToSign).toString('hex'), signedHeaders };
  }
  authorizationHeader(opts) {
    const { signature, signedHeaders } = this.sign(opts);
    return `AWS4-HMAC-SHA256 Credential=${this.accessKey}/${this.scope(opts.date)}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  }
  /** A time-limited link that needs no credentials. */
  presignedURL({ method = 'GET', scheme = 'https', host, path, expires, date }) {
    const query = [
      ['X-Amz-Algorithm', 'AWS4-HMAC-SHA256'], ['X-Amz-Credential', `${this.accessKey}/${this.scope(date)}`], ['X-Amz-Date', amzDate(date)],
      ['X-Amz-Expires', String(expires)], ['X-Amz-SignedHeaders', 'host'],
    ];
    const { signature } = this.sign({ method, path, query, headers: [['host', host]], payloadHash: 'UNSIGNED-PAYLOAD', date });
    return `${scheme}://${host}${uriEncode(path, true)}?${SigV4.canonicalQuery(query)}&X-Amz-Signature=${signature}`;
  }
}

module.exports = { SigV4, uriEncode, amzDate, dateStamp, sha256Hex };
