// PurgeCSS configuration - strips unused CSS rules during the container image build
module.exports = {
  content: [
    'WebContent/**/*.html',
    'WebContent/**/*.jsp',
    'WebContent/main.js'
  ],
  css: [
    'WebContent/styles.css'
  ],
  output: 'purged/',
  // Keep classes applied dynamically or used in inline markup
  safelist: {
    standard: ['bold', /^h[1-5]/],
    greedy: [/pika/]
  },
  fontFace: true,
  keyframes: true,
  variables: true
};
