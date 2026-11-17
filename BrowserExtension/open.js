const fromMenu = location.hash.length > 0;
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
  link.hidden = false;
  link.focus();
  // A real link remains available when the browser requires a fresh user gesture.
  // Give the browser a chance to paint the action before the external-app prompt.
  requestAnimationFrame(() => requestAnimationFrame(() => link.click()));
}
openVideo();
