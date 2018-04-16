
# Meta tasks
# ----------

.PHONY: test .env


# Configuration
# -------------

# Import environment variables if an .env file is present
ifneq ("$(wildcard .env)","")
export $(shell [ -f .env ] && sed 's/=.*//' .env)
$(info Note: importing environment variables from .env file)
endif

# Set up the npm binary path
NPM_BIN = ./node_modules/.bin
export PATH := $(PATH):$(NPM_BIN)

ifneq ("$(wildcard node_modules/@financial-times/origami-service-makefile/index.mk)","")
PATH_TO_SERVICE_MAKEFILE := node_modules/@financial-times/origami-service-makefile/
endif


# Output helpers
# --------------

TASK_DONE = echo "✓ $@ done"


# Group tasks
# -----------

all: install ci
ci: verify test whitesource


# Install tasks
# -------------

# Update the .env file with secrets from Vault (https://github.com/Financial-Times/vault/wiki/)
.env:
	@if [[ -z "$(shell command -v vault)" ]]; then echo "Error: You don't have Vault installed. Follow the guide at https://github.com/Financial-Times/vault/wiki/Getting-Started"; exit 1; fi
	@if [[ -z "$(shell find ~/.vault-token -mmin -480)" ]]; then echo "Error: You are not logged into Vault. Try vault auth --method github."; exit 1; fi
	@if [[ -z "$(shell grep .env .gitignore)" ]]; then echo "Error: .gitignore must include .env"; exit 1; fi
	@if [[ "$(shell grep .env .npmignore --silent --no-messages; echo $$?)" -eq 1 ]]; then echo "Error: .npmignore must include .env"; exit 1; fi
	@SERVICE_SYSTEM_CODE=$(SERVICE_SYSTEM_CODE) REGION=$(REGION) node $(PATH_TO_SERVICE_MAKEFILE)lib/vault.js
	@$(TASK_DONE)

# Clean the Git repository
clean:
	@git clean -fxd
	@$(TASK_DONE)

# Install dependencies
install: node_modules
	@$(TASK_DONE)

# Run npm install if package.json has changed more
# recently than node_modules
node_modules: package.json
	@npm prune --production=false
	@npm install
	@$(TASK_DONE)


# Verify tasks
# ------------

# Default configurations for code coverage
export EXPECTED_COVERAGE := 90

# Run all of the verify tasks
verify: verify-javascript verify-coverage
	@$(TASK_DONE)

# Run all of the JavaScript verification tasks
verify-javascript: verify-eslint
	@$(TASK_DONE)

# Run eslint against the codebase if an .eslintrc
# file exists in the repo
verify-eslint:
	@if [ -e .eslintrc* ]; then eslint . && $(TASK_DONE); fi

# Verify that code coverage meets the expected
# percentage. This works with either nyc or istanbul
verify-coverage:
	@if [ -d coverage ]; then \
		if [ -x $(NPM_BIN)/nyc ]; then \
			nyc check-coverage --lines $(EXPECTED_COVERAGE) --functions $(EXPECTED_COVERAGE) --branches $(EXPECTED_COVERAGE) && $(TASK_DONE); \
		else \
			if [ -x $(NPM_BIN)/istanbul ]; then \
				istanbul check-coverage --statement $(EXPECTED_COVERAGE) --branch $(EXPECTED_COVERAGE) --function $(EXPECTED_COVERAGE) && $(TASK_DONE); \
			fi \
		fi \
	fi


# Test tasks
# ----------

# Default configurations for integration tests
export INTEGRATION_TIMEOUT := 5000
export INTEGRATION_SLOW := 4000

# Run all of the test tasks and verify coverage
test: test-unit-coverage verify-coverage test-integration
	@$(TASK_DONE)

# Run the unit tests using mocha
test-unit:
	@if [ -d test/unit ]; then mocha "test/unit/**/*.test.js" --recursive && $(TASK_DONE); fi

