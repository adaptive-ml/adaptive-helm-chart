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
{{- printf "%s-control-plane" (include "adaptive.fullname" .) | trunc 30 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.controlPlane.service.fullname"}}
{{- printf "%s-svc" (include "adaptive.controlPlane.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}

{{- define "adaptive.harmony.fullname" -}}
{{- printf "%s-harmony" (include "adaptive.fullname" .) | trunc 30 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.service.fullname"}}
{{- printf "%s-svc" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.headlessService.fullname"}}
{{- printf "%s-hdls-svc" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.settingsConfigMap.fullname"}}
{{- printf "%s-settings-confmap" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.alloyConfigMap.fullname"}}
{{- printf "%s-alloy-confmap" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.deployment.fullname"}}
{{- printf "%s-dpl" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
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
{{- define "adaptive.externalSecretStore.fullname"}}
{{- printf "%s-ext-secret-store" (include "adaptive.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.controlPlane.configSecret.fullname"}}
{{- printf "%s-config-secret" (include "adaptive.controlPlane.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.configSecret.fullname"}}
{{- printf "%s-config-secret" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.controlPlane.externalSecret.fullname"}}
{{- printf "%s-ext-secret" (include "adaptive.controlPlane.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}
{{- define "adaptive.harmony.externalSecret.fullname"}}
{{- printf "%s-ext-secret" (include "adaptive.harmony.fullname" .) | trunc 63 | trimSuffix "-" }}
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


{{- define "adaptive.oidc_providers" -}}
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
Redis related helpers
*/}}
{{- define "adaptive.redis.fullname" -}}
{{- printf "%s-redis" (include "adaptive.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "adaptive.redis.service.fullname" -}}
{{- printf "%s-svc" (include "adaptive.redis.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "adaptive.redis.selectorLabels" -}}
app.kubernetes.io/component: redis
{{ include "adaptive.sharedSelectorLabels" . }}
{{- end }}

{{- define "adaptive.redis.secret.fullname" -}}
{{- printf "%s-secret" (include "adaptive.redis.fullname" .) | trunc 63 | trimSuffix "-" }}
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