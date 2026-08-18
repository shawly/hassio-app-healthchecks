# Changelog

## 1.0.2

- Fix status badge URLs, e-mail links and OAuth redirect URIs generated from
  the ingress interface. They carried the `/api/hassio_ingress/<token>` prefix
  on top of the mapped port's address, which is not a URL that resolves
  anywhere, and put the ingress token in anything a badge was pasted into.

## 1.0.1

- Fix the ingress panel returning an nginx 404. Home Assistant removes the
  `/api/hassio_ingress/<token>` prefix before it forwards a request, so the
  ingress server block now serves the app at the root instead of at that
  prefix. The mock Supervisor in the test suite strips the prefix too, which
  it did not before, and that is why the tests passed on a broken build.

## 1.0.0

Initial release, packaging Healthchecks v4.3.

- Web interface through the Home Assistant sidebar panel (ingress).
- Mapped port 8000 for ping URLs and for reaching the interface directly.
- SQLite by default, optional external PostgreSQL.
- Optional SMTP for alerts, monthly reports and sign-in links.
- Optional inbound SMTP listener for pinging by email.
- Optional auto sign-in for ingress requests.
- Optional TLS on the mapped port.
