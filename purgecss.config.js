// PurgeCSS configuration: removes unused rules from WebContent/styles.css
// during the container image build (see Dockerfile, "css-purge" stage).
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css'],
  output: 'purged-css/',
  // Classes toggled dynamically at runtime from JavaScript
  safelist: ['is-selected', 'bold'],
  keyframes: true,
  fontFace: true,
  variables: true
};
