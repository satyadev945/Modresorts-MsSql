// PurgeCSS configuration: strips unused rules from styles.css for the production image.
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css'],
  output: 'purged-css/',
  // Keep classes that are toggled dynamically at runtime
  safelist: {
    standard: [/^is-/, 'bold'],
    greedy: [/pika/]
  }
};
