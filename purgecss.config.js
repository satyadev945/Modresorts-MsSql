// PurgeCSS configuration used by the CSS-optimization stage of the Dockerfile.
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css'],
  output: 'WebContent/',
  // Classes toggled dynamically from JavaScript
  safelist: ['is-selected']
};
