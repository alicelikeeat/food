(() => {
  const $ = (id) => document.getElementById(id);
  const TAGS = ["vegetarian", "vegan", "spicy", "healthy", "comfort"];
  let current = null;
  let history = [];
  let favorites = load("favorites", []);

  function load(key, fallback) {
    try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; }
  }
  function save(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch {}
  }

  // populate filter controls
  [...new Set(DISHES.map((d) => d.cuisine))].sort().forEach((c) => {
    $("cuisine").add(new Option(c, c));
  });
  TAGS.forEach((t) => {
    const label = document.createElement("label");
    label.innerHTML = `<input type="checkbox" value="${t}"> ${t}`;
    $("tags").append(label);
  });

  function matches() {
    const cuisine = $("cuisine").value;
    const price = +$("price").value;
    const time = +$("time").value;
    const tags = [...$("tags").querySelectorAll("input:checked")].map((i) => i.value);
    return DISHES.filter((d) =>
      (!cuisine || d.cuisine === cuisine) &&
      d.price <= price && d.time <= time &&
      tags.every((t) => d.tags.includes(t)));
  }

  function pick() {
    const pool = matches();
    if (!pool.length) {
      current = null;
      $("result").textContent = "Nothing matches — loosen a filter.";
      $("fav").hidden = true;
      return;
    }
    // avoid repeating the current dish when there's an alternative
    const options = pool.length > 1 ? pool.filter((d) => d !== current) : pool;
    current = options[Math.floor(Math.random() * options.length)];
    $("result").textContent = `${current.emoji} ${current.name}`;
    $("fav").hidden = false;
    history = [current.name, ...history.filter((n) => n !== current.name)].slice(0, 5);
    render();
  }

  function render() {
    $("fav").textContent = current && favorites.includes(current.name) ? "★ Saved" : "☆ Save to favorites";
    $("history").innerHTML = history.map((n) => `<li>${n}</li>`).join("");
    $("favorites").innerHTML = favorites.map((n) => `<li>${n}</li>`).join("") || "<li>None yet</li>";
  }

  $("pick").addEventListener("click", pick);
  $("fav").addEventListener("click", () => {
    if (!current) return;
    favorites = favorites.includes(current.name)
      ? favorites.filter((n) => n !== current.name)
      : [...favorites, current.name];
    save("favorites", favorites);
    render();
  });
  render();
})();
