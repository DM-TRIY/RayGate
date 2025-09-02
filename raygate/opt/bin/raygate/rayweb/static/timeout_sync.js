let ipsetData = [];

function renderIpSet() {
  const table = document.getElementById("ipset-table");
  if (!table) return;
  table.innerHTML = "<tr><th>IP</th><th>Timeout</th></tr>";
  ipsetData.forEach(e => {
    table.innerHTML += `<tr><td>${e.ip}</td><td>${e.timeout}</td></tr>`;
  });
}

// каждую секунду уменьшаем timeout
setInterval(() => {
  ipsetData.forEach(e => { if (e.timeout > 0) e.timeout--; });
  renderIpSet();
}, 1000);

// каждые 10 секунд обновляем с сервера
setInterval(async () => {
  const resp = await fetch("/ipset_json");
  if (resp.ok) {
    ipsetData = await resp.json();
    renderIpSet();
  }
}, 10000);

// начальная загрузка
(async () => {
  const resp = await fetch("/ipset_json");
  if (resp.ok) {
    ipsetData = await resp.json();
    renderIpSet();
  }
})();
