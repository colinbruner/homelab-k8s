{{/*
Chart name, truncated to 63 chars.
*/}}
{{- define "kopia.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified release name, truncated to 63 chars.
*/}}
{{- define "kopia.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "kopia.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{ include "kopia.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "kopia.selectorLabels" -}}
app.kubernetes.io/name: kopia
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Repository description — defaults to "UNAS <Title-cased-name> Backup" if .Values.target.description is empty.
*/}}
{{- define "kopia.repoDescription" -}}
{{- if .Values.target.description }}
{{- .Values.target.description }}
{{- else }}
{{- printf "UNAS %s Backup" (.Values.target.name | title) }}
{{- end }}
{{- end }}
