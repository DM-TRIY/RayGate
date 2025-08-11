from flask import Flask, request, render_template_string, redirect, url_for, session, abort
import subprocess
import bcrypt
import ipaddress
import socket
import re

# ==== Настройки ====
USERNAME = "__USERNAME__"
PASSWORD_HASH = "__PASSHASH__"
SECRET_KEY = "__SECRET__"
XRAY_SERVICE = "/opt/etc/init.d/S99raygate"
XRAY_ADD_SCRIPT = "/opt/bin/raygate/raygate_add.sh"
XRAY_REM_SCRIPT = "/opt/bin/raygate/raygate_rem.sh"
DNSMASQ_CONF = "/opt/etc/dnsmasq.d/90-vpn-domains.conf"
IPSET_LIST_CMD = ["ipset", "list", "vpn_domains"]
IPSET_SAVE_CMD = ["ipset", "save", "vpn_domains"]
IPSET_FILE = "/opt/etc/vpn_domains.ipset"
WAN_INTERFACE = "eth3"

app = Flask(__name__, static_folder='static')
app.secret_key = SECRET_KEY

# ==== HTML шаблон ====
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>RayGate VPN Manager</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, sans-serif;
            background-color: #0d1117;
            color: #e6edf3;
            margin: 0;
            padding: 0;
            text-align: center;
        }
        h2, h3 {
            color: #58a6ff;
        }
        a {
            color: #f55;
            text-decoration: none;
        }
        .container {
            padding: 20px;
        }
        .control-line {
            display: flex;
            justify-content: center;
            gap: 10px;
            margin-bottom: 25px;
            flex-wrap: wrap;
        }
        form {
            display: inline-block;
            margin: 0;
        }
        input[type="text"], input[type="password"] {
            padding: 6px 10px;
            border: 1px solid #30363d;
            border-radius: 5px;
            background-color: #161b22;
            color: #e6edf3;
        }
        button {
            padding: 6px 12px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            background-color: #21262d;
            color: #e6edf3;
            transition: background 0.2s ease;
        }
        button:hover {
            background-color: #30363d;
        }
        .btn-red {
            background-color: #da3633;
        }
        .btn-red:hover {
            background-color: #f85149;
        }
        .btn-orange {
            background-color: #d29922;
        }
        .btn-orange:hover {
            background-color: #e3b341;
        }
        table {
            margin: auto;
            border-collapse: collapse;
            width: 80%;
            background-color: #161b22;
            border-radius: 6px;
            overflow: hidden;
        }
        td {
            padding: 8px;
            border-bottom: 1px solid #30363d;
        }
        tr:hover {
            background-color: #21262d;
        }
        pre {
            text-align: left;
            margin: auto;
            width: 80%;
            background-color: #161b22;
            padding: 12px;
            border-radius: 6px;
            overflow-x: auto;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
    {% if not session.get('logged_in') %}
        <h2>🔑 Login</h2>
        <form method="POST" action="{{ url_for('login') }}">
            <input type="text" name="username" placeholder="Username"><br><br>
            <input type="password" name="password" placeholder="Password"><br><br>
            <button type="submit">Login</button>
        </form>
    {% else %}
        <h3>🖥 Command Output</h3>
        <pre>{{ output }}</pre>

        <div class="control-line">
            <!-- XRAY Control -->
            <form method="POST" action="{{ url_for('xray_control') }}">
                <button name="action" value="start">▶ Start</button>
                <button name="action" value="stop">⏹ Stop</button>
                <button name="action" value="restart">🔄 Restart</button>
                <button name="action" value="status">ℹ Status</button>
            </form>

            <!-- Add domain -->
            <form method="POST" action="{{ url_for('add_domain') }}">
                <input type="text" name="domain" placeholder="example.com" required>
                <button type="submit">➕ Add</button>
            </form>

            <!-- Check IP -->
            <form method="POST" action="{{ url_for('check_ip') }}">
                <button type="submit">🌐 Check External IP's</button>
            </form>
        </div>

        <h2>📜 Current Domains in VPN</h2>
        <table>
            {% for domain in domains %}
            <tr>
                <td>{{ domain }}</td>
                <td>
                    <form method="POST" action="{{ url_for('remove_domain') }}" style="display:inline;">
                        <input type="hidden" name="domain" value="{{ domain }}">
                        <input type="hidden" name="mode" value="full">
                        <button type="submit" class="btn-red">🗑 Full Remove</button>
                    </form>
                    <form method="POST" action="{{ url_for('remove_domain') }}" style="display:inline;">
                        <input type="hidden" name="domain" value="{{ domain }}">
                        <input type="hidden" name="mode" value="dns">
                        <button type="submit" class="btn-orange">🚫 Remove</button>
                    </form>
                </td>
            </tr>
            {% endfor %}
        </table>

        <h3>📦 Current IPSet</h3>
        <pre>{{ ipset_list }}</pre>

        <br>
        <a href="{{ url_for('logout') }}">🚪 Logout</a>
    {% endif %}
    </div>
</body>
</html>
"""

# ==== Ограничение доступа по IP ====
@app.before_request
def limit_remote_addr():
    ip = ipaddress.ip_address(request.remote_addr)
    if not (ip.is_loopback or ip.is_private):
        abort(403)

# ==== Получить список доменов из dnsmasq ====
def get_domains():
    try:
        with open(DNSMASQ_CONF, "r") as f:
            lines = f.readlines()
        domains = set()
        for line in lines:
            if line.startswith("ipset=/"):
                dom = line.split("/")[1]
                domains.add(dom)
        return sorted(domains)
    except FileNotFoundError:
        return []

# ==== Получить список IP из ipset ====
def get_ipset_list():
    try:
        return subprocess.check_output(IPSET_LIST_CMD, stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        return e.output

# ==== Главная ====
@app.route("/", methods=["GET"])
def index():
    if not session.get("logged_in"):
        return render_template_string(HTML_TEMPLATE)
    return render_template_string(HTML_TEMPLATE, output="", ipset_list=get_ipset_list(), domains=get_domains())

# ==== Логин ====
@app.route("/login", methods=["POST"])
def login():
    username = request.form.get("username")
    password = request.form.get("password")
    if username == USERNAME and bcrypt.checkpw(password.encode(), PASSWORD_HASH.encode()):
        session["logged_in"] = True
    return redirect(url_for("index"))

# ==== Логаут ====
@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))

@app.route("/add", methods=["POST"])
def add_domain():
    if not session.get("logged_in"):
        return redirect(url_for("index"))
    domain = request.form.get("domain")
    try:
        result = subprocess.check_output([XRAY_ADD_SCRIPT, domain], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        result = e.output
    return render_template_string(HTML_TEMPLATE, output=result, ipset_list=get_ipset_list(), domains=get_domains())

@app.route("/remove", methods=["POST"])
def remove_domain():
    if not session.get("logged_in"):
        return redirect(url_for("index"))
    domain = request.form.get("domain")
    mode = request.form.get("mode", "full")
    try:
        result = subprocess.check_output([XRAY_REM_SCRIPT, domain, mode], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        result = e.output
    return render_template_string(HTML_TEMPLATE, output=result, ipset_list=get_ipset_list(), domains=get_domains())

# ==== Проверка IP ====
@app.route("/check_ip", methods=["POST"])
def check_ip():
    if not session.get("logged_in"):
        return redirect(url_for("index"))
    try:
        vpn_ip = subprocess.check_output(
            ["/opt/bin/curl", "-s", "--socks5", "127.0.0.1:10808", "https://api.ipify.org"],
            text=True
        ).strip()
    except subprocess.CalledProcessError:
        vpn_ip = "Error"
    try:
        wan_ip = subprocess.check_output(
            ["curl", "-s", "--interface", WAN_INTERFACE, "https://api.ipify.org"],
            text=True
        ).strip()
    except subprocess.CalledProcessError:
        wan_ip = "Error"
    result = f"VPN IP: {vpn_ip}\nWAN IP: {wan_ip}"
    return render_template_string(HTML_TEMPLATE, output=result, ipset_list=get_ipset_list(), domains=get_domains())

# ==== Управление XRAY ====
@app.route("/xray", methods=["POST"])
def xray_control():
    if not session.get("logged_in"):
        return redirect(url_for("index"))
    action = request.form.get("action")
    if action not in ["start", "stop", "restart", "status"]:
        return redirect(url_for("index"))
    try:
        result = subprocess.check_output([XRAY_SERVICE, action], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        result = e.output
    return render_template_string(HTML_TEMPLATE, output=result, ipset_list=get_ipset_list(), domains=get_domains())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9090)
