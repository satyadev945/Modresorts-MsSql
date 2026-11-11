'use strict';

/**
 * Lambda@Edge handler (CloudFront ORIGIN-RESPONSE / VIEWER-RESPONSE with body access
 * is not available for viewer-response, so deploy as ORIGIN-RESPONSE with
 * "Include body" enabled).
 *
 * Generates a per-response cryptographic nonce, replaces the __CSP_NONCE__ placeholder
 * in HTML inline <script> tags and sets the Content-Security-Policy header.
 */
const crypto = require('crypto');

const PLACEHOLDER = /__CSP_NONCE__/g;

exports.handler = async (event) => {
    const response = event.Records[0].cf.response;
    const headers = response.headers;

    const contentType = headers['content-type'] && headers['content-type'][0].value;
    if (!contentType || contentType.indexOf('text/html') === -1) {
        return response;
    }

    const nonce = crypto.randomBytes(16).toString('base64');

    if (response.body && response.bodyEncoding !== 'base64') {
        response.body = String(response.body).replace(PLACEHOLDER, nonce);
    } else if (response.body) {
        const html = Buffer.from(response.body, 'base64').toString('utf8');
        response.body = Buffer.from(html.replace(PLACEHOLDER, nonce), 'utf8').toString('base64');
    }

    // Body length changed; let CloudFront recompute it
    delete headers['content-length'];

    headers['content-security-policy'] = [{
        key: 'Content-Security-Policy',
        value: "default-src 'self'; script-src 'self' 'nonce-" + nonce + "'; " +
               "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " +
               "font-src 'self' https://fonts.gstatic.com; " +
               "img-src 'self' data: https://icons.wxug.com; connect-src 'self'; object-src 'none'; " +
               "base-uri 'self'; form-action 'self'; frame-ancestors 'self'"
    }];

    return response;
};
