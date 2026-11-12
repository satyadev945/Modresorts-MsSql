// PurgeCSS configuration used by the multi-stage Dockerfile (cz-css-1005)
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css'],
  output: 'build/purged-css/',
  // Classes toggled dynamically from JavaScript / used by .bold text (styles.css line 13)
  safelist: {
    standard: ['bold', 'is-selected'],
    greedy: [/^js-/, /^is-/]
  }
};
