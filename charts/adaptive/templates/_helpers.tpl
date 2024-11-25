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
Config secrets fullname
*/}}
{{- define "adaptive.configSecret.fullname"}}
{{- printf "%s-config-secret" (include "adaptive.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}

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

{{/*
Harmony ports
*/}}
{{- define "adaptive.harmony.ports" -}}
{
  "http": {"name": "http", "containerPort": 50053, "port": 80},
  "queue": {"name": "queue", "containerPort": 50052},
  "torch": {"name": "torch", "containerPort": 7777}
}
{{- end }}

{{/*
Control plane ports
*/}}
{{- define "adaptive.controlPlane.ports" -}}
{
  "http": {"name": "http", "containerPort": 9000}
}
{{- end }}

{{/*
Harmony settings
*/}}
{{- define "adaptive.harmony.settings" -}}
{
  "working_dir": "/opt/adaptive/shared_folder",
  "shared_master_worker_folder": "/opt/adaptive/shared_folder",
  "model_registry_root": "/opt/adaptive/model_registry",
  "any_path_config": {
    "cloud_cache": "/opt/adaptive/model_registry"
  }
}
{{- end }}

{{/*
Build the image URIs from registry, repository, name, and tag
*/}}
{{- define "adaptive.harmony.imageUri" -}}
{{- printf "%s/%s:%s" .Values.harmony.image.registry .Values.harmony.image.repository .Values.harmony.image.tag | trimSuffix "/" }}
{{- end }}
{{- define "adaptive.controlPlane.imageUri" -}}
{{- printf "%s/%s:%s" .Values.controlPlane.image.registry .Values.controlPlane.image.repository .Values.controlPlane.image.tag | trimSuffix "/" }}
{{- end }}
