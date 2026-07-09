# Screenshots — capture guide

This project's proof is visual, and the dashboard/alarms are private to the AWS account —
so screenshots are how it's shown. Capture these with the filenames below (the README and
`stage5.md` reference them). Re-run the drill anytime to get the live states.

| Filename | What to capture | Where |
|---|---|---|
| `01-dashboard-incident.png` | The golden-signals dashboard with the **5xx + throttle spike** (and the SLO dip) | CloudWatch → Dashboards → `sfs-obs-golden-signals` |
| `02-alarm-firing.png` | `sfs-obs-service-health` (or `sfs-obs-api-5xx`) in **red / In alarm** | CloudWatch → Alarms |
| `03-recovered.png` *(optional)* | The same alarm back to **OK** after recovery | CloudWatch → Alarms |
| `04-sns-email.png` *(optional)* | The alarm notification email from SNS | your inbox |

**To reproduce the incident state** (dashboard spike + red alarm):
```
aws lambda put-function-concurrency --function-name sfs-issue-url --reserved-concurrent-executions 0
# fire a few POST /files (they'll 503); wait ~1-2 min for the dashboard + alarm, screenshot, then:
aws lambda delete-function-concurrency --function-name sfs-issue-url
```

The metric spikes stay on the dashboard timeline for ~an hour, but the **red alarm state is
only live during the incident** — grab that one while it's firing.

Then: `git add docs/screenshots/*.png && git commit -m "docs: dashboard + alarm screenshots" && git push`
