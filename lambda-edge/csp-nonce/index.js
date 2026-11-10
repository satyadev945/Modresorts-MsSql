'use strict';
/**
 * Lambda@Edge (origin-request) - CSP nonce injection.
 * Generates a per-request nonce, replaces the __CSP_NONCE__ placeholder in the
 * HTML served by the origin and returns a Content-Security-Policy header that
 * only allows scripts carrying that nonce.
 * Deploy to us-east-1 and associate with the CloudFront origin-request event.
 */
const crypto = require('crypto');
const https = require('https');

const PLACEHOLDER = /__CSP_NONCE__/g;

function fetchOrigin(host, path) {
  return new Promise((resolve, reject) => {
    https.get({ host, path, headers: { Accept: 'text/html' } }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
    }).on('error', reject);
  });
}

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const isHtml = request.uri === '/' || request.uri.endsWith('.html');
  if (!isHtml) {
    return request;
  }
  const origin = request.origin.custom || request.origin.s3;
  const host = origin.domainName;
  const path = (origin.path || '') + (request.uri === '/' ? '/index.html' : request.uri);

  const nonce = crypto.randomBytes(16).toString('base64');
  const origRes = await fetchOrigin(host, path);
  if (origRes.status !== 200) {
    return { status: String(origRes.status), statusDescription: 'Origin error' };
  }
  const csp = "default-src 'self'; script-src 'self' 'nonce-" + nonce + "'; " +
    "style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; " +
    "img-src 'self' https://icons.wxug.com data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'";

  return {
    status: '200',
    statusDescription: 'OK',
    headers: {
      'content-type': [{ key: 'Content-Type', value: 'text/html; charset=UTF-8' }],
      'content-security-policy': [{ key: 'Content-Security-Policy', value: csp }],
      'cache-control': [{ key: 'Cache-Control', value: 'no-store' }]
    },
    body: origRes.body.replace(PLACEHOLDER, nonce)
  };
};
