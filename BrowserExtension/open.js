const fromMenu = location.hash.length > 0;
if (!fromMenu) document.documentElement.classList.add("popup");
const closeButton = document.getElementById("close");
async function dismiss() {
  if (fromMenu) {
    const tab = await chrome.tabs.getCurrent();
    if (tab) await chrome.tabs.remove(tab.id);
  } else {
    window.close();
  }
}
closeButton.addEventListener("click", dismiss);
document.addEventListener("keydown", event => {
  if (event.key === "Escape") {
    event.preventDefault();
    dismiss();
  }
});

async function showVideoTitle(source) {
  const title = document.getElementById("video-title");
  const endpoint = new URL("https://www.youtube.com/oembed");
  endpoint.searchParams.set("url", source);
  endpoint.searchParams.set("format", "json");
  try {
    const response = await fetch(endpoint, {
      credentials: "omit", referrerPolicy: "no-referrer", signal: AbortSignal.timeout(5000)
    });
    if (response.ok) {
      const metadata = await response.json();
      if (typeof metadata.title === "string" && metadata.title.trim()) {
        title.textContent = metadata.title.trim();
        return;
      }
    }
  } catch {
    // Project opening remains available when YouTube cannot supply a title.
  }
  title.textContent = "Video title unavailable";
}

async function openVideo() {
  let id;
  if (fromMenu) {
    id = youtubeVideoId("https://youtu.be/" + location.hash.slice(1));
  } else {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    id = youtubeVideoId(tab?.url);
  }
  if (!id) {
    document.getElementById("error").textContent = "This link does not point to a YouTube video.";
    closeButton.setAttribute("aria-describedby", "error");
    closeButton.focus();
    return;
  }
  const link = document.getElementById("launch");
  const source = "https://www.youtube.com/watch?v=" + id;
  link.href = "vidistudio://share?kind=youtube&source=" + encodeURIComponent(source);
  document.getElementById("source").textContent = "youtu.be/" + id;
  document.getElementById("details").hidden = false;
  closeButton.textContent = "Cancel";
  link.hidden = false;
  link.focus();
  const thumbnail = document.getElementById("thumbnail");
  thumbnail.addEventListener("load", () => { thumbnail.hidden = false; }, {once: true});
  thumbnail.src = "https://i.ytimg.com/vi/" + id + "/mqdefault.jpg";
  await showVideoTitle(source);
}
openVideo();
