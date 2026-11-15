---
name: weather-report
description: "Weather: current conditions # and forecasts"
compatibility: Requires a supported weather service
allowed-tools: [weather.current, weather.forecast]
metadata:
  openclaw:
    emoji: "🌦️"
    requires:
      bins: [curl, jq]
      env: [WEATHER_API_KEY]
    install:
      - id: brew
        kind: brew
        formula: jq
        optional: true
        retries: 9007199254740993
  vendor-extra: !vendor {nested: [null, false, 1.25, "on"]}
unknown-header: &shared {preserve: "é שלום 👩🏽‍💻"}
unknown-copy: *shared
---

# Weather
Use the configured service. Do not execute metadata.
