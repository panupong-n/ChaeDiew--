'use strict';
// Run: node test/upload.test.js — SigV4 against AWS's published examples (the same vectors as the native ChaeDiewChecks), S3 locations,
// reply parsing, and real uploads to two local servers: a fake S3 that re-checks the signature and an HTTP endpoint.
const http = require('http');
const { SigV4, sha256Hex, amzDate } = require('../src/sigv4');
const U = require('../src/uploader');

let passed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('PASS  ' + name); } else { console.log('FAIL  ' + name + (detail !== undefined ? '  —  ' + JSON.stringify(detail) : '')); process.exitCode = 1; }
}

(async () => {
  // ---- AWS documentation examples (S3 SigV4)
  const awsDate = new Date(Date.UTC(2013, 4, 24));
  const signer = new SigV4({ accessKey: 'AKIAIOSFODNN7EXAMPLE', secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', region: 'us-east-1' });
  check('SigV4 timestamp format', amzDate(awsDate) === '20130524T000000Z');
  const emptyHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  const get = signer.sign({ method: 'GET', path: '/test.txt', headers: [['host', 'examplebucket.s3.amazonaws.com'], ['range', 'bytes=0-9'], ['x-amz-content-sha256', emptyHash], ['x-amz-date', '20130524T000000Z']], payloadHash: emptyHash, date: awsDate });
  check('SigV4 header-signed GET matches AWS example', get.signature === 'f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41', get.signature);
  const body = Buffer.from('Welcome to Amazon S3.');
  const put = signer.sign({ method: 'PUT', path: '/test$file.text', headers: [['date', 'Fri, 24 May 2013 00:00:00 GMT'], ['host', 'examplebucket.s3.amazonaws.com'], ['x-amz-content-sha256', sha256Hex(body)], ['x-amz-date', '20130524T000000Z'], ['x-amz-storage-class', 'REDUCED_REDUNDANCY']], payloadHash: sha256Hex(body), date: awsDate });
  check('SigV4 PUT (with $ in the key) matches AWS example', put.signature === '98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd', put.signature);
  const pre = signer.presignedURL({ host: 'examplebucket.s3.amazonaws.com', path: '/test.txt', expires: 86400, date: awsDate });
  check('SigV4 presigned URL matches AWS example', pre.endsWith('X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404'), pre);

  // ---- locations, keys, replies
  check('AWS endpoint uses virtual-hosted style', U.s3Location({ region: 'eu-west-1', bucket: 'b' }, 'x/y.png').host === 'b.s3.eu-west-1.amazonaws.com');
  const loc = U.s3Location({ endpoint: 'http://localhost:9000', bucket: 'b' }, 'x/y.png');
  check('custom endpoint uses path style with its port', loc.host === 'localhost:9000' && loc.path === '/b/x/y.png' && loc.scheme === 'http');
  check('object key: prefix / random / name, spaces replaced', /^shots\/[0-9a-f]{12}\/my-shot\.png$/.test(U.objectKey('/shots/', 'my shot.png')));
  check('upload reply parsing: json url / nested / bare / none',
    U.parseLink('{"url":"https://a/b"}') === 'https://a/b' && U.parseLink('{"data":{"url":"https://c/d"}}') === 'https://c/d'
    && U.parseLink('https://e/f\n') === 'https://e/f' && U.parseLink('nope') === null);

  // ---- a fake S3 that recomputes the signature from what it received (rejects a wrong secret or a changed body)
  const store = new Map();
  const s3 = http.createServer((req, res) => {
    const chunks = []; req.on('data', c => chunks.push(c)); req.on('end', () => {
      const data = Buffer.concat(chunks), auth = req.headers.authorization || '';
      const m = /Credential=([^/]+)\/(\d{8})\/([^/]+)\/s3\/aws4_request, SignedHeaders=([^,]+), Signature=([0-9a-f]{64})/.exec(auth);
      if (req.method !== 'PUT' || !m) { res.writeHead(403); res.end('no auth'); return; }
      if (sha256Hex(data) !== req.headers['x-amz-content-sha256']) { res.writeHead(400); res.end('XAmzContentSHA256Mismatch'); return; }
      const d = req.headers['x-amz-date'], date = new Date(Date.UTC(+d.slice(0, 4), +d.slice(4, 6) - 1, +d.slice(6, 8), +d.slice(9, 11), +d.slice(11, 13), +d.slice(13, 15)));
      const headers = m[4].split(';').map(n => [n, req.headers[n]]);
      const expect = new SigV4({ accessKey: m[1], secretKey: 'server-secret', region: m[3] }).sign({ method: 'PUT', path: decodeURIComponent(req.url), headers, payloadHash: req.headers['x-amz-content-sha256'], date });
      if (expect.signature !== m[5]) { res.writeHead(403); res.end('SignatureDoesNotMatch'); return; }
      store.set(decodeURIComponent(req.url), data); res.writeHead(200); res.end();
    });
  });
  await new Promise(r => s3.listen(0, '127.0.0.1', r));
  const port = s3.address().port;
  const cfg = { endpoint: `http://127.0.0.1:${port}`, region: 'ap-southeast-1', bucket: 'shots', prefix: 'team', accessKey: 'AK', secretKey: 'server-secret', expirySeconds: 600 };
  const png = Buffer.from('fake png bytes ภาพ');
  const link = await U.uploadS3(png, { fileName: 'Tenix-ChaeDiew 2026.png', contentType: 'image/png', cfg });
  const keyStored = [...store.keys()][0];
  check('S3 upload: the fake S3 accepts the signed PUT and stores the bytes', store.size === 1 && store.get(keyStored).equals(png) && /^\/shots\/team\/[0-9a-f]{12}\/Tenix-ChaeDiew-2026\.png$/.test(keyStored), keyStored);
  check('S3 upload: the link is presigned for the configured time', link.startsWith(`http://127.0.0.1:${port}/shots/team/`) && /X-Amz-Expires=600/.test(link) && /X-Amz-Signature=[0-9a-f]{64}$/.test(link), link);
  let err = null; try { await U.uploadS3(png, { fileName: 'a.png', contentType: 'image/png', cfg: { ...cfg, secretKey: 'wrong' } }); } catch (e) { err = e; }
  check('S3 upload: a wrong secret is refused by the server and reported', err && err.code === 'server' && /403/.test(err.message), err && err.message);
  const pub = await U.uploadS3(png, { fileName: 'b c.png', contentType: 'image/png', cfg: { ...cfg, publicBase: 'https://cdn.example.com/' } });
  check('S3 upload: a public base gives a plain link', /^https:\/\/cdn\.example\.com\/team\/[0-9a-f]{12}\/b-c\.png$/.test(pub), pub);
  err = null; try { await U.uploadS3(png, { fileName: 'a.png', contentType: 'image/png', cfg: { ...cfg, bucket: '' } }); } catch (e) { err = e; }
  check('S3 upload: missing settings are reported before any network use', err && err.code === 'notConfigured');
  s3.close();

  // ---- an HTTP endpoint: multipart field "file", bearer token, JSON reply
  let seen = null;
  const web = http.createServer((req, res) => {
    const chunks = []; req.on('data', c => chunks.push(c)); req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('latin1');
      seen = { auth: req.headers.authorization, type: req.headers['content-type'], hasFile: /name="file"; filename="shot\.png"/.test(raw) && raw.includes('PNGDATA') };
      res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ data: { url: 'https://files.example.com/abc.png' } }));
    });
  });
  await new Promise(r => web.listen(0, '127.0.0.1', r));
  const l2 = await U.uploadHTTP(Buffer.from('PNGDATA'), { fileName: 'shot.png', contentType: 'image/png', url: `http://127.0.0.1:${web.address().port}/upload`, token: 'T0K' });
  check('HTTP upload: multipart "file" with a bearer token, link taken from the reply', l2 === 'https://files.example.com/abc.png' && seen.auth === 'Bearer T0K' && seen.hasFile && /multipart\/form-data; boundary=/.test(seen.type), seen);
  web.close();

  console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
})().catch(e => { console.log('FAIL  ' + e.stack); process.exitCode = 1; });
