# JIRA → AAP → EC2 + Zabbix Demo

Ticket-driven, closed-loop VM provisioning: a user files a **VM Request**
ticket in JIRA Cloud, Ansible Automation Platform (AAP 2.5 on OpenShift)
receives it via an Event-Driven Ansible event stream, provisions an EC2
instance, installs and registers the Zabbix agent against a Zabbix server,
and comments on / transitions the ticket to Done. No human touches a console
in between.

Derived from
[redhat-telco-adoption/aap-eda-demo](https://github.com/redhat-telco-adoption/aap-eda-demo)
(Zabbix → EDA auto-remediation), with the trigger direction reversed:
events flow **from JIRA into EDA**.

## Architecture

```
┌────────────┐ 1. create ticket  ┌──────────────┐
│ Requester  │──────────────────▶│  JIRA Cloud  │
└────────────┘                   │ (VM Request) │
                                 └──────┬───────┘
                                        │ 2. Automation rule → webhook
                                        ▼
                       ┌────────────────────────────────┐
                       │ AAP 2.5 on OpenShift           │
                       │  ├─ EDA event stream + rulebook│
                       │  └─ Controller job template    │
                       │     "VM Request Fulfillment"   │
                       └───┬──────────────────┬─────────┘
                3. provision│                 │ 5. comment + transition to Done
                            ▼                 ▼
                     ┌────────────┐     ┌───────────┐
                     │ AWS EC2    │     │ JIRA API  │
                     │ demo VM    │     └───────────┘
                     └─────┬──────┘
                           │ 4. agent install + host registration
                           ▼
                     ┌──────────────────────────┐
                     │ Zabbix server (EC2)      │
                     │  └─ DB on RDS PostgreSQL │
                     └──────────────────────────┘
```

## Prerequisites

- AAP 2.5 running on OpenShift, reachable via its Gateway URL
- AWS account (VPC, EC2, RDS permissions) and a target region
- JIRA Cloud site with an API token
- Locally: `terraform` (>= 1.5), `ansible-core`, `make`,
  and the collections: `make config-collections`

## Quickstart

```bash
cp .env.example .env        # fill in real values (git-ignored)
make config-collections     # install required collections locally
make infra                  # Terraform: VPC, Zabbix EC2, RDS, SGs, key pair
make wait                   # wait for SSH on the Zabbix server
make config-zabbix          # DB schema, server install, API config
make config-aap             # Controller + EDA objects; prints the event stream webhook URL
make config-jira            # JIRA project, "VM Request" issue type, custom fields
```

Then create the **JIRA Automation rule** (manual, in the JIRA UI):

- Trigger: issue created, type "VM Request"
- Action: send web request to the event stream webhook URL printed by
  `make config-aap`, with basic auth `EDA_STREAM_USERNAME`/`EDA_STREAM_PASSWORD`
  and a flat JSON body:

```json
{
  "issue_type": "VM Request",
  "issue_key": "{{issue.key}}",
  "summary": "{{issue.summary}}",
  "instance_size": "{{issue.Instance Size}}",
  "environment": "{{issue.Environment}}",
  "reporter": "{{issue.reporter.displayName}}"
}
```

## Demo flow

1. Create a "VM Request" ticket in JIRA (summary = VM name, pick a size and
   environment).
2. The Automation rule posts to the EDA event stream; the `jira_eda.yml`
   rulebook launches the "VM Request Fulfillment" job template.
3. The playbook comments "Provisioning started", creates the EC2 instance
   (tagged with the issue key — re-runs won't duplicate), installs
   zabbix-agent2, and registers the host in Zabbix (group "VM Requests",
   template "Linux by Zabbix agent").
4. On success, the ticket gets a comment with the instance details and is
   transitioned to Done. On failure, the ticket gets a FAILED comment.

## Teardown

```bash
make destroy   # AAP objects + per-ticket VMs, then terraform destroy
```

## Layout

- `terraform/` — VPC, Zabbix server EC2, RDS PostgreSQL, security groups, key pair
- `ansible/playbooks/` — Zabbix setup, AAP config, JIRA bootstrap, fulfillment, teardown
- `ansible/roles/` — `zabbix_server`, `zabbix_agent`, `zabbix_config`, `aap_config`
- `rulebooks/jira_eda.yml` — EDA rulebook (synced by the EDA project)
- `collections/requirements.yml` — collections for the AAP execution environment
