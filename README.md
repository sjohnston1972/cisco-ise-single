# cisco-ise-single

Terraform module to deploy a **Cisco ISE 3.4 standalone node** on Microsoft Azure.

## Overview

Deploys a single ISE VM into an existing Azure VNet/subnet using the Cisco ISE marketplace image. Designed for dev/test environments.

## Architecture

- Single standalone ISE node (PAN + PSN + MnT combined)
- Attached to a pre-existing VNet and subnet
- Public IP associated for management access
- NSG managed at the subnet level (not created by this module)
- First-boot configuration passed via Azure VM User Data

## Prerequisites

- Azure subscription with an existing resource group, VNet, subnet, public IP, and SSH key pair
- Cisco ISE marketplace terms accepted (or let Terraform accept them on first run)
- Terraform >= 1.0
- Azure CLI authenticated (`az login`)

## Resources Created

| Resource | Name |
|---|---|
| Network Interface | `vm-dev-smp-uks-ise-nic` |
| Linux Virtual Machine | `vm-dev-smp-uks-ise` |
| Marketplace Agreement | Cisco ISE 3.4 (accepted once per subscription) |

## Usage

1. Clone the repo:
   ```bash
   git clone https://github.com/sjohnston1972/cisco-ise-single.git
   cd cisco-ise-single
   ```

2. Create `terraform.tfvars` (not committed — contains sensitive values):
   ```hcl
   ise_password = "YourPassword"
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
| `resource_group_name` | Resource group for all created resources | `rg-dev-smp-uks-idm` |
| `location` | Azure region | `uksouth` |
| `ise_password` | ISE admin password (sensitive) | *(required)* |

## ISE First-Boot Configuration

ISE is configured at boot via Azure VM **User Data** (not custom data). The following parameters are passed:

```
hostname=vm-dev-smp-uks-ise
primarynameserver=8.8.8.8
dnsdomain=test.com
ntpserver=216.239.35.0
timezone=UTC
ersapi=no
openapi=no
pxGrid=no
pxgrid_cloud=no
```

> **Note:** ISE 3.4 requires a minimum of **16 vCPU / 32 GB RAM** for production use. The current VM size (`Standard_D4s_v3`) is suitable for evaluation/testing only.

## Notes

- `terraform.tfvars` is excluded from version control via `.gitignore`
- The marketplace agreement resource will error if terms are already accepted in the subscription — import it with:
  ```bash
  MSYS_NO_PATHCONV=1 terraform import azurerm_marketplace_agreement.ise \
    "/subscriptions/<sub-id>/providers/Microsoft.MarketplaceOrdering/agreements/cisco/offers/cisco-ise-virtual/plans/cisco-ise_3_4"
  ```
- ISE first boot takes 15–20 minutes; Azure provisioning timeouts from Terraform are expected and do not indicate a failed deployment
