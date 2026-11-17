/* This file is also loaded as a classic script by the extension worker. */
function youtubeVideoId(raw) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return null;
  const path = url.pathname.replace(/\/$/, "").split("/");
  let id;
  if (["youtu.be", "www.youtu.be"].includes(url.hostname)) {
    if (path.length === 2) id = path[1];
  } else if (["youtube.com", "www.youtube.com", "m.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com"].includes(url.hostname)) {
    if (url.pathname === "/watch") id = url.searchParams.get("v");
    else if (path.length === 3 && ["shorts", "embed", "live"].includes(path[1])) id = path[2];
  }
  return typeof id === "string" && id.length === 11 && !/[^a-zA-Z0-9_-]/.test(id) ? id : null;
}
