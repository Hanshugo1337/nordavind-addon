let currentSort = { key: "baseScore", asc: false };

// ---- Tab switching ----
document.querySelectorAll(".tab").forEach(tab => {
  tab.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    tab.classList.add("active");
    const target = tab.dataset.tab;
    document.querySelectorAll("[id^='tab-']").forEach(el => el.style.display = "none");
    document.getElementById("tab-" + target).style.display = "";
    if (target === "trades") loadTrades();
    if (target === "loot") loadLoot();
    if (target === "sync") loadSync();
  });
});

// ---- Sorting ----
document.querySelectorAll("th[data-sort]").forEach(th => {
  th.addEventListener("click", () => {
    const key = th.dataset.sort;
    if (currentSort.key === key) currentSort.asc = !currentSort.asc;
    else { currentSort.key = key; currentSort.asc = key === "playerName"; }
    renderPlayers(window._playersData);
  });
});

// ---- Players ----
async function loadPlayers() {
  const res = await fetch("/api/scores");
  const data = await res.json();
  const players = Object.entries(data.players || {}).map(([name, p]) => ({ playerName: name, ...p }));
  window._playersData = players;
  renderPlayers(players);
}

function renderPlayers(players) {
  const sorted = [...players].sort((a, b) => {
    const va = a[currentSort.key], vb = b[currentSort.key];
    if (typeof va === "string") return currentSort.asc ? va.localeCompare(vb) : vb.localeCompare(va);
    return currentSort.asc ? va - vb : vb - va;
  });

  const tbody = document.getElementById("players-body");
  tbody.innerHTML = sorted.map(p => `
    <tr>
      <td>${p.playerName}</td>
      <td class="score">${p.baseScore.toFixed(1)}</td>
      <td>${p.attendance}%</td>
      <td>${p.wclParse.toFixed(1)}</td>
      <td>${p.mplusEffort}</td>
      <td><span class="rank-${p.rank}">${p.rank}</span></td>
      <td>${p.lootThisWeek}</td>
      <td>${p.lootTotal}</td>
      <td>${p.deathPenalty > 0 ? "-" + p.deathPenalty.toFixed(1) : "\u2014"}</td>
    </tr>
  `).join("");
}

// ---- Trades ----
async function loadTrades() {
  const res = await fetch("/api/trades");
  const trades = await res.json();
  const el = document.getElementById("trades-list");
  if (trades.length === 0) { el.innerHTML = '<div class="empty">Ingen pending trades</div>'; return; }
  el.innerHTML = trades.map(t => `
    <div class="trade-row">
      <span class="loot-item">${t.item || "?"}</span>
      <span>\u2192 ${t.awardedTo || "?"}</span>
      <span style="color:#888">${t.category || ""}</span>
    </div>
  `).join("");
}

// ---- Loot Log ----
async function loadLoot() {
  const res = await fetch("/api/loot");
  const loot = await res.json();
  const tbody = document.getElementById("loot-body");
  if (loot.length === 0) { tbody.innerHTML = '<tr><td colspan="5" class="empty">Ingen loot registrert</td></tr>'; return; }
  tbody.innerHTML = loot.map(l => {
    const time = l.timestamp ? new Date(l.timestamp * 1000).toLocaleString("nb-NO") : "\u2014";
    return `
      <tr>
        <td class="loot-item">${l.item || "?"}</td>
        <td>${l.awardedTo || "?"}</td>
        <td>${l.boss || "?"}</td>
        <td>${l.category || "?"}</td>
        <td style="color:#888">${time}</td>
      </tr>
    `;
  }).join("");
}

// ---- Sync ----
async function loadSync() {
  const res = await fetch("/api/status");
  const s = await res.json();
  document.getElementById("sync-time").textContent = s.lastSync ? new Date(s.lastSync).toLocaleString("nb-NO") : "Aldri";
  document.getElementById("sync-players").textContent = s.playerCount;
  document.getElementById("sync-wow").textContent = s.wowPath || "\u2014";
  document.getElementById("sync-url").textContent = s.webUrl || "\u2014";
}

async function manualSync() {
  const btn = document.querySelector(".btn");
  btn.textContent = "Synkroniserer...";
  btn.disabled = true;
  await fetch("/api/sync", { method: "POST" });
  await loadPlayers();
  await loadSync();
  btn.textContent = "Synkroniser n\u00e5";
  btn.disabled = false;
}

async function fullRecalc() {
  const btns = document.querySelectorAll(".btn");
  btns.forEach(b => b.disabled = true);
  btns[1].textContent = "Beregner scores...";
  const res = await fetch("/api/recalc?mode=full", { method: "POST" });
  const data = await res.json();
  if (data.ok) {
    btns[1].textContent = "Ferdig! (" + (data.count || 0) + " spillere)";
  } else {
    btns[1].textContent = "Feilet: " + (data.error || "ukjent");
  }
  await loadPlayers();
  await loadSync();
  setTimeout(() => {
    btns[1].textContent = "Full beregning (raid night)";
    btns.forEach(b => b.disabled = false);
  }, 3000);
}

// ---- Status bar ----
async function updateStatus() {
  try {
    const res = await fetch("/api/status");
    const s = await res.json();
    document.getElementById("status-dot").className = "dot " + (s.connected ? "green" : "red");
    document.getElementById("status-text").textContent = s.connected
      ? `${s.playerCount} spillere \u00b7 sist sync ${s.lastSync ? new Date(s.lastSync).toLocaleTimeString("nb-NO") : "aldri"}`
      : (s.lastError || "Ikke tilkoblet");
  } catch {
    document.getElementById("status-dot").className = "dot red";
    document.getElementById("status-text").textContent = "Feil";
  }
}

// ---- Init ----
loadPlayers();
updateStatus();
setInterval(updateStatus, 10000);
setInterval(loadPlayers, 60000);
