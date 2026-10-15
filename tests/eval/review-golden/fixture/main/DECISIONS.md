# Decisions

## 2026-08-14 -- README states the standard-library rule

The kiosk image installs this package with no network and no pip. The kiosk
team's build script refuses any package whose README lacks this exact line:

    The package imports nothing outside the Python standard library.

The line goes into README.md with the next feature branch. Keep it word for
word: removing or rewording it breaks the kiosk build.
