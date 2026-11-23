module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js',
    'WebContent/lib/pikaday.js'
  ],
  css: ['WebContent/styles.css', 'WebContent/pikaday.css'],
  output: 'purged-css/',
  // Keep @font-face / keyframes / CSS variables intact
  fontFace: false,
  keyframes: false,
  variables: false
};
