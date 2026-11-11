module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: [
    'WebContent/styles.css'
  ],
  output: 'purged-css/',
  // Keep classes toggled dynamically at runtime (see main.js classList usage)
  safelist: ['is-selected']
};
