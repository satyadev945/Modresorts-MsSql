// PurgeCSS configuration used in the Docker build stage (cz-css-1005)
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css', 'WebContent/pikaday.css'],
  output: 'WebContent/',
  // Keep classes that are toggled dynamically at runtime, and the used .bold rule
  safelist: {
    standard: ['bold'],
    greedy: [/^is-/, /^pika-/, /^has-/]
  }
};
