// PurgeCSS configuration used by the Docker build stage to strip unused CSS
// from the application's own stylesheet before packaging the WAR.
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: ['WebContent/styles.css'],
  output: 'purged-css/',
  // Classes toggled/used at runtime or in markup that must never be removed
  safelist: ['bold', 'is-selected']
};
