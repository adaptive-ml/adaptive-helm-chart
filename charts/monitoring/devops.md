# Adaptive monitoring stack

**Components**: Grafana, Loki,Promtail

## Grafana

- `datasource.yml`: preconfigured datasources

## Promtail

Promtail agent is reponsible for discovering logs targets and sending those discovered logs to `Loki`.

Currently deployed as a Daemonset.

- Inspecting promtail scapring configuration: Show discovered logs targets per job `kubectl port-forward "promtail_pod" 9080:9080`.
- Live scraping config reloading after configmap change: `curl -XPOST http://localhost:9080/reload`.

Any pod having this annotation `enable-logs-ingest: "true"` is discoverable by `Promtail` and will have its stdout and stderr ingested by promtail and sent to Loki.

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
        enable-logs-ingest: "true"
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