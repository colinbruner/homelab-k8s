# Operational targets for the Kopia backup stack.
# Companion to docs/kopia-cutover-runbook.md — recurring commands only;
# one-time cutover/cleanup steps stay in the runbook.
#
# Variables:
#   NS    Namespace of the backup app        (default: backup)
#   REPO  Repository name from kopia-values  (default: primary)

NS     ?= backup
REPO   ?= primary
DEPLOY  = backup-$(REPO)

.DEFAULT_GOAL := help

.PHONY: help
help: ## List available targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

.PHONY: kopia-pods
kopia-pods: ## Watch backup pods
	kubectl -n $(NS) get pods -w

.PHONY: kopia-snapshots
kopia-snapshots: ## List all snapshots in the repository (REPO=primary)
	kubectl -n $(NS) exec deploy/$(DEPLOY) -c server -- kopia snapshot list --all

.PHONY: kopia-maintenance
kopia-maintenance: ## Show maintenance owner and schedule (REPO=primary)
	kubectl -n $(NS) exec deploy/$(DEPLOY) -c server -- kopia maintenance info

.PHONY: kopia-policies
kopia-policies: ## List snapshot policies (REPO=primary)
	kubectl -n $(NS) exec deploy/$(DEPLOY) -c server -- kopia policy list

.PHONY: kopia-verify
kopia-verify: ## Run the monthly verify CronJob immediately (REPO=primary)
	kubectl -n $(NS) create job --from=cronjob/$(DEPLOY)-verify verify-manual-$$(date +%s)

.PHONY: kopia-ui
kopia-ui: ## Port-forward the Kopia UI to https://localhost:51515 (REPO=primary)
	kubectl -n $(NS) port-forward svc/$(DEPLOY) 51515:51515

.PHONY: kopia-first-snapshot
kopia-first-snapshot: ## First snapshot for a new source: SRC=/data/<name> (required; scheduler only fires after one exists)
	@test -n "$(SRC)" || { echo "Usage: make kopia-first-snapshot SRC=/data/<name> [REPO=primary]"; exit 1; }
	kubectl -n $(NS) exec deploy/$(DEPLOY) -c server -- kopia snapshot create $(SRC)
