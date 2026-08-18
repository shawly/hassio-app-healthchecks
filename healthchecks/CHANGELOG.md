# Changelog

## 1.0.0

Initial release, packaging Healthchecks v4.3.

- Web interface through the Home Assistant sidebar panel (ingress).
- Mapped port 8000 for ping URLs and for reaching the interface directly.
- SQLite by default, optional external PostgreSQL.
- Optional SMTP for alerts, monthly reports and sign-in links.
- Optional inbound SMTP listener for pinging by email.
- Optional auto sign-in for ingress requests.
- Optional TLS on the mapped port.
