# Home Assistant App: Healthchecks

[![License][license-shield]](LICENSE.md)
![Project Stage][project-stage-shield]
![Maintenance][maintenance-shield]

[![CI][ci-shield]][ci]

Self-hosted cron job and background task monitoring, packaged as a Home
Assistant app.

## About

[Healthchecks][healthchecks] watches cron jobs, backups and background tasks.
Each job gets a URL to request when it finishes; if the request does not arrive
on schedule, Healthchecks sends a notification.

The app serves the web interface twice: through the Home Assistant sidebar
panel, and on a mapped port that the monitored machines send their pings to.

[:books: App documentation][docs]

## License

MIT License. See [LICENSE.md](LICENSE.md).

[ci-shield]: https://github.com/shawly/hassio-app-healthchecks/actions/workflows/ci.yaml/badge.svg
[ci]: https://github.com/shawly/hassio-app-healthchecks/actions/workflows/ci.yaml
[docs]: healthchecks/DOCS.md
[healthchecks]: https://github.com/healthchecks/healthchecks
[license-shield]: https://img.shields.io/github/license/shawly/hassio-app-healthchecks.svg
[maintenance-shield]: https://img.shields.io/maintenance/yes/2026.svg
[project-stage-shield]: https://img.shields.io/badge/project%20stage-experimental-yellow.svg
