// PurgeCSS configuration used during the Docker build stage (cz-css-1005).
// Removes CSS rules that are not referenced by any markup/script in the web app.
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js',
    'WebContent/lib/pikaday.js'
  ],
  css: ['WebContent/styles.css', 'WebContent/pikaday.css'],
  output: 'purged-css/',
  // keep classes toggled dynamically by scripts
  safelist: {
    standard: [/^is-/, /^pika-/, /^js-/],
    greedy: [/pika/]
  },
  keyframes: true,
  fontFace: false,
  variables: false
};
