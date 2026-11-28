"use strict";

const repository = "https://github.com/acepleiades/HZoi-Gameplay";
const releaseApi = "https://api.github.com/repos/acepleiades/HZoi-Gameplay/releases/latest";
const releaseTag = document.getElementById("release-tag");
const assetInfo = document.getElementById("asset-info");
const download = document.getElementById("download-link");
const label = document.getElementById("download-label");
const status = document.getElementById("release-status");
const releaseLink = document.getElementById("release-link");
const notes = document.getElementById("release-notes");
const releaseLanguage = document.getElementById("release-language");
let assetSize;

function showAssetSize() {
  if (assetSize === undefined) return;
  assetInfo.textContent = new Intl.NumberFormat(document.documentElement.lang, {
    style: "unit", unit: "megabyte", unitDisplay: "short", maximumFractionDigits: 1
  }).format(assetSize / 1000000);
}

document.addEventListener("site-language-change", showAssetSize);

// Render only the Markdown used in release notes, never remote HTML.
function addInline(element, text) {
  const inline = /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)|(\x60[^\x60]+\x60)|\*\*([^*]+)\*\*/g;
  let offset = 0;
  for (const match of text.matchAll(inline)) {
    element.append(text.slice(offset, match.index));
    const part = document.createElement(match[1] ? "a" : match[3] ? "code" : "strong");
    if (match[1]) part.href = match[2];
    part.textContent = match[1] || (match[3] && match[3].slice(1, -1)) || match[4];
    element.append(part);
    offset = match.index + match[0].length;
  }
  element.append(text.slice(offset));
}

function showNotes(body) {
  if (!body?.trim()) return;
  notes.lang = "en";
  releaseLanguage.hidden = false;
  notes.replaceChildren();
  let block;
  for (const line of body.trim().split(/\r?\n/)) {
    const heading = line.match(/^#{1,6}\s+(.+)/);
    const bullet = line.match(/^\s*[-*+]\s+(.+)/);
    const numbered = line.match(/^\s*\d+\.\s+(.+)/);
    if (!line.trim()) {
      block = null;
    } else if (bullet || numbered) {
      const type = bullet ? "ul" : "ol";
      if (block?.localName !== type) {
        block = document.createElement(type);
        notes.append(block);
      }
      const item = document.createElement("li");
      addInline(item, (bullet || numbered)[1]);
      block.append(item);
    } else if (heading) {
      const title = document.createElement("h3");
      addInline(title, heading[1]);
      notes.append(title);
      block = null;
    } else {
      if (block?.localName !== "p") {
        block = document.createElement("p");
        notes.append(block);
      } else {
        block.append(" ");
      }
      addInline(block, line);
    }
  }
}

async function loadRelease() {
  try {
    const response = await fetch(releaseApi, {
      headers: { Accept: "application/vnd.github+json" },
      signal: AbortSignal.timeout(8000)
    });
    if (!response.ok) throw new Error("Release request failed");
    const release = await response.json();
    if (!release.tag_name || release.draft || release.prerelease) throw new Error("No stable release data");

    const tag = encodeURIComponent(release.tag_name);
    const name = "HZoiGameplay-" + release.tag_name.replace(/^v/i, "") + ".zip";
    const asset = release.assets?.find(item => item.state === "uploaded" && item.name === name &&
      item.browser_download_url === repository + "/releases/download/" + tag + "/" + encodeURIComponent(name));
    releaseTag.textContent = release.tag_name + " · ";
    releaseLink.href = repository + "/releases/tag/" + tag;
    download.href = asset ? asset.browser_download_url : releaseLink.href;
    if (asset) {
      setSiteMessage(label, "downloadZip", "Download HZoi Gameplay ZIP");
    } else {
      setSiteMessage(label, "viewRelease", "View release on GitHub");
    }
    if (asset && Number.isFinite(asset.size)) {
      assetSize = asset.size;
      showAssetSize();
    }
    showNotes(release.body);
  } catch {
    setSiteMessage(status, "releaseUnavailable", "Live release details are unavailable. Open GitHub to get the latest ZIP.");
  }
}

loadRelease();
