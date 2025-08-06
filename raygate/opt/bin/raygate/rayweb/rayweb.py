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
XRAY_ADD_SCRIPT = "/opt/bin/raygate/raygate_add_domain.sh"
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
    <title>VPN Domain Manager</title>
    <style>
        body { font-family: Arial; background-color: #111; color: #eee; text-align:center; }
        .control-line { display: flex; justify-content: center; gap: 10px; margin-bottom: 20px; flex-wrap: wrap; }
        .control-line form { display: inline-block; }
        input[type="text"] { padding: 5px; }
        button { padding: 5px 10px; }
        table { margin: auto; border-collapse: collapse; }
        td { padding: 5px; }
    </style>
</head>
<body>
    {% if not session.get('logged_in') %}
        <h2>Login</h2>
        <form method="POST" action="{{ url_for('login') }}">
            <input type="text" name="username" placeholder="Username"><br><br>
            <input type="password" name="password" placeholder="Password"><br><br>
            <button type="submit">Login</button>
        </form>
    {% else %}
        <h3>Command Output</h3>
        <pre style="text-align:left; margin:auto; width:80%; background-color:#222; padding:10px; border-radius:5px;">{{ output }}</pre>

        <div class="control-line">
            <!-- XRAY Control -->
            <form method="POST" action="{{ url_for('xray_control') }}">
                <button name="action" value="start">Start</button>
                <button name="action" value="stop">Stop</button>
                <button name="action" value="restart">Restart</button>
                <button name="action" value="status">Status</button>
            </form>

            <!-- Add domain -->
            <form method="POST" action="{{ url_for('add_domain') }}">
                <input type="text" name="domain" placeholder="example.com" required>
                <button type="submit">Add</button>
            </form>

            <!-- Check IP -->
            <form method="POST" action="{{ url_for('check_ip') }}">
                <button type="submit">Check External IP</button>
            </form>
        </div>

        <h2>Current Domains in VPN</h2>
        <table>
            {% for domain in domains %}
            <tr>
                <td>{{ domain }}</td>
                <td>
                    <!-- Удалить полностью -->
                    <form method="POST" action="{{ url_for('remove_domain') }}" style="display:inline;">
                        <input type="hidden" name="domain" value="{{ domain }}">
                        <input type="hidden" name="mode" value="full">
                        <button type="submit" style="color:red;">🗑 Полностью</button>
                    </form>
                    <!-- Удалить только из dnsmasq -->
                    <form method="POST" action="{{ url_for('remove_domain') }}" style="display:inline;">
                        <input type="hidden" name="domain" value="{{ domain }}">
                        <input type="hidden" name="mode" value="dns">
                        <button type="submit" style="color:orange;">🚫 Только dnsmasq</button>
                    </form>
                </td>
            </tr>
            {% endfor %}
        </table>

        <h3>Current IPSet</h3>
        <pre style="text-align:left; margin:auto; width:80%; background-color:#222; padding:10px; border-radius:5px;">{{ ipset_list }}</pre>

        <a href="{{ url_for('logout') }}" style="color:#f55;">Logout</a>
    {% endif %}
</body>
</html>
"""

# ==== Ограничение доступа по IP ====
@app.before_request
def limit_remote_addr():
    if request.remote_addr not in ("127.0.0.1", "::1") and not str(ipaddress.ip_address(request.remote_addr)).startswith("192.168."):
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

# ==== Удалить домен ====
def remove_domain_from_ipset(domain, mode="full"):
    try:
        removed_ips = []
        clean = domain.strip().lstrip('.')
        if not re.match(r'^[A-Za-z0-9.-]+$', clean):
            clean = ''

        try:
            with open(DNSMASQ_CONF, "r") as f:
                lines = f.readlines()
        except FileNotFoundError:
            lines = []
        with open(DNSMASQ_CONF, "w") as f:
            for line in lines:
                if not line.startswith(f"ipset=/{domain}/") and not line.startswith(f"ipset=/{clean}/"):
                    f.write(line)
        subprocess.run(["kill", "-HUP", "$(pidof dnsmasq)"], shell=True)

        if mode == "full" and clean:
            try:
                ips = socket.gethostbyname_ex(clean)[2]
                for ip in ips:
                    subprocess.run(["ipset", "del", "vpn_domains", ip], check=False)
                    removed_ips.append(ip)
            except socket.gaierror:
                pass

        subprocess.run(IPSET_SAVE_CMD, stdout=open(IPSET_FILE, "w"))

        if mode == "full" and removed_ips:
            return f"Domain '{domain}' removed from dnsmasq. Removed IPs: {', '.join(removed_ips)}"
        elif mode == "full":
            return f"Domain '{domain}' removed from dnsmasq. No IPs removed from ipset."
        else:
            return f"Domain '{domain}' removed only from dnsmasq."
    except Exception as e:
        return f"Error removing {domain}: {e}"

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

# ==== Добавление домена ====
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

# ==== Удаление домена ====
@app.route("/remove", methods=["POST"])
def remove_domain():
    if not session.get("logged_in"):
        return redirect(url_for("index"))
    domain = request.form.get("domain")
    mode = request.form.get("mode", "full")
    result = remove_domain_from_ipset(domain, mode)
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
