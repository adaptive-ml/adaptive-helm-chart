{{- define "adaptive.name" -}}
{{- default .Values.nameOverride .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Default fully qualified app name.
We truncate at 30 chars so we have characters left to append individual components' names.
*/}}
{{- define "adaptive.fullname" -}}
{{- $name := default .Values.nameOverride .Chart.Name }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 30 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 30 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Control plane and harmony components full names
*/}}
{{- define "adaptive.controlPlane.fullname" -}}
{{- printf "%s-controlplane" (include "adaptive.fullname" .) | trunc 30 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.controlPlane.service.fullname"}}
{{- printf "%s" (include "adaptive.controlPlane.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}

{{- define "adaptive.harmony.fullname" -}}
{{- printf "%s-harmony" (include "adaptive.fullname" .) | trunc 30 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.service.fullname"}}
{{- printf "%s" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.headlessService.fullname"}}
{{- printf "%s-hdls" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.settingsConfigMap.fullname"}}
{{- printf "%s-settings" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.alloyConfigMap.fullname"}}
{{- printf "%s-alloy" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.deployment.fullname"}}
{{- printf "%s" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}

# MLFlow names
{{- define "adaptive.mlflow.fullname" -}}
{{- printf "%s-mlflow" (include "adaptive.fullname" .) | trunc 30 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.mlflow.service.fullname"}}
{{- printf "%s-svc" (include "adaptive.mlflow.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.mlflow.pvc.fullname"}}
{{- printf "%s-pvc" (include "adaptive.mlflow.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}



{{/*
Secret related fullnames
*/}}
{{- define "adaptive.controlPlane.secret.fullname"}}
{{- if .Values.secrets.existingControlPlaneSecret }}
{{- .Values.secrets.existingControlPlaneSecret }}
{{- else }}
{{- printf "%s-secret" (include "adaptive.controlPlane.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end}}
{{- define "adaptive.harmony.secret.fullname"}}
{{- if .Values.secrets.existingHarmonySecret }}
{{- .Values.secrets.existingHarmonySecret }}
{{- else }}
{{- printf "%s-secret" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end}}



{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "adaptive.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "adaptive.labels" -}}
helm.sh/chart: {{ include "adaptive.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Shared selector labels
*/}}
{{- define "adaptive.sharedSelectorLabels" -}}
app.kubernetes.io/name: {{ include "adaptive.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end}}

{{/*
Control plane and harmony selector labels
*/}}
{{- define "adaptive.controlPlane.selectorLabels" -}}
app.kubernetes.io/component: control-plane
{{ include "adaptive.sharedSelectorLabels" . }}
{{- end }}

{{- define "adaptive.harmony.selectorLabels" -}}
app.kubernetes.io/component: harmony
{{ include "adaptive.sharedSelectorLabels" . }}
{{- end }}

{{- define "adaptive.harmony.deployment.selectorLabels" -}}
app.kubernetes.io/component: harmony-dpl
{{ include "adaptive.sharedSelectorLabels" . }}
{{- end }}

# MLFlow selector labels
{{- define "adaptive.mlflow.selectorLabels" -}}
app.kubernetes.io/component: mlflow
{{ include "adaptive.sharedSelectorLabels" . }}
{{- end }}

{{/*
Harmony ports
*/}}
{{- define "adaptive.harmony.ports" -}}
{
  "http": {"name": "http", "containerPort": 50053, "port": 80},
  "queue": {"name": "queue", "containerPort": 50052},
  "torch": {"name": "torch", "containerPort": 7777},
  "tensorboard": {"name": "tensorboard", "containerPort": 6006},
  "alloy": {"name": "alloy", "containerPort": 12345}
}
{{- end }}

{{/*
MLFlow ports
*/}}
{{- define "adaptive.mlflow.ports" -}}
{
  "http": {"name": "http", "containerPort": 5000, "port": 5000}
}
{{- end }}

{{/*
Harmony service HTTP endpoint
*/}}
{{- define "adaptive.harmony.httpEndpoint" -}}
{{- $ports := fromJson (include "adaptive.harmony.ports" .) -}}
{{- printf "http://%s:%d" (include "adaptive.harmony.service.fullname" .) (int $ports.http.port) }}
{{- end }}


{{- define "adaptive.oidcProviders" -}}
[
  {{- range .Values.secrets.auth.oidc.providers -}}
  {
    key={{ .key }},
    name={{ .name }},
    issuer_url={{ .issuer_url | quote }},
    client_id={{ .client_id | quote }},
    {{- if .client_secret -}}
    client_secret={{ .client_secret | quote }},
    {{- end -}}
    scopes={{ .scopes | toJson }},
    pkce={{ .pkce }},
    allow_sign_up={{ .allow_sign_up }}
  },
  {{- end -}}
]
{{- end -}}

{{/*
Control plane ports
*/}}
{{- define "adaptive.controlPlane.ports" -}}
{
  "http": {"name": "http", "containerPort": 9000},
  "internal": {"name": "internal", "containerPort": 9009}
}
{{- end }}

{{/*
Control plane HTTP private endpoint
*/}}
{{- define "adaptive.controlPlane.privateHttpEndpoint" -}}
{{- $ports := fromJson (include "adaptive.controlPlane.ports" .) -}}
{{- printf "http://%s:%d" (include "adaptive.controlPlane.service.fullname" .) (int $ports.internal.containerPort) }}
{{- end }}

{{/*
Harmony settings
*/}}
{{- define "adaptive.harmony.settings" -}}
{
  "working_dir": "/opt/adaptive/working_dir",
  "shared_master_worker_folder": "/opt/adaptive/working_dir",
  "any_path_config": {
    "cloud_cache": "/opt/adaptive/cloud_cache"
  }
}
{{- end }}

{{/*
Build the image URIs from registry, repository, name, and tag
*/}}
{{- define "adaptive.harmony.imageUri" -}}
{{- printf "%s/%s:%s" .Values.containerRegistry .Values.harmony.image.repository .Values.harmony.image.tag | trimSuffix "/" }}
{{- end }}
{{- define "adaptive.controlPlane.imageUri" -}}
{{- printf "%s/%s:%s" .Values.containerRegistry .Values.controlPlane.image.repository .Values.controlPlane.image.tag | trimSuffix "/" }}
{{- end }}
{{- define "adaptive.tensorboard.imageUri" -}}
{{- printf "%s" .Values.tensorboard.imageUri }}
{{- end }}
{{- define "adaptive.mlflow.imageUri" -}}
{{- printf "%s" .Values.mlflow.imageUri }}
{{- end }}

{{/*
Get MLflow tracking URL - returns external URL if configured, otherwise internal service URL
*/}}
{{- define "adaptive.mlflow.trackingUrl" -}}
{{- if and .Values.mlflow.enabled .Values.mlflow.external.enabled -}}
{{- required "MLflow external URL must be set when mlflow.external.enabled is true" .Values.mlflow.external.url }}
{{- else -}}
{{- printf "http://%s:%d" (include "adaptive.mlflow.service.fullname" .) (int (include "adaptive.mlflow.ports" . | fromJson).http.port) }}
{{- end }}
{{- end }}

{{/*
Redis related helpers
*/}}
{{- define "adaptive.redis.fullname" -}}
{{- printf "%s-redis" (include "adaptive.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "adaptive.redis.service.fullname" -}}
{{- printf "%s-svc" (include "adaptive.redis.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "adaptive.redis.configMap.fullname"}}
{{- printf "%s-redis-confmap" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}

{{- define "adaptive.redis.selectorLabels" -}}
app.kubernetes.io/component: redis
{{ include "adaptive.sharedSelectorLabels" . }}
{{- end }}

{{- define "adaptive.redis.secret.fullname" -}}
{{- if .Values.secrets.existingRedisSecret }}
{{- .Values.secrets.existingRedisSecret }}
{{- else }}
{{- printf "%s-secret" (include "adaptive.redis.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "adaptive.redis.url" -}}
{{- $host := include "adaptive.redis.service.fullname" . -}}
{{- $port := .Values.redis.port | int -}}
{{- if and .Values.redis.auth.username .Values.redis.auth.password -}}
{{- printf "redis://%s:%s@%s:%d" .Values.redis.auth.username .Values.redis.auth.password $host $port -}}
{{- else if .Values.redis.auth.password -}}
{{- printf "redis://:%s@%s:%d" .Values.redis.auth.password $host $port -}}
{{- else -}}
{{- printf "redis://%s:%d" $host $port -}}
{{- end -}}
{{- end }}

{{/*
Helper to generate Harmony secret environment variables
Usage: {{ include "adaptive.harmony.secretEnvVars" . | nindent 12 }}
*/}}
{{- define "adaptive.harmony.secretEnvVars" -}}
- name: ADAPTIVE_MODEL_REGISTRY
  valueFrom:
    secretKeyRef:
      name: {{ include "adaptive.harmony.secret.fullname" . }}
      key: modelRegistryUrl
- name: ADAPTIVE_HARMONY__SHARED_DIRECTORY__URL
  valueFrom:
    secretKeyRef:
      name: {{ include "adaptive.harmony.secret.fullname" . }}
      key: sharedDirectoryUrl
- name: HARMONY_SETTING_MODEL_REGISTRY_ROOT
  valueFrom:
    secretKeyRef:
      name: {{ include "adaptive.harmony.secret.fullname" . }}
      key: modelRegistryUrl
{{- end }}

{{/*
Helper to generate Redis secret environment variables
Usage: {{ include "adaptive.redis.secretEnvVars" . | nindent 12 }}
*/}}
{{- define "adaptive.redis.secretEnvVars" -}}
- name: ADAPTIVE_REDIS__URL
  valueFrom:
    secretKeyRef:
      name: {{ include "adaptive.redis.secret.fullname" . }}
      key: redisUrl
- name: REDIS_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "adaptive.redis.secret.fullname" . }}
      key: redisUrl
{{- end }}


