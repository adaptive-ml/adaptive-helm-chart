# Adaptive monitoring stack

**Components**: Grafana, Loki,Promtail

## Table of Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Grafana](#grafana)
- [Promtail](#promtail)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Grafana

- `datasource.yml`: preconfigured datasources

## Promtail

Promtail agent is reponsible for discovering logs targets and sending those discovered logs to `Loki`.

Currently deployed as a Daemonset.

- Inspecting promtail scapring configuration: Show discovered logs targets per job `kubectl port-forward "promtail_pod" 9080:9080`.
- Live scraping config reloading after configmap change: `curl -XPOST http://localhost:9080/reload`.

Any pod having this annotation `ingest-adaptive-logs: "true"` is discoverable by `Promtail` and will have its stdout and stderr ingested by promtail and sent to Loki.

Testing

You can deploy a fake log generator to test logs are working:

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flog
spec:
  replicas: 10
  selector:
    matchLabels:
      app: flog
  template:
    metadata:
      labels:
        app: flog
      annotations:
        ingest-adaptive-logs: "true"
    spec:
      containers:
        - name: flog
          image: mingrammer/flog:0.4.3
          args: ["-s", "10s", "-d", "1s", "-l"] # Generate logs every 20s in JSON format
          resources:
            limits:
              memory: "128Mi"
              cpu: "100m"
```
