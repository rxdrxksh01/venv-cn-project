# Phase 2 evidence index

Team .venv. Recorded on 24-25 November 2026, IST. Primary edge/DNS: 10.7.31.231;
Backend A: 10.7.1.112; Backend B/backup DNS/temporary standby: 10.7.2.240.
Screenshots are preserved from the team's live tests. Text transcripts are labeled
where supplied in chat rather than captured directly by a tool.

| Requirement | Evidence to open | Observed result |
|---|---|---|
| A: primary DNS failure | [Primary stopped](A-Backup-DNS/A1_primary_DNS_stopped.png), [client lookup](A-Backup-DNS/A2_client_uncached_lookup_primary_stopped.jpg), [backup query transcript](A-Backup-DNS/A3_backup_query_log_transcript.txt) | Client with two resolvers resolves api.team1.test after cache flush while primary is stopped; backup logs the non-healthcheck query |
| B: cached record and expiry | [Server changed answer](B-DNS-TTL/B1_server_changed_record_TTL30.png), [client sequence](B-DNS-TTL/B2_client_cached_old_then_new.jpg) | Server has new address while client still has old address; later client obtains new address |
| B: manual cache flush | [Server restoration](B-DNS-TTL/B3_server_record_restored_233634.png), [client flush](B-DNS-TTL/B4_client_manual_flush_233645.png), [timestamps](B-DNS-TTL/observed-results.txt) | Client primes at 23:36:31, server changes at :34, flushed client gets new answer at :45, before advertised 30-second TTL |
| C: Backend B isolation | [Blocked client and HTTPS success](C-Service-Isolation/C1_backend_B_client_blocked_HTTPS_allowed.png), [edge allowed](C-Service-Isolation/C2_backend_B_edge_direct_allowed.png), [counters](C-Service-Isolation/C3_backend_B_pf_counters.txt) | Edge can reach B; Bineet cannot directly; Bineet still reaches B over trusted HTTPS through nginx |
| C: Backend B rollback | [Direct access restored](C-Service-Isolation/C4_backend_B_rollback_client_direct_restored.png) | Bineet direct HTTP succeeds again |
| C: Backend A isolation | [Baseline PF](C-Service-Isolation/C5_backend_A_pf_before.png), [edge allowed](C-Service-Isolation/C6_backend_A_edge_direct_allowed.png), [rules](C-Service-Isolation/C7_backend_A_pf_enabled_rules.png), [counters](C-Service-Isolation/C8_backend_A_pf_counters.png), [results transcript](C-Service-Isolation/C10_backend_A_final_results.txt) | Edge allowed; Vridhi direct HTTP denied; trusted HTTPS restored after correcting Vridhi's resolver settings |
| C: Backend A rollback | [PF disabled after scoped rollback](C-Service-Isolation/C9_backend_A_rollback_pf_disabled.png), [direct-access result](C-Service-Isolation/C10_backend_A_final_results.txt) | Vridhi direct HTTP to A succeeds again |
| D: failover | [A stopped](D-Backend-Failover/D1_backend_A_stopped_B_serves_all.png) | Six HTTP 200 responses from B; initial upstream header shows A attempted then B retried |
| D: recovery | [A restarted](D-Backend-Failover/D2_backend_A_restarted_AB_rotation.png) | A/B rotation resumes, all six shown responses HTTP 200 |
| E: standby preparation | [Verified standby HTTPS](E-Edge-Migration/E1_standby_direct_TLS_verified_HTTP200.png), [standby setup](E-Edge-Migration/E2_standby_nginx_setup.png) | Standby configured on Vridhi :443 with trusted certificate; --resolve used only for preparation |
| E: DNS cutover | [Both DNS servers publish standby](E-Edge-Migration/E3_both_DNS_servers_publish_standby.png), [ordinary client transitions](E-Edge-Migration/E4_client_transitions_original_to_standby_HTTP200.png) | Client moves from edge-mac2/10.7.31.231 to edge-standby/10.7.2.240; all visible requests HTTP 200 |
| E: rollback | [Client back on original edge](E-Edge-Migration/E5_rollback_original_edge_HTTP200.png), [observations](E-Edge-Migration/observed-results.txt) | HTTP 200 from edge-mac2/10.7.31.231; standby stopped and Supportdesk restored, separately confirmed by user |
| F: rehearsal only | [Wrong-port diagnosis](F-Troubleshooting/F1_wrong_port_read_only_rehearsal.txt) | Both DNS servers resolve correctly; unused 8443 fails; trusted HTTPS on 443 succeeds. No configuration changed |

The actual faculty-injected fault and outcome remain pending. Append those results
after evaluation; do not present the rehearsal as the faculty challenge.

Timing limits: TTL was advertised as 30 seconds. Report the sampled client times,
not an invented exact expiry. The failed helper command visible in E3 did not
change DNS and is not a valid cutover timestamp. See E's observations transcript.

Phase 1 DNS/TCP/TLS packet capture remains under ../G-Packet-Capture/; it is
historical evidence with October addresses, not a new Phase 2 packet capture.
