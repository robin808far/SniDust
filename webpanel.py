import os, sys, base4, subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs

USERNAME = os.getenv("PANEL_USER", "admin")
PASSWORD = os.getenv("PANEL_PASS", "admin123")
PORT = int(os.getenv("PANEL_PORT", "8085"))
ACL_FILE = "/etc/snidust/clients.txt"
DOMAINS_DIR = "/etc/snidust/domains.d"

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SniDust Control Panel</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 2rem; }}
        .container {{ max-width: 900px; margin: auto; background: #1e293b; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.5); }}
        h1 {{ margin-top: 0; color: #38bdf8; font-size: 1.5rem; }}
        label {{ font-weight: 600; display: block; margin: 1.2rem 0 0.4rem; color: #94a3b8; }}
        textarea {{ width: 100%; box-sizing: border-box; background: #0f172a; border: 1px solid #334155; color: #f8fafc; padding: 0.75rem; border-radius: 6px; font-family: monospace; height: 160px; resize: vertical; }}
        button {{ background: #0284c7; color: #fff; border: none; padding: 0.75rem 1.5rem; border-radius: 6px; cursor: pointer; font-weight: 600; margin-top: 1.2rem; transition: background 0.2s; }}
        button:hover {{ background: #0369a1; }}
        .success {{ background: #14532d; color: #86efac; padding: 0.75rem; border-radius: 6px; margin-bottom: 1rem; }}
        .hint {{ font-size: 0.8rem; color: #64748b; margin-top: 0.2rem; }}
    </style>
</head>
<body>
<div class="container">
    <h1>SniDust Dashboard</h1>
    {status_msg}
    <form method="POST" action="/save">
        <label>Allowed Clients & IPs / DynDNS:</label>
        <div class="hint">Enter one IP, Subnet (e.g. 1.2.3.4 or 1.2.3.0/24), or DynDNS domain per line.</div>
        <textarea name="clients">{clients}</textarea>

        <label>Custom Domains:</label>
        <div class="hint">Enter domain names per line (e.g. example.com or .example.com). Leading dots are handled automatically.</div>
        <textarea name="domains">{domains}</textarea>

        <button type="submit">Save & Apply Changes</button>
    </form>
</div>
</body>
</html>
"""

def reload_services():
    subprocess.run(["/bin/bash", "/generateACL.sh"], check=False)
    subprocess.run(["nginx", "-s", "reload"], check=False)
    subprocess.run(["/usr/bin/dog", "@127.0.0.1:5300", "reload.acl.snidust.local"], check=False)
    subprocess.run(["/usr/bin/dog", "@127.0.0.1:5300", "reload.domainlist.snidust.local"], check=False)

class Handler(BaseHTTPRequestHandler):
    def authenticate(self):
        auth_header = self.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Basic '):
            return False
        import base64
        token = auth_header.split(' ', 1)[1].strip()
        try:
            creds = base64.b64decode(token).decode('utf-8').split(':', 1)
            return creds[0] == USERNAME and creds[1] == PASSWORD
        except Exception:
            return False

    def request_auth(self):
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="SniDust Panel"')
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"Authentication required")

    def do_GET(self):
        if not self.authenticate():
            self.request_auth()
            return
        
        clients = ""
        if os.path.exists(ACL_FILE):
            with open(ACL_FILE, "r") as f:
                clients = f.read()

        custom_domains_path = os.path.join(DOMAINS_DIR, "custom.lst")
        domains = ""
        if os.path.exists(custom_domains_path):
            with open(custom_domains_path, "r") as f:
                domains = f.read()

        self.send_response(200)
        self.send_header("Content-type", "text/html; charset=utf-8")
        self.end_headers()
        html = HTML_TEMPLATE.format(status_msg="", clients=clients, domains=domains)
        self.wfile.write(html.encode("utf-8"))

    def do_POST(self):
        if not self.authenticate():
            self.request_auth()
            return

        if self.path == "/save":
            content_length = int(self.headers.get('Content-Length', 0))
            post_body = self.rfile.read(content_length).decode('utf-8')
            fields = parse_qs(post_body)

            clients = fields.get("clients", [""])[0].replace("\r\n", "\n")
            domains_raw = fields.get("domains", [""])[0].replace("\r\n", "\n")

            with open(ACL_FILE, "w") as f:
                f.write(clients)

            formatted_domains = []
            for d in domains_raw.splitlines():
                d = d.strip()
                if d and not d.startswith("#"):
                    if not d.startswith("."):
                        d = "." + d
                    formatted_domains.append(d)

            custom_domains_path = os.path.join(DOMAINS_DIR, "custom.lst")
            with open(custom_domains_path, "w") as f:
                f.write("\n".join(formatted_domains) + "\n")

            reload_services()

            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            success_box = '<div class="success">Settings saved and reloaded in real-time!</div>'
            html = HTML_TEMPLATE.format(status_msg=success_box, clients=clients, domains="\n".join(formatted_domains))
            self.wfile.write(html.encode("utf-8"))

if __name__ == "__main__":
    os.makedirs(DOMAINS_DIR, exist_ok=True)
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever()
