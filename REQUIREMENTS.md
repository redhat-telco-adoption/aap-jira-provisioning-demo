# PRD — JIRA-Driven VM Provisioning with Ansible Automation Platform

**Status:** Draft
**Author:** José Luis Mayorga
**Date:** 2026-07-08

---

## 1. Overview

This demo showcases a closed-loop, ticket-driven infrastructure provisioning
workflow. A user files a ticket in JIRA Cloud requesting a new VM. Ansible
Automation Platform (AAP), running on OpenShift, receives the request via
Event-Driven Ansible (EDA), provisions an EC2 instance in AWS, installs and
registers the Zabbix agent on it, and reports status back to the JIRA ticket —
with no human touching a console in between.

**Target audience:** Prospects/customers evaluating AAP for ITSM-integrated
self-service automation.

**Elevator pitch:** "Open a ticket, get a monitored VM."

**Starting point:** This demo builds on the private repo
[`redhat-telco-adoption/aap-eda-demo`](https://github.com/redhat-telco-adoption/aap-eda-demo)
(Zabbix → EDA auto-remediation). We reuse its infrastructure and AAP plumbing
and reverse the trigger direction: events come **from JIRA into EDA** instead
of from Zabbix. See §7 for the detailed reuse map.

## 2. Goals

| # | Goal | Success signal |
|---|------|----------------|
| G1 | Demonstrate JIRA Cloud as a self-service front end for automation | Ticket creation alone triggers the workflow |
| G2 | Demonstrate AAP on OpenShift as the automation engine | Job templates execute in AAP; visible in the AAP UI during the demo |
| G3 | Demonstrate end-to-end provisioning + day-1 config | EC2 instance running with Zabbix agent registered and reporting |
| G4 | Demonstrate closed-loop feedback | JIRA ticket receives status comments and is transitioned to Done automatically |

## 3. Non-Goals (Out of Scope)

- Production-grade security hardening (least-privilege IAM refinement, network
  segmentation, TLS between all components).
- High availability of AAP, Zabbix, or the provisioned workload.
- Approval workflows in JIRA (the ticket triggers provisioning directly; an
  approval step is a possible follow-up).
- Deprovisioning/teardown driven by JIRA (nice-to-have, see §10).
- Cost management, tagging governance, or multi-account AWS setups.
- Windows instances — Linux (RHEL or Amazon Linux) only.

## 4. Personas

- **Requester** — files a JIRA ticket asking for a VM; non-technical; only
  interacts with JIRA.
- **Automation engineer (demo presenter)** — owns AAP configuration,
  playbooks, and the EDA rulebook; narrates the flow.

## 5. End-to-End Workflow

```
┌────────────┐  1. create ticket   ┌──────────────────┐
│ Requester  │────────────────────▶│  JIRA Cloud      │
└────────────┘                     │  (VM Request)    │
                                   └────────┬─────────┘
                                            │ 2. JIRA Automation rule
                                            │    fires webhook
                                            ▼
                              ┌─────────────────────────────┐
                              │ AAP on OpenShift            │
                              │  ├─ EDA: rulebook matches   │
                              │  │  event, launches job     │
                              │  ├─ Controller: workflow    │
                              │  │  job template            │
                              └──┬───────────────┬──────────┘
                    3. provision │               │ 5. status updates
                                 ▼               ▼ (comments + transition)
                          ┌────────────┐   ┌───────────┐
                          │ AWS EC2    │   │ JIRA API  │
                          │ instance   │   └───────────┘
                          └─────┬──────┘
                                │ 4. install + register agent
                                ▼
                          ┌────────────┐
                          │ Zabbix     │
                          │ server     │
                          └────────────┘
```

1. Requester creates a JIRA issue of type **VM Request** with fields:
   instance name, instance size (t3.micro/small/medium), environment tag.
2. A JIRA Automation rule fires an outbound webhook to the EDA event stream
   endpoint exposed by AAP (OpenShift Route), carrying the issue key and
   field values.
3. The EDA rulebook validates the payload and launches an AAP **workflow job
   template** with the ticket fields as extra vars.
4. The workflow:
   a. Comments on the JIRA ticket: "Provisioning started."
   b. Provisions the EC2 instance (`amazon.aws.ec2_instance`), waits for SSH.
   c. Adds the host to the inventory dynamically, installs the Zabbix agent
      (`community.zabbix.zabbix_agent` role), points it at the Zabbix server.
   d. Registers the host in Zabbix (`community.zabbix.zabbix_host`) with a
      standard Linux template.
5. On success, the workflow comments on the ticket with instance details
   (instance ID, private/public IP, Zabbix host link) and transitions the
   ticket to **Done**. On failure, it comments with the error summary and
   leaves the ticket **In Progress** (no custom workflow status — see §12).

## 6. Functional Requirements

### FR-1 JIRA Cloud (configured as code)
- FR-1.1 Use the existing free JIRA Cloud site (`jlmayorga.atlassian.net`).
  Create a **new company-managed project** `VMREQ` — not the existing
  team-managed `KAN` project, whose fields/issue types are project-scoped
  with a weaker admin API.
- FR-1.2 Issue type **VM Request** with custom fields `Instance Size`
  (select: t3.micro/small/medium) and `Environment` (select: dev/test); the
  issue Summary serves as the VM name.
- FR-1.3 JIRA Automation rule: on issue created (type = VM Request), send
  web request (POST, JSON payload with issue key + custom fields) to the EDA
  event stream URL, authenticated with the Basic Event Stream credential.
- FR-1.4 API token for the JIRA account so AAP can comment on and
  transition issues.
- FR-1.5 **All JIRA configuration is code:** a `jira_bootstrap.yml` playbook
  (via `ansible.builtin.uri`, driven by `.env`) creates the project, issue
  type, custom fields + options, and the Automation rule (via the Automation
  Rule Management API, `POST /automation/public/jira/{cloudId}/rest/v1/rule`)
  and prints the created custom field IDs. Only two manual, one-time steps
  are permitted: creating the API token, and authoring the Automation rule
  once in the UI to export its JSON as the stored template the playbook
  re-creates (rule internals aren't documented enough to write from
  scratch; watch for the known smart-value mangling issue when re-posting).

### FR-2 AAP on OpenShift
- FR-2.1 AAP 2.5 available on the OpenShift cluster (Gateway + Controller +
  EDA + Hub). The base repo assumes an existing AAP install and configures it
  via the Gateway API (`AAP_GATEWAY_URL` + admin credentials in `.env`); if
  the cluster doesn't have AAP yet, install it via the AAP Operator as a
  documented setup step.
- FR-2.2 EDA **event stream** (with Basic Event Stream credential) reachable
  from the internet via an OpenShift Route, since JIRA Cloud must reach it.
  Reuses the event-stream + source-mapping pattern from `aap-eda-demo`'s
  `aap_config` role (including the test-mode disable and activation
  source-mapping API calls, which are already solved there).
- FR-2.3 EDA rulebook (`jira_eda.yml`, modeled on the repo's
  `zabbix_eda.yml`): match `event.payload.issue_type == "VM Request"`,
  launch the provisioning workflow job template with extra vars mapped from
  the payload.
- FR-2.4 Controller objects (created as code via `ansible.controller`
  collection or manually for the demo):
  - Project pointing at the demo Git repository (playbooks + rulebooks).
  - Execution environment with `amazon.aws` and `community.zabbix`
    collections.
  - Credentials: AWS access key, SSH machine credential, JIRA API token,
    Zabbix API credential.
  - Job templates: `provision-ec2`, `install-zabbix-agent`,
    `register-zabbix-host`, `update-jira` — composed into one **workflow
    job template** `vm-request-fulfillment` with failure paths that report
    back to JIRA.

### FR-3 AWS Provisioning
- FR-3.1 Provision a single EC2 instance from the ticket parameters:
  RHEL 9 AMI (matching the base repo), size from ticket (default `t3.micro`),
  tagged with `Name`, `Environment`, `RequestedBy` (JIRA reporter), and
  `JiraIssue` (issue key).
- FR-3.2 Networking: default VPC (or one demo VPC), public subnet, security
  group allowing SSH (22) from the AAP egress and Zabbix agent traffic
  (10050) from the Zabbix server.
- FR-3.3 SSH key pair managed as an AAP machine credential.
- FR-3.4 Idempotency: re-running the workflow for the same ticket must not
  create a duplicate instance (match on `JiraIssue` tag).

### FR-4 Zabbix
- FR-4.1 A Zabbix server provisioned on a dedicated EC2 instance during demo
  setup, reusing the `aap-eda-demo` approach as-is: Terraform provisions a
  RHEL 9 EC2 instance (`t3.medium`) plus an RDS PostgreSQL 15 database;
  Ansible roles (`zabbix_server`, `zabbix_config`) install
  `zabbix-server-pgsql` + nginx/php-fpm and configure the Zabbix API. This
  instance is part of the demo environment, not the per-ticket workflow.
- FR-4.2 Zabbix agent 2 installed on the new instance via the
  `community.zabbix.zabbix_agent` role, configured with the Zabbix server
  address (passive checks are sufficient).
- FR-4.3 Host registered via the Zabbix API with the "Linux by Zabbix agent"
  template; host visible and **green (available)** in the Zabbix UI within
  ~2 minutes of provisioning.

### FR-5 Feedback Loop
- FR-5.1 JIRA ticket receives a comment at workflow start, on success (with
  instance ID, IPs, Zabbix link), and on any failure (with a human-readable
  error summary).
- FR-5.2 Ticket transitioned automatically: In Progress → Done on success.

## 7. Technical Requirements & Constraints

- **Secrets:** All credentials (AWS keys, OpenShift kubeconfig/login, JIRA
  token, Zabbix password) live in a git-ignored `.env` file at the repo root.
  A committed `.env.example` documents the required variables. Setup scripts
  read `.env` and inject secrets into AAP credential objects — no secrets in
  Git, playbooks, or AAP job template definitions.
- **Repository layout:** fork/adopt the `aap-eda-demo` structure
  (`terraform/`, `ansible/{playbooks,roles,inventory}/`, `rulebooks/`,
  `scripts/`, `docs/`, `Makefile`, `.env.example`).

  **Reuse map from `aap-eda-demo`:**

  | Component | Status |
  |-----------|--------|
  | `terraform/` (VPC, security groups, keypair, Route53, RDS, Zabbix EC2) | Reuse; drop the two static `monitored-*` instances (ours are created per ticket) |
  | `ansible/roles/zabbix_server`, `zabbix_config` | Reuse as-is |
  | `ansible/roles/zabbix_agent` (agent2 install + conf template) | Reuse as-is on ticket-provisioned hosts |
  | `ansible/roles/aap_config` (Controller + EDA config-as-code, event streams, activations) | Adapt: new job templates, JIRA event stream instead of Zabbix stream |
  | `rulebooks/zabbix_eda.yml` | Model for new `rulebooks/jira_eda.yml` (JIRA payload conditions) |
  | `ansible/inventory/aws_ec2.yml` (dynamic inventory by tags) | Reuse; add a tag group for ticket-provisioned hosts |
  | `Makefile`, `.env.example`, `scripts/wait_for_instances.sh` | Reuse; extend `.env` with JIRA variables |
  | `remediation/` playbooks, trigger scripts, Slack notify, demo-app | Out of scope for v1 (candidate for a "part 2" remediation act, see §10) |

  **Net-new work:**
  - `jira_bootstrap.yml` playbook: creates the JIRA project, issue type,
    custom fields, and Automation webhook rule as code (FR-1.5), wired into
    the Makefile as `make config-jira`; JIRA variables in `.env`.
  - `rulebooks/jira_eda.yml` + JIRA event stream/credential in `aap_config`.
  - Playbooks: `provision_ec2.yml` (per-ticket, idempotent via `JiraIssue`
    tag), `update_jira.yml` (comment + transition); Zabbix agent install and
    host registration reuse existing roles.
  - Workflow job template `vm-request-fulfillment` wiring the above with
    failure paths.
- **Collections:** `amazon.aws`, `community.zabbix`, `ansible.controller`,
  `ansible.eda` (already pinned in the repo's `collections/requirements.yml`;
  add `community.general` or use `ansible.builtin.uri` for JIRA API calls).
- **Connectivity constraints:**
  - JIRA Cloud → EDA: EDA endpoint must be internet-reachable (OpenShift
    Route with a valid TLS cert) — JIRA Automation webhooks cannot reach
    private endpoints.
  - AAP → EC2: execution environment pods must reach the instance over SSH
    (public IP for demo simplicity).
  - Agent → Zabbix server: port 10050/10051 open between them.
- **Config as code where practical:** AAP objects defined via the
  `ansible.controller` collection so the demo is reproducible from scratch.

## 8. Demo Script (Happy Path)

1. Show the empty state: JIRA board, AAP dashboard, Zabbix host list.
2. Create a **VM Request** ticket in JIRA (name: `demo-web-01`, size:
   `t3.micro`, env: `dev`).
3. Switch to AAP: show the EDA rule audit firing and the workflow job
   running live.
4. Show the EC2 console: instance appearing with tags including the JIRA
   issue key.
5. Show Zabbix: new host registered and turning green.
6. Return to JIRA: ticket has progress comments and is now **Done**.
7. (Optional) Create a ticket with an invalid size to show the failure path
   commenting back on the ticket.

Total target runtime: **under 10 minutes**, with provisioning + agent
registration completing in under 5.

## 9. Acceptance Criteria

- [ ] Creating a VM Request ticket in JIRA launches the AAP workflow with no
      manual intervention (verified via EDA rule audit).
- [ ] EC2 instance is running, tagged with the JIRA issue key, and reachable
      over SSH.
- [ ] Zabbix agent is installed, and the host shows as available in Zabbix
      with the Linux template applied.
- [ ] JIRA ticket contains start + completion comments and ends in **Done**.
- [ ] A failed run (e.g., bad AMI/size) results in a failure comment on the
      ticket — no silent failures.
- [ ] Re-submitting the same ticket does not create a duplicate instance.
- [ ] `git grep` of the repo shows zero credentials; `.env` is git-ignored.
- [ ] The full environment can be rebuilt from this repo + `.env` following
      `setup/` docs.

## 10. Future Enhancements (Post-Demo)

- Approval step in JIRA before provisioning fires.
- Deprovisioning workflow: closing/labeling a ticket terminates the instance
  and removes the Zabbix host.
- Ansible survey / JIRA field validation for richer instance options.
- ServiceNow variant of the same flow.

## 11. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| JIRA Cloud webhook can't reach EDA (cluster route not public / cert issues) | Demo dead on arrival | Verify route reachability from the internet during setup; fallback: EDA polls JIRA via `ansible.eda.generic` source or a JQL poller |
| Free JIRA plan limits on Automation rule executions | Rule stops firing mid-demo cycle | Free plan allows limited automation runs/month; keep test runs lean, monitor usage |
| EC2 provisioning latency or AMI availability varies by region | Demo runs long | Pin region + AMI ID in `.env`; pre-warm once before presenting |
| Zabbix server down or agent port blocked | Registration step fails | Health-check Zabbix in workflow step 0; security group opened as code |
| AWS credential scope too broad in `.env` | Security exposure | Demo-dedicated IAM user restricted to EC2 in one region; rotate after demo |

## 12. Open Questions

1. ~~EDA event intake style~~ **Resolved:** AAP 2.5 event streams with a
   Basic Event Stream credential — the `aap-eda-demo` repo already implements
   this pattern end to end.
2. ~~AWS region and base AMI~~ **Resolved by default:** `us-east-2`, RHEL 9
   AMIs (Red Hat owner `309956199498`), inherited from the base repo's
   `.env.example`; still overridable per environment.
3. ~~Ticket transition on failure~~ **Resolved:** stay **In Progress** with a
   failure comment. A custom `Failed` status would require driving the
   workflow-editing API — the clunkiest JIRA endpoint — for little demo
   value.

*(All open questions are resolved; section retained for the decision log.)*
