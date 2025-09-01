from flask import Flask, request, render_template, redirect, url_for, session, abort
from collections import defaultdict
import subprocess
import bcrypt
import ipaddress
import re

# ==== Настройки ====
USERNAME = "__USERNAME__"
PASSWORD_HASH = "__PASSHASH__"
SECRET_KEY = "__SECRET__"
XRAY_SERVICE = "/opt/etc/init.d/S99raygate"
XRAY_ADD_SCRIPT = "/opt/bin/raygate/raygate_add.sh"
XRAY_REM_SCRIPT = "/opt/bin/raygate/raygate_rem.sh"
META_FILE = "/opt/etc/vpn_domains.meta"
WAN_INTERFACE = "eth3"

app = Flask(__name__, static_folder='static')
app.secret_key = SECRET_KEY


# ==== Ограничение доступа по IP ====
@app.before_request
def limit_remote_addr():
    ip = ipaddress.ip_address(request.remote_addr)
    if not (ip.is_loopback or ip.is_private):
        abort(403)


# ==== Получить список доменов из META ====
def get_domains():
    groups = defaultdict(list)
    try:
        with open(META_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if not line or "," not in line:
                    continue
                domain, tag = line.split(",", 1)
                groups[tag].append(domain)
    except FileNotFoundError:
        pass
    return dict(sorted(groups.items()))  # сортировка по тегу


# ==== Получить список IP из ipset ====
def get_ipset_list():
    try:
        return subprocess.check_output(
            ["ipset", "list", "vpn_domains"], stderr=subprocess.STDOUT, text=True
        )
    except subprocess.CalledProcessError as e:
        return e.output
    except FileNotFoundError:
        return ""


def ip_to_flag(ip):
    try:
        country_code = subprocess.check_output(
            ["curl", "-s", f"https://ipapi.co/{ip}/country/"],
            text=True, timeout=2
        ).strip()
        if len(country_code) == 2:
            return chr(ord(country_code[0].upper()) + 127397) + chr(ord(country_code[1].upper()) + 127397)
    except Exception:
        pass
    return ""


# ==== Главная ====
@app.route("/", methods=["GET"])
def index():
    if not session.get("logged_in"):
        return render_template("index.html")
    return render_template(
        "index.html",
        output="",
        ipset_list=get_ipset_list(),
        grouped_domains=get_domains(),
    )


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
    domain = request.form.get("domain", "").strip()
    domain_regex = re.compile(r"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$")
    if not domain_regex.fullmatch(domain):
        result = "Invalid domain"
    else:
        try:
            result = subprocess.check_output(
                [XRAY_ADD_SCRIPT, domain], stderr=subprocess.STDOUT, text=True
            )
        except subprocess.CalledProcessError as e:
            result = e.output
    return render_template(
        "index.html",
        output=result,
        ipset_list=get_ipset_list(),
        grouped_domains=get_domains(),
    )


# ==== Удаление домена ====
@app.route("/remove", methods=["POST"])
def remove_domain():
    if not session.get("logged_in"):
        return redirect(url_for("index"))
    domain = request.form.get("domain", "").strip()
    if not domain:
        result = "Domain is required"
    else:
        try:
            result = subprocess.check_output(
                [XRAY_REM_SCRIPT, domain], stderr=subprocess.STDOUT, text=True
            )
        except subprocess.CalledProcessError as e:
            result = e.output
    return render_template(
        "index.html",
        output=result,
        ipset_list=get_ipset_list(),
        grouped_domains=get_domains(),
    )


# ==== Удаление IP из ipset ====
@app.route("/remove_ip", methods=["POST"])
def remove_ip():
    if not session.get("logged_in"):
        return redirect(url_for("index"))
    ip = request.form.get("ip", "").strip()
    if not ip:
        result = "IP is required"
    else:
        try:
            subprocess.check_call(["ipset", "del", "vpn_domains", ip])
            result = f"IP {ip} removed from vpn_domains"
        except subprocess.CalledProcessError:
            result = f"Failed to remove IP {ip} (not found?)"
    return render_template(
        "index.html",
        output=result,
        ipset_list=get_ipset_list(),
        grouped_domains=get_domains(),
    )


# ==== Удаление группы доменов ====
@app.route("/remove_group", methods=["POST"])
def remove_group():
    if not session.get("logged_in"):
        return redirect(url_for("index"))
    tag = request.form.get("tag", "").strip()
    if not tag:
        result = "Tag is required"
    else:
        try:
            result = subprocess.check_output(
                [XRAY_REM_SCRIPT, f"group:{tag}"], stderr=subprocess.STDOUT, text=True
            )
        except subprocess.CalledProcessError as e:
            result = e.output
    return render_template(
        "index.html",
        output=result,
        ipset_list=get_ipset_list(),
        grouped_domains=get_domains(),
    )


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

    vpn_flag = ip_to_flag(vpn_ip) if vpn_ip != "Error" else ""
    wan_flag = ip_to_flag(wan_ip) if wan_ip != "Error" else ""

    result = f"VPN IP: {vpn_ip} {vpn_flag}\nWAN IP: {wan_ip} {wan_flag}"
    return render_template(
        "index.html",
        output=result,
        ipset_list=get_ipset_list(),
        grouped_domains=get_domains(),
    )


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
    return render_template(
        "index.html",
        output=result,
        ipset_list=get_ipset_list(),
        grouped_domains=get_domains(),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9090)
