module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css'],
  output: 'WebContent/',
  // Classes toggled dynamically at runtime
  safelist: {
    standard: [/^is-/, /^js-/, /^bold$/]
  }
};
