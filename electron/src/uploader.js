'use strict';
// Upload to S3-compatible storage (signed PUT, then a presigned or public link) or to an internal HTTP endpoint (multipart POST, the
// reply contains the link). A port of the native app's Uploader.swift. Nothing leaves the computer unless the user configured this.
const crypto = require('crypto');
const { SigV4, uriEncode, amzDate, sha256Hex } = require('./sigv4');

class UploadError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

/** Where an object lives: AWS uses virtual-hosted style, a custom endpoint path style. */
function s3Location(cfg, key) {
  const endpoint = String(cfg.endpoint || '').trim();
  if (!endpoint) return { scheme: 'https', host: `${cfg.bucket}.s3.${cfg.region}.amazonaws.com`, path: `/${key}` };
  let url;
  try { url = new URL(endpoint.includes('://') ? endpoint : `https://${endpoint}`); } catch { throw new UploadError('notConfigured', 'endpoint'); }
  return { scheme: url.protocol.replace(':', ''), host: url.host, path: `/${cfg.bucket}/${key}` };
}

/** Unguessable key: prefix / random id / file name. */
function objectKey(prefix, fileName) {
  const id = crypto.randomBytes(6).toString('hex');
  const clean = String(prefix || '').replace(/^[\/\s]+|[\/\s]+$/g, '');
  return [clean, id, String(fileName).replace(/ /g, '-')].filter(Boolean).join('/');
}

/** Accepts {"url": …}, {"link": …}, {"data": {"url": …}} or a bare URL. */
function parseLink(text) {
  try {
    const j = JSON.parse(text);
    for (const c of [j && j.url, j && j.link, j && j.data && j.data.url]) if (typeof c === 'string' && /^[a-z][a-z0-9+.-]*:\/\//i.test(c)) return c;
  } catch { /* not JSON */ }
  const t = String(text).trim();
  return /^https?:\/\//i.test(t) && !/\s/.test(t) ? t : null;
}

async function uploadS3(data, { fileName, contentType, cfg, fetchImpl = fetch, now = () => new Date() }) {
  if (!cfg.bucket || !cfg.accessKey || !cfg.secretKey) throw new UploadError('notConfigured', 'bucket / access key / secret key');
  const key = objectKey(cfg.prefix, fileName);
  const loc = s3Location(cfg, key);
  const signer = new SigV4({ accessKey: cfg.accessKey, secretKey: cfg.secretKey, region: cfg.region || 'us-east-1' });
  const date = now(), payloadHash = sha256Hex(data);
  const headers = [['host', loc.host], ['content-type', contentType], ['x-amz-content-sha256', payloadHash], ['x-amz-date', amzDate(date)]];
  const authorization = signer.authorizationHeader({ method: 'PUT', path: loc.path, headers, payloadHash, date });
  const res = await fetchImpl(`${loc.scheme}://${loc.host}${uriEncode(loc.path, true)}`, {
    method: 'PUT', body: data, headers: { ...Object.fromEntries(headers.filter(([n]) => n !== 'host')), Authorization: authorization },
  });
  if (!res.ok) throw new UploadError('server', `${res.status} ${(await res.text()).slice(0, 200)}`);
  const base = String(cfg.publicBase || '').replace(/^[\/\s]+|[\/\s]+$/g, '');
  if (base) return `${base}/${uriEncode(key, true)}`;
  return signer.presignedURL({ scheme: loc.scheme, host: loc.host, path: loc.path, expires: Math.max(60, Number(cfg.expirySeconds) || 3600), date: now() });
}

async function uploadHTTP(data, { fileName, contentType, url, token, fetchImpl = fetch }) {
  let target;
  try { target = new URL(url); } catch { throw new UploadError('notConfigured', 'URL'); }
  const boundary = 'chaediew-' + crypto.randomBytes(12).toString('hex');
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${String(fileName).replace(/"/g, '')}"\r\nContent-Type: ${contentType}\r\n\r\n`),
    Buffer.from(data), Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  const headers = { 'Content-Type': `multipart/form-data; boundary=${boundary}` };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetchImpl(target.toString(), { method: 'POST', body, headers });
  const text = await res.text();
  if (!res.ok) throw new UploadError('server', `${res.status} ${text.slice(0, 200)}`);
  const link = parseLink(text);
  if (!link) throw new UploadError('badResponse', 'no link in the reply');
  return link;
}

module.exports = { uploadS3, uploadHTTP, parseLink, objectKey, s3Location, UploadError };
