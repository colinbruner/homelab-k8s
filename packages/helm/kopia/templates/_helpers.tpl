{{/*
Common labels.
*/}}
{{- define "kopia.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: kopia
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Per-repository resource name. Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.repoFullname" -}}
{{- printf "%s-%s" .root.Release.Name .repo.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Per-repository selector labels. Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.repoSelectorLabels" -}}
app.kubernetes.io/name: kopia
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .repo.name }}
{{- end }}

{{/*
Fail rendering when a source references an unknown repository or omits retention.
*/}}
{{- define "kopia.validateSources" -}}
{{- $repoNames := list }}
{{- range .Values.repositories }}{{- $repoNames = append $repoNames .name }}{{- end }}
{{- range .Values.sources }}
{{- if not (has .repository $repoNames) }}
{{- fail (printf "source %q references unknown repository %q" .name .repository) }}
{{- end }}
{{- if not .retention }}
{{- fail (printf "source %q must set retention (explicit retention is required)" .name) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Backend-specific env vars. Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.backendEnv" -}}
{{- $b := .repo.backend }}
{{- if eq $b.type "gcs" }}
- name: REPO_TYPE
  value: gcs
- name: GCS_BUCKET
  value: {{ $b.gcs.bucket | quote }}
- name: GCS_CREDENTIALS_FILE
  value: /credentials/gcs/credentials.json
{{- else if eq $b.type "s3" }}
- name: REPO_TYPE
  value: s3
- name: S3_BUCKET
  value: {{ $b.s3.bucket | quote }}
- name: S3_ENDPOINT
  value: {{ $b.s3.endpoint | quote }}
{{- with $b.s3.region }}
- name: S3_REGION
  value: {{ . | quote }}
{{- end }}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ $b.s3.credentialsSecret }}
      key: access_key_id
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $b.s3.credentialsSecret }}
      key: secret_access_key
{{- else }}
{{- fail (printf "repository %q: unsupported backend type %q" .repo.name $b.type) }}
{{- end }}
{{- end }}

{{/*
Env shared by bootstrap initContainer, server, and verify CronJob.
Context: dict "root" $ "repo" <entry>, optional "usernameOverride" <string>.
*/}}
{{- define "kopia.repoEnv" -}}
- name: TZ
  value: {{ .root.Values.timezone | quote }}
- name: KOPIA_CONFIG_PATH
  value: /app/config/repository.config
- name: KOPIA_LOG_DIR
  value: /tmp/kopia-logs
- name: KOPIA_CACHE_SIZE_MB
  value: {{ .repo.cacheSizeMB | default 5000 | quote }}
- name: KOPIA_OVERRIDE_USERNAME
  value: {{ .usernameOverride | default .repo.identity.username | quote }}
- name: KOPIA_OVERRIDE_HOSTNAME
  value: {{ .repo.identity.hostname | quote }}
- name: KOPIA_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .repo.passwordSecret.name }}
      key: {{ .repo.passwordSecret.key | default "password" }}
{{- include "kopia.backendEnv" . }}
{{- end }}

{{/*
Volume mounts shared by bootstrap initContainer, server, and verify CronJob.
Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.repoStateMounts" -}}
- name: state
  mountPath: /app
- name: scripts
  mountPath: /app/scripts
  readOnly: true
- name: tmp
  mountPath: /tmp
{{- if eq .repo.backend.type "gcs" }}
- name: gcs-credentials
  mountPath: /credentials/gcs
  readOnly: true
{{- end }}
{{- end }}

{{/*
Backend credential volumes. Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.backendVolumes" -}}
{{- if eq .repo.backend.type "gcs" }}
- name: gcs-credentials
  secret:
    secretName: {{ .repo.backend.gcs.credentialsSecret }}
    items:
      - key: sa_json
        path: credentials.json
{{- end }}
{{- end }}
