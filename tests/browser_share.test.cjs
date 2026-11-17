const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");
const fixtures = require("./browser_share_urls.json");
const read = name => fs.readFileSync(path.join(__dirname, "../BrowserExtension", name), "utf8");
const page = "https://youtube.com/watch?v=dQw4w9WgXcQ";
const other = "https://example.org";
test("all shared URL fixtures", () => {
  const validate = vm.runInNewContext(read("youtube.js") + "\nyoutubeVideoId", {URL});
  for (const [url, id] of fixtures) assert.equal(validate(url), id, url);
});
test("context action always prefers the clicked link, even when it is invalid", () => {
  let clicked;
  let created;
  const chrome = {
    runtime: {onInstalled: {addListener() {}}, getURL: name => name},
    contextMenus: {onClicked: {addListener: fn => clicked = fn}},
    tabs: {create: ({url}) => created = url}
  };
  vm.runInNewContext(read("youtube.js") + read("background.js"), {chrome, URL, importScripts() {}});
  for (const [pageUrl, linkUrl, result] of [[other, page, "dQw4w9WgXcQ"], [page, other, "invalid"],
    [page, undefined, "dQw4w9WgXcQ"], [other, undefined, "invalid"]]) {
    clicked({menuItemId: "open-in-vidistudio", pageUrl, linkUrl});
    assert.equal(created, "open.html#" + result);
  }
});

test("invalid toolbar input shows the exact accessible error without a handoff", async () => {
  for (const url of [other, "file:///tmp/video.mp4", undefined]) {
    const close = {addEventListener() {}, setAttribute(name, value) {this[name] = value;}, focus() {this.focused = true;}};
    const error = {};
    const views = {error, close};
    const document = {documentElement: {classList: {add() {}}}, addEventListener() {}, getElementById(id) {
      assert.ok(id in views, "an invalid target must never access the launch link");
      return views[id];
    }};
    await vm.runInNewContext(read("youtube.js") + read("open.js"), {
      URL, document, location: {hash: ""}, chrome: {tabs: {query: async () => [{url}]}}
    });
    assert.equal(error.textContent, "This link does not point to a YouTube video.");
    assert.equal(close["aria-describedby"], "error");
    assert.ok(close.focused);
  }
});

test("a desktop-only release keeps the running extension; a changed extension version reloads it", async () => {
  const loaded = {name: "Describe with Vidi Studio", version: "1.0.346", background: {service_worker: "local-worker.js"}};
  let version = loaded.version;
  let reloads = 0;
  const event = {addListener() {}};
  const context = {
    importScripts() {},
    chrome: {
      alarms: {onAlarm: event},
      runtime: {onInstalled: event, onStartup: event, getManifest: () => loaded,
        getURL: name => name, reload: () => reloads++}
    },
    fetch: async () => ({ok: true, json: async () => ({...loaded, version})})
  };
  const check = vm.runInNewContext(read("local-worker.js") + "\ncheckInstalledVersion", context);
  await check();
  assert.equal(reloads, 0);
  version = "1.0.347";
  await check();
  assert.equal(reloads, 1);
});

test("valid video waits for the user's choice and Cancel dismisses the originating view", async () => {
  for (const hash of ["", "#dQw4w9WgXcQ"]) {
    let cancel, removed, windowClosed = false, focused = false;
    const elements = {
      details: {hidden: true}, source: {}, "video-title": {},
      thumbnail: {hidden: true, addEventListener(name, handler) {if (name === "load") this.loaded = handler;}},
      launch: {hidden: true, focus() {focused = true;}},
      close: {addEventListener(event, handler) {if (event === "click") cancel = handler;}}
    };
    const document = {documentElement: {classList: {add() {}}}, addEventListener() {}, getElementById: id => elements[id]};
    const tabs = {query: async () => [{url: page}], getCurrent: async () => ({id: 42}), remove: async id => {removed = id;}};
    await vm.runInNewContext(read("youtube.js") + read("open.js"), {
      URL, document, AbortSignal, fetch: async (url, options) => {
        assert.equal(url.origin + url.pathname, "https://www.youtube.com/oembed");
        assert.equal(url.searchParams.get("url"), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
        assert.equal(options.credentials, "omit");
        assert.equal(options.referrerPolicy, "no-referrer");
        if (hash) throw new Error("Offline");
        return {ok: true, json: async () => ({title: "A <video> title"})};
      }, location: {hash}, chrome: {tabs}, window: {close() {windowClosed = true;}}
    });
    assert.equal(elements["video-title"].textContent, hash ? "Video title unavailable" : "A <video> title");
    assert.equal(elements.thumbnail.src, "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg");
    assert.ok(elements.thumbnail.hidden);
    elements.thumbnail.loaded();
    assert.equal(elements.thumbnail.hidden, false);
    assert.equal(elements.source.textContent, "youtu.be/dQw4w9WgXcQ");
    assert.equal(elements.launch.href, "vidistudio://share?kind=youtube&source=" + encodeURIComponent("https://www.youtube.com/watch?v=dQw4w9WgXcQ"));
    assert.equal(elements.launch.hidden, false);
    assert.equal(elements.details.hidden, false);
    assert.equal(elements.close.textContent, "Cancel");
    assert.ok(focused);
    await cancel();
    assert.equal(windowClosed, !hash);
    assert.equal(removed, hash ? 42 : undefined);
  }
});
