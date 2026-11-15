(() => {
  const $ = (id) => document.getElementById(id);
  const TAGS = ["vegetarian", "vegan", "spicy", "healthy", "comfort"];
  const RECENT_AVOID = 3; // don't re-pick any of the last N dishes if alternatives exist
  const byId = new Map(DISHES.map((d) => [d.id, d]));

  const load = (key, fallback) => {
    try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; }
  };
  const save = (key, value) => {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* storage unavailable */ }
  };

  // Drop ids that no longer exist in the data set.
  let favorites = load("favorites", []).filter((id) => byId.has(id));
  let history = load("history", []).filter((id) => byId.has(id));
  let current = null;

  // ---- build controls ----
  [...new Set(DISHES.map((d) => d.cuisine))].sort().forEach((c) => $("cuisine").add(new Option(c, c)));
  TAGS.forEach((t) => {
    const label = document.createElement("label");
    label.className = "chip";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.value = t;
    label.append(input, " " + t);
    $("tags").append(label);
  });

  const filterControls = () => ({
    cuisine: $("cuisine"), price: $("price"), time: $("time"),
  });

  function readFilters() {
    const c = filterControls();
    return {
      cuisine: c.cuisine.value,
      price: c.price.value,
      time: c.time.value,
      tags: [...$("tags").querySelectorAll("input:checked")].map((i) => i.value),
    };
  }

  function applyFilters(f) {
    const c = filterControls();
    for (const k of ["cuisine", "price", "time"]) {
      if (f[k] != null && [...c[k].options].some((o) => o.value === f[k])) c[k].value = f[k];
    }
    $("tags").querySelectorAll("input").forEach((i) => { i.checked = (f.tags || []).includes(i.value); });
  }

  function matches() {
    const f = readFilters();
    return DISHES.filter((d) =>
      (!f.cuisine || d.cuisine === f.cuisine) &&
      d.price <= +f.price &&
      d.time <= +f.time &&
      f.tags.every((t) => d.tags.includes(t)));
  }

  function onFiltersChanged() {
    save("filters", readFilters());
    const n = matches().length;
    $("count").textContent = `${n} dish${n === 1 ? "" : "es"} match`;
    $("pick").disabled = n === 0;
    $("empty").hidden = n !== 0;
  }

  function pick() {
    const pool = matches();
    if (!pool.length) return;
    // Prefer dishes not picked recently; fall back to anything but the current one.
    const recent = new Set(history.slice(0, RECENT_AVOID));
    let options = pool.filter((d) => !recent.has(d.id));
    if (!options.length) options = pool.length > 1 ? pool.filter((d) => d !== current) : pool;
    current = options[Math.floor(Math.random() * options.length)];
    history = [current.id, ...history.filter((id) => id !== current.id)].slice(0, 5);
    save("history", history);
    render();
  }

  function toggleFavorite(id) {
    favorites = favorites.includes(id) ? favorites.filter((f) => f !== id) : [...favorites, id];
    save("favorites", favorites);
    render();
  }

  function listItem(dish, removable) {
    const li = document.createElement("li");
    li.textContent = `${dish.emoji} ${dish.name}`;
    if (removable) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "icon small";
      btn.textContent = "✕";
      btn.setAttribute("aria-label", `Remove ${dish.name} from favorites`);
      btn.addEventListener("click", () => toggleFavorite(dish.id));
      li.append(btn);
    }
    return li;
  }

  function renderList(el, ids, removable, emptyText) {
    el.replaceChildren(...ids.map((id) => listItem(byId.get(id), removable)));
    if (!ids.length) {
      const li = document.createElement("li");
      li.className = "muted";
      li.textContent = emptyText;
      el.append(li);
    }
  }

  function render() {
    if (current) {
      $("result").hidden = false;
      $("emoji").textContent = current.emoji;
      $("name").textContent = current.name;
      $("meta").textContent =
        `${current.cuisine} · ${"$".repeat(current.price)} · ~${current.time} min` +
        (current.tags.length ? ` · ${current.tags.join(", ")}` : "");
      const fav = favorites.includes(current.id);
      $("fav").textContent = fav ? "★" : "☆";
      $("fav").setAttribute("aria-pressed", String(fav));
      $("fav").setAttribute("aria-label", fav ? "Remove from favorites" : "Save to favorites");
    }
    renderList($("favorites"), favorites, true, "None yet — tap ☆ on a pick.");
    renderList($("history"), history, false, "Nothing yet.");
  }

  // ---- wire up ----
  applyFilters(load("filters", {}));
  document.querySelectorAll("select").forEach((s) => s.addEventListener("change", onFiltersChanged));
  $("tags").addEventListener("change", onFiltersChanged);
  $("reset").addEventListener("click", () => {
    applyFilters({ cuisine: "", price: "3", time: "999", tags: [] });
    onFiltersChanged();
  });
  $("pick").addEventListener("click", pick);
  $("fav").addEventListener("click", () => current && toggleFavorite(current.id));
  document.addEventListener("keydown", (e) => {
    if (e.key === " " && e.target === document.body) { e.preventDefault(); $("pick").click(); }
  });

  onFiltersChanged();
  render();
})();
