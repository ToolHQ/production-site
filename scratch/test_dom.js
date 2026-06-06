const jsdom = require("jsdom");
const { JSDOM } = jsdom;
JSDOM.fromURL("https://reports.dnor.io/", {
  runScripts: "dangerously",
  resources: "usable"
}).then(dom => {
  setTimeout(() => {
    console.log("Navs:", dom.window.document.querySelectorAll("header.dnor-shell").length);
    console.log("Mains:", dom.window.document.querySelectorAll("main").length);
    process.exit(0);
  }, 5000);
});
