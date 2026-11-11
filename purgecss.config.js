// PurgeCSS configuration used in the Docker build stage to strip unused CSS
module.exports = {
  content: [
    "WebContent/**/*.html",
    "WebContent/**/*.jsp",
    "WebContent/main.js"
  ],
  css: ["WebContent/styles.css"],
  output: "build/purged-css/",
  // Classes toggled dynamically from JavaScript (classList.add/remove)
  safelist: {
    standard: [/^is-/]
  }
};
