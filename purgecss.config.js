// PurgeCSS configuration: removes CSS rules not referenced by the web content.
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js',
    'WebContent/lib/**/*.js'
  ],
  css: ['WebContent/styles.css', 'WebContent/pikaday.css'],
  // Classes added dynamically at runtime (main.js, Pikaday date picker)
  safelist: {
    standard: [/^is-/, /^pika-/, /^has-/],
    greedy: [/pika/]
  },
  keyframes: true,
  fontFace: true,
  variables: true
};
