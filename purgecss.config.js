// PurgeCSS configuration - removes unused CSS rules from the production image.
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css', 'WebContent/pikaday.css'],
  output: 'build/purged-css/',
  // Classes toggled dynamically at runtime (main.js) or used by pikaday
  safelist: {
    standard: [/^is-/, /^pika-/, 'bold'],
    greedy: [/^pika/]
  }
};
