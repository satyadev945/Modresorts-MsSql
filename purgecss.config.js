// PurgeCSS configuration: strips unused rules from WebContent/styles.css at image build time
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css'],
  output: 'purged-css/',
  // Classes toggled dynamically from JavaScript or third-party widgets must be preserved
  safelist: {
    standard: [/^js-/, /^pika-/, /^is-/],
    greedy: [/^h[1-6]/, /^weather/, /^button/]
  },
  keyframes: true,
  fontFace: true,
  variables: true
};
