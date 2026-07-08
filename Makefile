include .env
export

TERRAFORM_DIR = terraform
ANSIBLE_DIR   = ansible

TF_VARS = TF_VAR_zabbix_ami=$(ZABBIX_AMI) \
	TF_VAR_zabbix_instance_type=$(ZABBIX_INSTANCE_TYPE) \
	TF_VAR_key_pair_name=$(AWS_KEY_PAIR_NAME) \
	TF_VAR_rds_master_password=$(RDS_MASTER_PASSWORD) \
	TF_VAR_rds_master_username=$(RDS_MASTER_USERNAME) \
	TF_VAR_rds_instance_class=$(RDS_INSTANCE_CLASS)

# ─── Full lifecycle ──────────────────────────────────────
.PHONY: all
all: check-env infra wait config-zabbix config-aap summary

.PHONY: destroy
destroy: teardown-aap infra-destroy

# ─── Env check ───────────────────────────────────────────
.PHONY: check-env
check-env:
	@test -n "$$AWS_ACCESS_KEY_ID" || (echo "ERROR: AWS_ACCESS_KEY_ID not set" && exit 1)
	@test -n "$$AWS_SECRET_ACCESS_KEY" || (echo "ERROR: AWS_SECRET_ACCESS_KEY not set" && exit 1)
	@test -n "$$AWS_REGION" || (echo "ERROR: AWS_REGION not set" && exit 1)
	@test -n "$$AAP_GATEWAY_URL" || (echo "ERROR: AAP_GATEWAY_URL not set" && exit 1)
	@test -n "$$JIRA_URL" || (echo "ERROR: JIRA_URL not set" && exit 1)
	@echo "Environment OK"

# ─── Infrastructure ──────────────────────────────────────
.PHONY: infra
infra:
	cd $(TERRAFORM_DIR) && $(TF_VARS) \
	sh -c 'terraform init && terraform apply -auto-approve'

.PHONY: infra-destroy
infra-destroy:
	cd $(TERRAFORM_DIR) && $(TF_VARS) \
	sh -c 'terraform destroy -auto-approve'

.PHONY: infra-output
infra-output:
	cd $(TERRAFORM_DIR) && terraform output

# ─── Wait ────────────────────────────────────────────────
.PHONY: wait
wait:
	bash scripts/wait_for_instances.sh

# ─── Zabbix Stack ────────────────────────────────────────
.PHONY: config-zabbix
config-zabbix: config-zabbix-db config-zabbix-server config-zabbix-api

.PHONY: config-zabbix-db
config-zabbix-db:
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup_zabbix_db.yml

.PHONY: config-zabbix-server
config-zabbix-server:
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup_zabbix_server.yml

.PHONY: config-zabbix-api
config-zabbix-api:
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/configure_zabbix.yml

# ─── AAP Config ──────────────────────────────────────────
.PHONY: config-aap
config-aap:
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/configure_aap.yml

# ─── JIRA Config ─────────────────────────────────────────
.PHONY: config-jira
config-jira:
	ansible-playbook ansible/playbooks/jira_bootstrap.yml

# ─── AAP Teardown ────────────────────────────────────────
.PHONY: teardown-aap
teardown-aap:
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/teardown.yml

# ─── Collections ─────────────────────────────────────────
.PHONY: config-collections
config-collections:
	cd $(ANSIBLE_DIR) && AUTOMATION_HUB_TOKEN=$(AUTOMATION_HUB_TOKEN) \
	ansible-galaxy collection install -r collections/requirements.yml --force

.PHONY: summary
summary:
	cd $(TERRAFORM_DIR) && terraform output summary
