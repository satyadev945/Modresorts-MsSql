// PurgeCSS configuration: removes unused CSS rules (e.g. styles.css) from the production image.
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/**/*.js',
  ],
  css: ['WebContent/styles.css'],
  output: 'WebContent/',
  // Classes toggled dynamically at runtime
  safelist: {
    standard: [/^js-/, /^is-/, /^pika-/],
  },
};
