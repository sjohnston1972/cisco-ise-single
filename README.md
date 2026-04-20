# cisco-ise-lab

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

**Domain:** `lab.com` — hosted on `vm-dc-pri-uks` (10.10.1.10 as primary DNS)

**VNet peering:** `vnet-ise-uks` ↔ `vnet-ise-ukw` (non-transitive, configured manually)

## Resources Created by this Config

| Resource | Name | Notes |
|---|---|---|
| Resource Group | `rg-dev-smp-uks-ise` | |
| Virtual Network | `vnet-ise` | 10.10.0.0/16 |
| Subnet | `snet-ise` | 10.10.1.0/24 |
| Network Security Group | `permit-all` | Allow all inbound/outbound (lab use) |
| Network Interface | `nic-dc-pri-uks` | Static 10.10.1.20 |
| Windows VM | `vm-dc-pri-uks` | Standard_B2ms, WS2022, AD DS |
| Network Interface | `nic-c8kv-gi1` | Static 10.10.1.30, IP forwarding on |
| Network Interface | `nic-c8kv-gi2` | Static 10.10.1.31, IP forwarding on |
| Linux VM | `vm-c8kv-pri-uks` | Cisco C8000v PAYG-essentials |
| Marketplace Agreement | Cisco C8000v | Accepted once per subscription |
| TLS Private Key | — | RSA 4096, written to `ise_private_key.pem` |

## Prerequisites

- Azure subscription
- Terraform >= 1.0
- Azure CLI authenticated (`az login`)

## Usage

1. Clone the repo:
   ```bash
   git clone https://github.com/sjohnston1972/cisco-ise-single.git
   cd cisco-ise-single
   ```

2. Create `terraform.tfvars`:
   ```hcl
   dc_admin_password   = "YourDCPassword"
   c8kv_admin_password = "YourC8KvPassword"
   ```

3. Initialise and apply:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Variables

| Variable | Description | Default |
|---|---|---|
| `resource_group_name` | Resource group for created resources | `rg-dev-smp-uks-ise` |
| `location` | Azure region | `uksouth` |
| `dc_admin_password` | Windows DC admin password (sensitive) | *(required)* |
| `c8kv_admin_password` | C8Kv admin password (sensitive) | *(required)* |

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
| `labadmin@lab.com` | ISE-Admins, ISE-Network-RW | `Cisco1234!` |
| `labrw@lab.com` | ISE-Network-RW | `Cisco1234!` |
| `labro@lab.com` | ISE-Network-RO | `Cisco1234!` |
| `svc-ise@lab.com` | *(ISE join account)* | `Cisco1234!` |

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
| Device Administration Service | 443 | Enabled on primary node |

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
| C8Kv-Router | 10.10.1.30 | `Cisco123` |

## C8000v Router TACACS Configuration

To enable TACACS authentication on the C8Kv, apply the following IOS-XE config:

```
aaa new-model
!
tacacs server ISE-PRIMARY
 address ipv4 10.10.1.10
 key Cisco123
!
aaa group server tacacs+ ISE-GROUP
 server name ISE-PRIMARY
!
aaa authentication login default group ISE-GROUP local
aaa authorization exec default group ISE-GROUP local
aaa authorization commands 1 default group ISE-GROUP local
aaa authorization commands 15 default group ISE-GROUP local
aaa accounting exec default start-stop group ISE-GROUP
aaa accounting commands 1 default start-stop group ISE-GROUP
aaa accounting commands 15 default start-stop group ISE-GROUP
!
line vty 0 4
 login authentication default
 authorization exec default
```

## Notes

- `terraform.tfvars` and `.env` are excluded from version control
- The permit-all NSG is intentional for this lab — do not use in production
- ISE first boot takes 15–20 minutes after VM creation
- The C8Kv marketplace agreement can be imported if already accepted:
  ```bash
  MSYS_NO_PATHCONV=1 terraform import azurerm_marketplace_agreement.c8kv \
    "/subscriptions/<sub-id>/providers/Microsoft.MarketplaceOrdering/agreements/cisco/offers/cisco-c8000v/plans/17_15_02a-payg-essentials"
  ```
