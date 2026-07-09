# Web / domain monitoring — RUM + CloudFront

Beyond the backend golden signals, this project also watches the **domain and the
portfolio site** from the user's side.

## CloudWatch RUM (real-user monitoring)

[`terraform/rum.tf`](../terraform/rum.tf) provisions a RUM app monitor for
`abheenash.com`, plus the Cognito identity pool + guest role the browser needs to send
events. A small snippet in the site's `<head>` collects, from real visitors:

- **Sessions & page views** — how many people, how often
- **Web-vitals performance** — real load times (not synthetic)
- **JavaScript errors** — client-side breakage
- **Link clicks** — via the DOM-event telemetry (`click` on `a` elements)

Guest access is least-privilege: the browser identity may only `rum:PutRumEvents` to this
one app monitor. See it in **CloudWatch → RUM → `abheenash-portfolio`**.

## CloudFront metrics

The dashboard adds a **Domain / web traffic** row — request volume and 4xx/5xx error rate
for both distributions (`abheenash.com` portfolio and `share.abheenash.com` app) from the
`AWS/CloudFront` namespace.

## Together

- **CloudFront** answers "how much traffic hit the edge?" (server-side).
- **RUM** answers "who actually used the site, how fast was it for them, and what did they
  click?" (real users, in-browser).

## Cost

RUM is ~$1 per 100k events; a portfolio's traffic keeps this to pennies. Cognito identity
pool is free. `session_sample_rate = 1` samples 100% — lower it if traffic ever grows.
