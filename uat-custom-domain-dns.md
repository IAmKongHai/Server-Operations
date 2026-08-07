# icare.com.ph UAT Public-Facing Custom Domain — DNS Record Request Form

## 1. Records to Add

Each domain requires **two** records: a `CNAME` pointing to the Azure container and a `TXT` record for Azure to verify domain ownership.

### CNAME

| Hostname | Type | Value |
|---|---|---|
| `api-icare2-uat-ecom` | CNAME | `icare2-uat-ecom-api.victoriousglacier-592cbc74.southeastasia.azurecontainerapps.io` |
| `api-icare2-uat-sup` | CNAME | `icare2-uat-sup-api.victoriousglacier-592cbc74.southeastasia.azurecontainerapps.io` |
| `api-icare2-uat-app` | CNAME | `icare2-uat-app-api.victoriousglacier-592cbc74.southeastasia.azurecontainerapps.io` |
| `api-icare2-uat-hr` | CNAME | `icare2-uat-hr-api.victoriousglacier-592cbc74.southeastasia.azurecontainerapps.io` |
| `api-icare2-uat-map` | CNAME | `icare2-uat-map-api.victoriousglacier-592cbc74.southeastasia.azurecontainerapps.io` |
| `map-icare2-uat` | CNAME | `icare-2-uat-map-hshpeccddzb0fsbe.a01.azurefd.net` |
| `hr-icare2-uat` | CNAME | `icare-2-uat-hr-cuc4bthybhfzaqb6.a01.azurefd.net` |

### TXT (Domain Ownership Verification)

| Hostname | Type | Value |
|---|---|---|
| `asuid.api-icare2-uat-ecom` | TXT | `2C1A85F8270C45387E288405A72F87FDE567EFF2A683E7851E5250ECA02B3230` |
| `asuid.api-icare2-uat-sup` | TXT | Same as above |
| `asuid.api-icare2-uat-app` | TXT | Same as above |
| `asuid.api-icare2-uat-hr` | TXT | Same as above |
| `asuid.api-icare2-uat-map` | TXT | Same as above |
| `_dnsauth.map-icare2-uat` | TXT | _mu2dvq0in3p3sc8stjibf3tvahhn43y |
| `_dnsauth.hr-icare2-uat` | TXT | _htj11xdndnjjmxtwuwtmwc7f3pk6xor |

> The `asuid.` prefix is a fixed convention for Azure Container Apps, not a typo. This TXT value is the `customDomainVerificationId` of the external CAE `icare2-uat-cae-external`, shared by all apps under the same CAE.