# Run the unit tests using mocha and generating
# a coverage report if nyc or istanbul are installed
test-unit-coverage:
	@if [ -d test/unit ]; then \
		if [ -x $(NPM_BIN)/nyc ]; then \
			nyc --reporter=text --reporter=html $(NPM_BIN)/_mocha "test/unit/**/*.test.js" --recursive && $(TASK_DONE); \
		else \
			if [ -x $(NPM_BIN)/istanbul ]; then \
				istanbul cover $(NPM_BIN)/_mocha -- "test/unit/**/*.test.js" --recursive && $(TASK_DONE); \
			else \
				make test-unit; \
			fi \
		fi \
	fi

# Run the integration tests using mocha
test-integration:
	@if [ -d test/integration ]; then mocha "test/integration/**/*.test.js" --recursive --timeout $(INTEGRATION_TIMEOUT) --slow $(INTEGRATION_SLOW) $(INTEGRATION_FLAGS) && $(TASK_DONE); fi


# Service running tasks
# ---------------------

# Run the service in the same way as production
run:
	@npm start

# Run the service using nodemon, restarting when
# local files change
run-dev:
	@nodemon --ext html,js,json --exec "npm start"


# Deploy tasks
# ------------

# Deploy to the QA application via git push
deploy:
	@git push https://git.heroku.com/$(HEROKU_APP_QA).git
	@$(TASK_DONE)

# Perform the tasks necessary before triggering
# a release. To be used in Heroku release stages
release: release-log
ifneq ($(REGION), QA)
	@make cmdb-update
endif
	@$(DONE)

# Promote the QA application to production
promote:
	@heroku pipelines:promote --app $(HEROKU_APP_QA)
	@$(TASK_DONE)

# Check for the presence of required deploy
# environment variables
deploy-checks:
	@if [ -z "$(HEROKU_APP_QA)" ]; then echo "Error: HEROKU_APP_QA is not set" && exit 1; fi


# Versioning tasks
# ----------------

# Get a canonical "current commit" regardless of environment
ifeq ($(SOURCE_VERSION),)
export SOURCE_VERSION := $(CIRCLE_SHA1)
endif
ifeq ($(SOURCE_VERSION),)
export SOURCE_VERSION := $(TRAVIS_COMMIT)
endif

# Auto-version the repo and create a GitHub release
auto-version:
	@if [ "$${REGION}" = "QA" ] || [ -n "$${CI}" ]; then \
		if [ -z "$${SOURCE_VERSION}" ]; then echo "Error: SOURCE_VERSION is not set" && exit 1; fi; \
		if [ -z "$${GITHUB_RELEASE_TOKEN}" ]; then echo "Error: GITHUB_RELEASE_TOKEN is not set" && exit 1; fi; \
		if [ -z "$${GITHUB_RELEASE_USER}" ]; then echo "Error: GITHUB_RELEASE_USER is not set" && exit 1; fi; \
		if [ -z "$${GITHUB_RELEASE_REPO}" ]; then echo "Error: GITHUB_RELEASE_REPO is not set" && exit 1; fi; \
		npx @quarterto/git-version-infer --all-commits && npx @quarterto/package-version-github-release; \
	else \
		echo "Auto-versioning will only run when REGION=QA or CI=true"; \
	fi;


# CMDB tasks
# ----------

# Update all CMDB endpoints
cmdb-update:
	@if [ -d operational-documentation ]; then make cmdb-checks cmdb-update-eu cmdb-update-us cmdb-update-runbook && $(TASK_DONE); fi

# Update the CMDB endpoint for the EU application
cmdb-update-eu:
	@curl --silent --show-error -H 'Content-Type: application/json' -H 'X-Api-Key: ${CMDB_API_KEY}' \
		-X PUT https://cmdb.in.ft.com/v3/items/endpoint/$(HEROKU_APP_EU).herokuapp.com \
		-d @operational-documentation/health-and-about-endpoints-eu.json -f > /dev/null
	@$(TASK_DONE)

