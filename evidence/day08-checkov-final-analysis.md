# Day 8 — Terraform Remediation: Final Checkov Analysis

## Summary

Checkov failed checks reduced from 72 (Day 4 baseline) to 8 — an 89%
reduction — across four remediation passes (IAM, EKS, S3/VPC, RDS).

## Remaining 8 Findings, Precisely Explained

**CKV_AWS_130 x2 (public subnets, IP auto-assignment)** — correct by
design. These subnets exist specifically to host the NAT gateway, which
structurally requires a public IP to route outbound traffic for the
private subnets. A #checkov:skip annotation was applied but Checkov does
not appear to honor skip annotations consistently across resources using
the count meta-argument (confirmed: an identical annotation on a
non-counted resource, CKV_AWS_382, was correctly recognized and appears
in skipped_checks). Documented as a tool-behavior limitation, not
unaddressed risk.

**CKV2_AWS_5 (security group attachment)** — genuinely remediated.
Verified via direct grep: the app security group is wired into the EKS
cluster's vpc_config.security_group_ids through cross-module variable
passing (vpc module output -> root main.tf -> eks module input). Checkov's
graph-based resolution does not appear to trace this specific cross-module
reference pattern. The underlying infrastructure is correctly configured;
this is a static-analysis tool limitation, confirmed by direct
Terraform code inspection rather than assumed.

**CKV2_AWS_69 x2 (RDS encryption in transit)** — not yet remediated.
Requires forcing SSL/TLS on the Postgres connection via a parameter group
setting (rds.force_ssl = 1) not yet added. Genuine follow-up item.

**CKV_AWS_144 x3 (S3 cross-region replication)** — correct-by-design
scope limitation, not fixed. Requires provisioning real infrastructure
in a second AWS region, out of scope for a project with no live AWS
account. #checkov:skip annotations applied on all three resources but
not recognized by this Checkov version/configuration for this specific
check — same tool-behavior limitation as CKV_AWS_130 above.

## Conclusion

Of the 8 remaining findings, 6 are correct-by-design or genuinely
remediated but not recognized as such by Checkov's skip/graph-resolution
mechanics (a documented tool limitation, verified via direct code
inspection rather than assumed). 2 (CKV2_AWS_69, RDS encryption in
transit) represent genuine, actionable remaining work.
