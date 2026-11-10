'use strict';
// Lambda@Edge (CloudFront origin-request trigger): fetches the HTML page from the origin,
// generates a per-response CSP nonce, replaces the __CSP_NONCE__ placeholder and sets the
// Content-Security-Policy header. Non-HTML requests pass through unchanged.
const crypto = require('crypto');
const https = require('https');

function fetchOrigin(domain, path) {
  return new Promise((resolve, reject) => {
    https.get({ host: domain, path }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
    }).on('error', reject);
  });
}

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const isHtml = request.uri === '/' || request.uri.endsWith('.html');
  if (!isHtml) return request;

  const origin = request.origin.custom || request.origin.s3;
  const domain = origin.domainName;
  const uri = request.uri === '/' ? '/index.html' : request.uri;
  const originRes = await fetchOrigin(domain, (origin.path || '') + uri);

  const nonce = crypto.randomBytes(16).toString('base64');
  const body = originRes.body.replace(/__CSP_NONCE__/g, nonce);

  return {
    status: String(originRes.status),
    statusDescription: 'OK',
    headers: {
      'content-type': [{ key: 'Content-Type', value: 'text/html; charset=utf-8' }],
      'content-security-policy': [{
        key: 'Content-Security-Policy',
        value: `default-src 'self'; script-src 'self' 'nonce-${nonce}'; style-src 'self' https://fonts.googleapis.com 'unsafe-inline'; font-src https://fonts.gstatic.com; img-src 'self' data:`
      }],
      'cache-control': [{ key: 'Cache-Control', value: 'no-store' }]
    },
    body
  };
};
