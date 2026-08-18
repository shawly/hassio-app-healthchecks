# Home Assistant App: Healthchecks

[Healthchecks][healthchecks] watches your cron jobs, backups and background
tasks. Each job gets a URL to request when it finishes; if a request does not
arrive on schedule, Healthchecks notifies you.

## Installation

1. Add this app repository to your Home Assistant instance.
1. Search for "Healthchecks" in the app store and install it.
1. Set `superuser_email` and `superuser_password` in the configuration.
1. Set `site_root` to a URL your monitored machines can reach.
1. Start the app and open the panel in the sidebar.

## Two ways in

The app serves the same instance twice:

- **Ingress**, the panel in the Home Assistant sidebar. Nothing to expose,
  works through Nabu Casa and any reverse proxy in front of Home Assistant.
- **Port 8000**, mapped by default. This is what the monitored machines send
  their pings to, and the address that ends up in every ping URL.

If you remove the port mapping, the web interface still works through ingress,
but nothing can ping the instance any more, which makes it useless. Keep the
port mapped.

## Configuration

```yaml
log_level: info
site_root: http://homeassistant.local:8000
site_name: Healthchecks
registration_open: false
allow_private_ips: true
db: sqlite
superuser_email: you@example.com
superuser_password: something-long
smtp_host: smtp.example.com
smtp_port: 587
smtp_user: you@example.com
smtp_password: hunter2
smtp_tls: true
ssl: false
```

### Option: `site_root`

The public base URL of this instance. Every ping URL is built from it, so it
has to be an address the machines you are monitoring can reach. Defaults to
`http://<your Home Assistant host>:8000`, which is right on a flat home network
and wrong as soon as you put a reverse proxy in front of it.

Changing it does not rewrite the ping URLs that are already stored; it changes
how they are displayed and where new ones point.

### Option: `site_name`

The name shown in the interface and in notification subjects.

### Option: `registration_open`

Whether strangers can sign up. Defaults to `false`. Leave it there unless you
are deliberately running an instance for other people.

### Option: `allow_private_ips`

Whether the webhook and Apprise integrations are allowed to call private
addresses. Defaults to `true`, which is what you want for notifying something
on your own LAN. Set it to `false` if the instance is reachable from the
internet and you do not fully trust everyone who can log in, since it is the
only thing stopping a notification from being pointed at an internal service.

### Option: `superuser_email` / `superuser_password`

Creates the first account the first time the app starts. Both are needed.
The account is only created if that email address is not already registered, so
changing the password here later does **not** change the account password - do
that from the web interface.

### Option: `ingress_user`

Signs ingress requests in as this account automatically, so opening the sidebar
panel does not ask for a password again. Anyone who can open your Home
Assistant can then use Healthchecks as that account, which is usually what you
want and occasionally not. The port 8000 entrance is unaffected and keeps
asking for a password.

### Option: `db` and friends

`sqlite` (default) keeps the database at `/data/healthchecks.sqlite`, inside
the app's own storage, and is included in Home Assistant backups. It is a
sensible choice for a home instance.

Set `db: postgres` to use an external PostgreSQL server instead, along with
`db_host`, `db_port`, `db_name`, `db_user` and `db_password`. The database has
to exist already; the app creates the schema but not the database.

### Option: `smtp_host` and friends

Healthchecks sends alerts, monthly reports and sign-in links by email. Without
an SMTP server none of that is delivered, and email-based sign-in links stop
working - which is why `superuser_password` matters.

`smtp_from` sets the `From` address if it differs from `smtp_user`.

### Option: `smtpd_port`

Runs Healthchecks' own SMTP listener on this port, so jobs can ping by sending
mail instead of making an HTTP request. Off unless set. Remember to map the
port in the app's network configuration too.

### Option: `csrf_trusted_origins`

Only needed if you reach the direct port through a reverse proxy that changes
the scheme or hostname and logins start failing with a CSRF error. Add the
origin, including the scheme:

```yaml
csrf_trusted_origins:
  - https://checks.example.com
```

### Option: `ssl`, `certfile`, `keyfile`

Serves port 8000 over HTTPS using a certificate from Home Assistant's `/ssl`
directory. Ingress is unaffected - Home Assistant already handles TLS there.

Remember to set `site_root` to an `https://` URL as well, or the ping URLs will
point at a port that no longer speaks HTTP.

### Option: `log_level`

`trace`, `debug`, `info` (default), `notice`, `warning`, `error` or `fatal`.
Controls both the app's own startup logging and how much Healthchecks writes
to the app log.

## Notes on how this app is put together

Healthchecks is a Django application, and Django caches the URL prefix into
`STATIC_URL` the first time that setting is read. One process therefore cannot
serve both the ingress prefix and the root prefix correctly. The app runs
two uWSGI instances against one database instead: one for ingress, one for the
mapped port. Expect roughly 250 MB of memory rather than 130 MB.

The alert and report workers run in the ingress instance only, so nothing is
sent twice.

django-compressor is switched off for the same reason - its offline manifest
bakes in a single fixed prefix at build time. Assets are served unminified.

One upstream file is patched at build time,
[`patches/absolute-url-script-name.py`][patch]. Healthchecks builds absolute
URLs as `SITE_ROOT` plus a reversed path, and the reversed path carries the
ingress prefix, so status badges, e-mail links and OAuth redirect URIs came
out as the mapped port glued to an ingress-only path, with the ingress token
in the middle of them. The patch takes the prefix back off. It fails the build
if Healthchecks rewrites that function, rather than quietly doing nothing.

## Support

Open an issue on [the app repository][issues]. For questions about
Healthchecks itself, see the [Healthchecks documentation][healthchecks-docs].

[healthchecks]: https://github.com/healthchecks/healthchecks
[patch]: https://github.com/shawly/hassio-app-healthchecks/blob/main/healthchecks/patches/absolute-url-script-name.py
[healthchecks-docs]: https://healthchecks.io/docs/
[issues]: https://github.com/shawly/hassio-app-healthchecks/issues
