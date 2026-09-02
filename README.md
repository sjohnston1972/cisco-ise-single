# cisco-ise-lab

[![Terraform CI](https://github.com/sjohnston1972/cisco-ise-dual_tacacs/actions/workflows/terraform.yml/badge.svg)](https://github.com/sjohnston1972/cisco-ise-dual_tacacs/actions/workflows/terraform.yml)

Terraform configuration to deploy a **Cisco ISE 3.4 distributed lab** on Microsoft Azure, including a Windows domain controller, Cisco C8000v router, and full TACACS+ Device Administration policy.

## Overview

Deploys a complete ISE lab environment into Azure for dev/test purposes. ISE nodes (primary and secondary) are deployed separately into their own resource groups; this Terraform config manages the supporting infrastructure and shared components in `rg-dev-smp-uks-ise`.

## Architecture

```
rg-dev-smp-uks-ise  (this config)
  vnet-ise-uks  10.10.0.0/16
    snet-ise-uks  10.10.1.0/24  ← permit-all NSG
      vm-dc-pri-uks    10.10.1.20  Windows Server 2022 DC (lab.com)
      vm-c8kv-pri-uks  10.10.1.30  Cisco C8000v (Gi1 — management)
                       10.10.1.31  Cisco C8000v (Gi2 — LAN)

rg-ise-pri-uks  (deployed separately)
  vnet-ise-uks  10.10.0.0/16  ← peered to rg-ise-sec-ukw
    ise-pri-uks  10.10.1.10  ISE 3.4 Primary (PAN + PSN + MnT)

rg-ise-sec-ukw  (deployed separately)
  vnet-ise-ukw  10.20.0.0/16  ← peered to rg-ise-pri-uks
    ise-sec-ukw  10.20.1.10  ISE 3.4 Secondary (PSN + MnT)
```

**Domain:** `lab.com` — hosted on `vm-dc-pri-uks` (10.10.1.20 as primary DNS)

**VNet peering:** `vnet-ise-uks` ↔ `vnet-ise-ukw` (non-transitive, configured manually)

## Resources Created by this Config

| Resource | Name | Notes |
|---|---|---|
| Resource Group | `rg-dev-smp-uks-ise` | |
| Virtual Network | `vnet-ise` | 10.10.0.0/16 |
| Subnet | `snet-ise` | 10.10.1.0/24 |
| Network Security Group | `permit-all` | Inbound scoped to `var.allowed_inbound_cidr` (default `VirtualNetwork`); outbound allowed (lab use) |
| Network Interface | `nic-dc-pri-uks` | Static 10.10.1.20 |
| Windows VM | `vm-dc-pri-uks` | Standard_B2ms, WS2022, AD DS |
| Network Interface | `nic-c8kv-gi1` | Static 10.10.1.30, IP forwarding on |
| Network Interface | `nic-c8kv-gi2` | Static 10.10.1.31, IP forwarding on |
| Linux VM | `vm-c8kv-pri-uks` | Cisco C8000v PAYG-essentials |
| Marketplace Agreement | Cisco C8000v | Accepted once per subscription |

## Prerequisites

- Azure subscription
- Terraform >= 1.5.0 (enforced by `required_version` in `providers.tf`)
- Azure CLI authenticated (`az login`)

## Usage

1. Clone the repo:
   ```bash
   git clone https://github.com/sjohnston1972/cisco-ise-dual_tacacs.git
   cd cisco-ise-dual_tacacs
   ```

2. Create `terraform.tfvars` (git-ignored -- never commit real secrets):
   ```hcl
   subscription_id      = "00000000-0000-0000-0000-000000000000"
   dc_admin_password    = "YourDCPassword-12+chars-3-of-4-complexity"
   c8kv_admin_password  = "YourC8KvPassword-12+chars-3-of-4-complexity"
   allowed_inbound_cidr = "203.0.113.4/32" # or leave the VirtualNetwork default
   ```
   Both passwords are validated at `plan` time: 12+ characters and at least
   3 of uppercase / lowercase / digit / special-character (Azure's VM
   password complexity rule). `c8kv_admin_password` additionally must not
   contain the admin username `ciscoadmin`.

3. Initialise and apply:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```
   This config uses local Terraform state by default. See "Remote State"
   below to opt into an Azure Storage backend instead.

## Variables

| Variable | Description | Default |
|---|---|---|
| `subscription_id` | Azure subscription ID to deploy into | *(required)* |
| `resource_group_name` | Resource group for created resources | `rg-dev-smp-uks-ise` |
| `location` | Azure region | `uksouth` |
| `dc_admin_password` | Windows DC admin password (sensitive, validated) | *(required)* |
| `c8kv_admin_password` | C8Kv admin password (sensitive, validated) | *(required)* |
| `allowed_inbound_cidr` | Source CIDR / service tag allowed inbound to the lab subnet (validated) | `VirtualNetwork` |

## Remote State (optional)

By default Terraform state is stored locally in `terraform.tfstate`
(git-ignored). That's fine for a single person on a single laptop, but it
gives no state locking, is easy to lose, and holds secrets in plaintext on
disk. For anything beyond solo/local use, switch to an `azurerm` (Azure
Storage) backend:

1. Create the storage account once, outside this config, so it can't
   accidentally delete its own state:
   ```bash
   az group create -n rg-tfstate -l uksouth
   az storage account create -n <globally-unique-name> -g rg-tfstate \
     -l uksouth --sku Standard_LRS --min-tls-version TLS1_2
   az storage container create -n tfstate --account-name <globally-unique-name>
   ```
2. Copy `backend.tf.example` to `backend.tf` (git-ignored, so real values
   never get committed) and fill in the storage account details, or leave
   the block empty and supply them via `-backend-config`:
   ```bash
   terraform init \
     -backend-config="resource_group_name=rg-tfstate" \
     -backend-config="storage_account_name=<globally-unique-name>" \
     -backend-config="container_name=tfstate" \
     -backend-config="key=cisco-ise-dual_tacacs.tfstate"
   ```
3. If you already have local state, `terraform init -migrate-state` moves
   it into the new backend.

Terraform reads whatever backend block is present at init time. CI never
copies `backend.tf` in, so it always runs `terraform init -backend=false`
and validates against the local/null backend -- no cloud credentials needed
just to lint and validate.

## Continuous Integration

`.github/workflows/terraform.yml` runs on every push and pull request:
`terraform fmt -check`, `terraform init -backend=false`, `terraform validate`,
[TFLint](https://github.com/terraform-linters/tflint), and
[Checkov](https://www.checkov.io/) (`checkov -d .`). It needs no Azure
credentials -- everything it checks is static analysis against the
configuration as written. Findings from TFLint/Checkov map to security and
style issues tracked separately in the issue tracker; CI surfaces them, it
doesn't fix them.

## Active Directory (lab.com)

The DC is configured with the following domain, groups, and users:

**Domain:** `lab.com`

| Group | Purpose |
|---|---|
| `ISE-Admins` | Full ISE GUI + SSH access, full switch privileges |
| `ISE-Network-RW` | Read-write access to network devices |
| `ISE-Network-RO` | Read-only access to network devices |

| User | Groups | Password |
|---|---|---|
| `labadmin@lab.com` | ISE-Admins, ISE-Network-RW | see `.env` |
| `labrw@lab.com` | ISE-Network-RW | see `.env` |
| `labro@lab.com` | ISE-Network-RO | see `.env` |
| `svc-ise@lab.com` | *(ISE join account)* | see `.env` |

ISE is joined to `lab.com` via `svc-ise@lab.com`. The AD identity source is named `lab.com` inside ISE.

## ISE Distributed Deployment

| Node | FQDN | Private IP | Public IP | Role |
|---|---|---|---|---|
| Primary | `ise-pri-uks.lab.com` | 10.10.1.10 | 51.11.154.165 | PAN + PSN + MnT |
| Secondary | `ise-sec-ukw.lab.com` | 10.20.1.10 | 51.11.106.43 | PSN + MnT |

Both nodes are registered in a single deployment; the secondary was registered from the primary node GUI under **Administration > System > Deployment**.

**ISE admin credentials:** `iseadmin` / see `.env`

### APIs enabled (on primary)

| API | Port | Auth |
|---|---|---|
| ERS API | 9060 | Basic auth |
| Open API | 443 `/api/v1/` | Session (Basic auth for GETs; session cookie for writes) |
| Device Administration Service | 443 | Enabled on both nodes |

## TACACS+ Device Administration Policy

Configured via ISE REST API (ERS + Open API). All policy lives in the **Default** Device Admin policy set.

### Shell Profiles

Located in ISE at:
`Work Centers > Device Administration > Policy Elements > Results > TACACS Profiles`

| Profile Name | Privilege Level | Assigned To |
|---|---|---|
| Profile Admin | 15 | ISE-Admins |
| Profile NetworkRW | 15 | ISE-Network-RW |
| Profile NetworkRO | 1 | ISE-Network-RO |
| Deny All Shell Profile | — | Default catch-all |

### Command Sets

Located in ISE at:
`Work Centers > Device Administration > Policy Elements > Results > TACACS Command Sets`

| Command Set | Permit Unmatched | Commands Defined | Assigned To |
|---|---|---|---|
| Commands-PermitAll | Yes | *(none — all permitted)* | ISE-Admins, ISE-Network-RW |
| Commands-PermitRO | No | show, ping, traceroute, exit | ISE-Network-RO |
| DenyAllCommands | No | *(none — all denied)* | Default catch-all |

### Authorization Policy

Located in ISE at:
`Work Centers > Device Administration > Device Admin Policy Sets`
→ Click the `>` arrow on the **Default** policy set row → **Authorization Policy**

| Rank | Rule Name | Condition | Shell Profile | Command Set |
|---|---|---|---|---|
| 0 | ISE-Admins | lab.com ExternalGroups = `lab.com/Users/ISE-Admins` | Profile Admin | Commands-PermitAll |
| 1 | ISE-Network-RW | lab.com ExternalGroups = `lab.com/Users/ISE-Network-RW` | Profile NetworkRW | Commands-PermitAll |
| 2 | ISE-Network-RO | lab.com ExternalGroups = `lab.com/Users/ISE-Network-RO` | Profile NetworkRO | Commands-PermitRO |
| Default | Default | *(catch-all)* | Deny All Shell Profile | DenyAllCommands |

### Authentication Policy

Located in ISE at:
`Work Centers > Device Administration > Device Admin Policy Sets`
→ **Default** policy set → **Authentication Policy**

| Rule | Identity Source |
|---|---|
| Default | `lab.com` (Active Directory) |

### Network Devices

Located in ISE at:
`Work Centers > Device Administration > Network Resources > Network Devices`

| Device Name | IP | TACACS Secret |
|---|---|---|
| C8Kv-Router | 10.10.1.30 | see `.env` |

## C8000v Router TACACS Configuration

Full dual-ISE TACACS config as deployed and tested:

```
tacacs server ISE-PRIMARY
 address ipv4 10.10.1.10
 key <tacacs-secret>
 timeout 3
!
tacacs server ISE-SECONDARY
 address ipv4 10.20.1.10
 key <tacacs-secret>
 timeout 3
!
aaa group server tacacs+ ISE-GROUP
 server name ISE-PRIMARY
 server name ISE-SECONDARY
!
aaa new-model
aaa authentication login default group ISE-GROUP local
aaa authorization exec default group ISE-GROUP if-authenticated
aaa authorization commands 1 default group ISE-GROUP if-authenticated
aaa authorization commands 15 default group ISE-GROUP if-authenticated
aaa accounting exec default start-stop group ISE-GROUP
!
line vty 0 4
 login authentication default
 authorization exec default
```

> **Note on local fallback:** `local` applies only to authentication. The `if-authenticated` keyword on authorization means exec/command authorization succeeds for any already-authenticated user — including local fallback users — without needing ISE to respond.

> **Note on username anonymisation:** ISE replaces failed-auth usernames with `INVALID` in TACACS Live Logs by default. Disable at `Administration > System > Settings > Security Settings` if you need to see the actual submitted username during debugging.

## TACACS+ Configuration Runbook

### Prerequisites

| Check | Command | Expected |
|---|---|---|
| Local priv-15 user exists | `show run \| include username` | `username <user> privilege 15 ...` |
| ISE Primary reachable | `ping 10.10.1.10 repeat 3` | 100% success |
| ISE Secondary reachable | `ping 10.20.1.10 repeat 3` | 100% success |

> **Before starting:** Open a second session or have Azure Serial Console ready (`vm-c8kv-pri-uks` → Help → Serial console).

### Step 1 — Define TACACS servers and AAA group
*No AAA impact.*
```
tacacs server ISE-PRIMARY
 address ipv4 10.10.1.10
 key <tacacs-secret>
 timeout 3
!
tacacs server ISE-SECONDARY
 address ipv4 10.20.1.10
 key <tacacs-secret>
 timeout 3
!
aaa group server tacacs+ ISE-GROUP
 server name ISE-PRIMARY
 server name ISE-SECONDARY
```

### Step 2 — Enable AAA framework
*No methods applied yet.*
```
aaa new-model
```

### Step 3 — Test both ISE nodes
*Do not proceed if either test fails.*
```
test aaa group ISE-GROUP labadmin <password> legacy
```
Expected: `User was successfully authenticated.`

To test secondary specifically:
```
tacacs server ISE-PRIMARY
 shutdown
!
test aaa group ISE-GROUP labadmin <password> legacy
!
tacacs server ISE-PRIMARY
 no shutdown
```

### Step 4 — Apply authentication and authorization methods
*Activates TACACS on all VTY lines immediately via the `default` method list.*
```
aaa authentication login default group ISE-GROUP local
aaa authorization exec default group ISE-GROUP if-authenticated
aaa authorization commands 1 default group ISE-GROUP if-authenticated
aaa authorization commands 15 default group ISE-GROUP if-authenticated
aaa accounting exec default start-stop group ISE-GROUP
```

### Step 5 — Make VTY assignment explicit and save
```
line vty 0 4
 login authentication default
 authorization exec default
!
end
write memory
```

### Rollback

#### Option A — SSH working (at least one ISE node up, or local fallback active)
```
configure terminal
 no aaa authentication login default group ISE-GROUP local
 no aaa authorization exec default group ISE-GROUP if-authenticated
 no aaa authorization commands 1 default group ISE-GROUP if-authenticated
 no aaa authorization commands 15 default group ISE-GROUP if-authenticated
 no aaa accounting exec default start-stop group ISE-GROUP
 no aaa new-model
 no aaa group server tacacs+ ISE-GROUP
 no tacacs server ISE-PRIMARY
 no tacacs server ISE-SECONDARY
 line vty 0 4
  no login authentication default
  no authorization exec default
end
write memory
```

#### Option B — Fully locked out
Azure Serial Console: Portal → `vm-c8kv-pri-uks` → **Help** → **Serial console**

Console auth uses the local database regardless of AAA (console line has no explicit AAA method assigned). Log in as the local user and run Option A.

### Key Behavioural Notes

| Scenario | Behaviour |
|---|---|
| Both ISE nodes up | Primary tried first, auth in ~100ms |
| Primary down, secondary up | 3s primary timeout, then secondary responds (~5s total) |
| Both ISE nodes down | Falls through to local after ~6s (3s × 2 timeouts) |
| ISE reachable, user not in AD | ISE returns explicit reject — local fallback does **not** trigger |
| Local user with ISE up | Denied — local users are unknown to ISE/AD |

---

## Test Results

**Date:** 2026-04-20 | **Device:** `vm-c8kv-pri-uks` (10.10.1.30)

### Read-Write Account (`labrw`)

| Test | Command | Result |
|---|---|---|
| Login | SSH | PASS |
| Privilege level | `show privilege` | PASS — Level **15** (Profile NetworkRW) |
| Show version | `show version \| include uptime` | PERMITTED |
| Show interfaces | `show ip interface brief` | PERMITTED |
| Show running config | `show running-config \| include hostname` | PERMITTED |
| Ping | `ping 10.10.1.10` | PERMITTED — 100% success |
| Enter config mode | `configure terminal` | PERMITTED |
| Save config | `write memory` | PERMITTED — `[OK]` |

**Verdict: PASS** — Full read and configuration access confirmed.

### Read-Only Account (`labro`)

| Test | Command | Result | Notes |
|---|---|---|---|
| Login | SSH | PASS | |
| Privilege level | `show privilege` | PASS | Level **1** (Profile NetworkRO) |
| Show version | `show version \| include uptime` | PERMITTED | |
| Show interfaces | `show ip interface brief` | PERMITTED | |
| Show running config | `show running-config \| include hostname` | DENIED | Requires priv 15 |
| Ping basic | `ping 10.10.1.10` | PERMITTED | |
| Ping extended | `ping 10.10.1.10 repeat 5` | DENIED | Extended ping requires priv 15 |
| Traceroute | `traceroute 10.10.1.10` | PERMITTED | |
| Enter config mode | `configure terminal` | DENIED | Requires priv 15 |
| Save config | `write memory` | DENIED | Requires priv 15 |

**Verdict: PASS** — Correctly restricted to read-only operations.

### ISE Failover Test

Primary ISE (`ise-pri-uks`, 10.10.1.10) stopped via Azure. All three accounts tested against secondary only.

| Account | Result | Login Time | Privilege |
|---|---|---|---|
| `labadmin` | PASS | 5.6s | 15 |
| `labrw` | PASS | 5.1s | 15 |
| `labro` | PASS | 5.1s | 1 |

~5 second failover time = 3s primary timeout + secondary response. Secondary socket opens confirmed incrementing in `show tacacs`.

**Verdict: PASS** — All accounts authenticate and receive correct privilege levels via secondary ISE.

### Issues Found During Testing

| Issue | Root Cause | Resolution |
|---|---|---|
| First failover test failed (all users denied) | `ISE-SECONDARY` was never added to the router config — initial setup only defined one server | Added `tacacs server ISE-SECONDARY` and added to `ISE-GROUP` |
| `labro` extended ping denied | IOS-XE `ping <ip> repeat <n>` requires priv 15 regardless of TACACS command set | Expected — basic `ping` works fine at priv 1 |
| `write memory` appeared to fail for `labrw` in first test pass | Command issued from inside `(config)#` mode — exec-only command | Test artifact only; confirmed working from exec mode |

---

## Notes

- `terraform.tfvars` and `.env` are excluded from version control
- The NSG's inbound rule is scoped by the `allowed_inbound_cidr` variable
  (default `"VirtualNetwork"`, an Azure service tag that limits inbound
  traffic to sources inside the VNet). Set it to a specific CIDR (e.g. your
  admin workstation's `/32`) to allow inbound access from outside the VNet.
  **Setting it to `"*"` re-opens the subnet to the entire Internet** — the
  variable's validation block rejects `"*"` and empty strings specifically
  to stop that from happening by accident, but the underlying rule still
  permits all ports/protocols from whatever source you do configure, so
  treat this as lab convenience, not a production-grade firewall.
- ISE first boot takes 15–20 minutes after VM creation
- The C8Kv marketplace agreement can be imported if already accepted:
  ```bash
  MSYS_NO_PATHCONV=1 terraform import azurerm_marketplace_agreement.c8kv \
    "/subscriptions/<sub-id>/providers/Microsoft.MarketplaceOrdering/agreements/cisco/offers/cisco-c8000v/plans/17_15_02a-payg-essentials"
  ```
