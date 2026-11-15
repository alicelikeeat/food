document.getElementById("pick").addEventListener("click", () => {
  const dish = DISHES[Math.floor(Math.random() * DISHES.length)];
  document.getElementById("result").textContent = dish;
});
