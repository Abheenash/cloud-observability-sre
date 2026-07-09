# Canary source

`nodejs/node_modules/apiCanary.js` is the Synthetics canary handler.

The `nodejs/node_modules/` path is **required by AWS CloudWatch Synthetics** — for a Node.js
canary, the handler must live at exactly `nodejs/node_modules/<handler>.js` inside the zip.
This is **not** vendored npm dependencies (there are none) — it's a single hand-written file
in AWS's mandated layout. Terraform (`terraform/canary.tf`) zips this folder at apply time,
so it must be committed for a clean clone to `terraform apply`.
