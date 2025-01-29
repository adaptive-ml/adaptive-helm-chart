# Adaptive monitoring stack

**Components**: Grafana, Loki,Promtail

## Grafana


- `datasource.yml`: preconfigured datasources

## Promtail

Promtail agent is reponsible for discovering logs targets and sending those discovered logs to `Loki`.

Currently deployed as a Daemonset.

- Inspecting promtail scapring configuration: Show discovered logs targets per job `kubectl port-forward "promtail_pod" 9080:9080`.
- Live scraping config reloading after configmap change: `curl -XPOST http://localhost:9080/reload`.