# Update the CMDB endpoint for the US application
cmdb-update-us:
	@curl --silent --show-error -H 'Content-Type: application/json' -H 'X-Api-Key: ${CMDB_API_KEY}' \
		-X PUT https://cmdb.in.ft.com/v3/items/endpoint/$(HEROKU_APP_US).herokuapp.com \
		-d @operational-documentation/health-and-about-endpoints-us.json -f > /dev/null
	@$(TASK_DONE)

# Update the application runbook
cmdb-update-runbook:
	@curl --silent --show-error -H 'Content-Type: application/json' -H 'X-Api-Key: ${CMDB_API_KEY}' \
		-X PUT https://cmdb.in.ft.com/v3/items/system/$(SERVICE_SYSTEM_CODE) \
		-d @operational-documentation/runbook.json -f > /dev/null
	@$(TASK_DONE)

# Check for the presence of required CMDB
# environment variables
cmdb-checks:
	@if [ -z "$(CMDB_API_KEY)" ]; then echo "Error: CMDB_API_KEY is not set" && exit 1; fi
	@if [ -z "$(SERVICE_SYSTEM_CODE)" ]; then echo "Error: SERVICE_SYSTEM_CODE is not set" && exit 1; fi
	@if [ -z "$(HEROKU_APP_EU)" ]; then echo "Error: HEROKU_APP_EU is not set" && exit 1; fi
	@if [ -z "$(HEROKU_APP_US)" ]; then echo "Error: HEROKU_APP_US is not set" && exit 1; fi


# Release log tasks
# -----------------

# Create a release log in Salesforce for the service
# TODO: work out how we can use origami.support@ft.com as an owner email
release-log: release-log-checks
	@npx -p @financial-times/release-log@^1 release-log \
		--environment "$(RELEASE_LOG_ENVIRONMENT)" \
		--api-key "$(RELEASE_LOG_API_KEY)" \
		--summary "Releasing $(SERVICE_NAME) to $(RELEASE_LOG_ENVIRONMENT) ($(REGION))" \
		--description "Release triggered by CI" \
		--owner-email "rowan.manning@ft.com" \
		--service "$(SERVICE_SALESFORCE_ID)" \
		--notify-channel "origami-deploys"
	@$(TASK_DONE)

# Check for the presence of required release-log
# environment variables
release-log-checks:
	@if [ -z "$(RELEASE_LOG_API_KEY)" ]; then echo "Error: RELEASE_LOG_API_KEY is not set" && exit 1; fi
	@if [ -z "$(RELEASE_LOG_ENVIRONMENT)" ]; then echo "Error: RELEASE_LOG_ENVIRONMENT is not set" && exit 1; fi
	@if [ -z "$(SERVICE_NAME)" ]; then echo "Error: SERVICE_NAME is not set" && exit 1; fi
	@if [ -z "$(SERVICE_SALESFORCE_ID)" ]; then echo "Error: SERVICE_SALESFORCE_ID is not set" && exit 1; fi
	@if [ -z "$(REGION)" ]; then echo "Error: REGION is not set" && exit 1; fi


# Monitoring tasks
# ----------------

# Pull monitoring dashboard changes from Grafana
grafana-pull: grafana-checks
	@grafana pull $(GRAFANA_DASHBOARD) ./operational-documentation/grafana-dashboard.json

# Push monitoring dashboard changes to Grafana
grafana-push: grafana-checks
	@grafana push $(GRAFANA_DASHBOARD) ./operational-documentation/grafana-dashboard.json --overwrite

# Check for the presence of required release-log
# environment variables
grafana-checks:
	@if [ -z "$(GRAFANA_API_KEY)" ]; then echo "Error: GRAFANA_API_KEY is not set" && exit 1; fi
	@if [ -z "$(GRAFANA_DASHBOARD)" ]; then echo "Error: GRAFANA_DASHBOARD is not set" && exit 1; fi


# Whitesource tasks
# -----------------

# Verify security and licensing of production dependencies
whitesource:
	@if [ -f "$(whitesource.config.json)" ]; then \
		echo "Warning: whitesource.config.json file not found, skipping running whitesource"; \
	else \
		npx -p whitesource@^1 whitesource run; \
	fi
