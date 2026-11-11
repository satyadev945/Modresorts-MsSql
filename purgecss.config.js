// PurgeCSS configuration used during the Docker build stage to strip unused CSS
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css'],
  output: 'purged-css/',
  // Classes toggled dynamically at runtime from JavaScript
  safelist: ['is-selected'],
  keyframes: true,
  fontFace: true,
  variables: true
};
