importScripts("youtube.js");

const openMenu = "open-in-vidistudio";
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({id: openMenu, title: "Describe with Vidi Studio", contexts: ["page", "link", "video"]});
});
chrome.contextMenus.onClicked.addListener((info) => {
  if (info.menuItemId !== openMenu) return;
  const id = youtubeVideoId(info.linkUrl ?? info.pageUrl);
  // Only the validated video ID enters the extension tab's history.
  chrome.tabs.create({url: chrome.runtime.getURL("open.html") + "#" + (id || "invalid")});
});
