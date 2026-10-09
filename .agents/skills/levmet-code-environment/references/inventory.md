# Reporting code environment inventory

Audit date: 9 October 2026. Source root: the reporting repository's `Code` folder.
594 source/configuration files were scanned without executing them. There are
86 distinct case-insensitive Windows variable names, of which 48 are managed
by this follow-up. Source locations below are relative to `Code`.

The complete allowlist and sample source references are in
[assets/code-environment.json](../../../../assets/code-environment.json).
Run `CodeEnvironment.cmd -Phase Audit` to refresh the full local inventory and
identify new names; it never automatically trusts an unknown name for export.

Database identity is read from the destination device setup. Sender/recipient
overrides are copied only if already configured or supplied explicitly; an
IAM email is not evidence of a verified sending identity.

Graph additionally needs a Windows Credential Manager entry, normally service
`ms_graph_secret` and user `RiskReports`, or the selectors configured in the
`MS_GRAPH_SECRET_*` variables. It is transferred separately from env values.

## Database and identity: derived on the destination

| Variable | Handling | Example source |
| --- | --- | --- |
| `LEVMET_DB_HOST` | Destination dbHost | `Mark Automations/spark-report/src/spark_report/db.py:16` |
| `LEVMET_DB_NAME` | Destination dbName | `Mark Automations/spark-report/src/spark_report/db.py:18` |
| `LEVMET_DB_PORT` | Destination dbPort | `Mark Automations/spark-report/src/spark_report/db.py:17` |
| `RISK_DB_URL` | Destination dbUrl | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:74` |
| `RISK_DB_USER` | Destination email | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:73` |
| `user_email` | Destination email | `GrandReport - SQL DB Migration.py:1366` |

## Paths: derive, rebase, or request a location

| Variable | Handling | Example source |
| --- | --- | --- |
| `LEVMET_ALL_TRADES_DIR` | {riskRoot}/All trades | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:61` |
| `LEVMET_BROKER_DIR` | {riskRoot}/FTP files | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:63` |
| `LEVMET_DOCS_ROOT` | {riskRoot} | `Mark Automations/spark-report/src/spark_report/paths.py:20` |
| `LEVMET_FEED_DIR` | {riskRoot}/LME Traders Report/RiskPack_feed | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:67` |
| `LEVMET_FX_HISTORY_CSV` | {riskRoot}/FTP files/prices/fx_daily.csv | `Mark Automations/power-var/src/levmet_power_var/settings.py:208` |
| `LEVMET_ICE_CREDENTIALS_JSON` | {oneDriveRoot}/Monaco - Documents/Risk Management/Pricing/json/logICE.json | `Mark Automations/power-var/src/levmet_power_var/settings.py:193` |
| `LEVMET_ICE_POWER_DIR` | {oneDriveRoot}/Monaco - Documents/Risk Management/VM/Risk/Scripts/Pricing/inputs | `Mark Automations/power-var/src/levmet_power_var/settings.py:180` |
| `LEVMET_ICE_SETTLEMENT_DIR` | {oneDriveRoot}/Monaco - Documents/Risk Management/Market Data/ICE_Settlements | `Mark Automations/power-var/src/levmet_power_var/settings.py:163` |
| `LEVMET_LIMITS_OVERLAY` | {codeRoot}/Mark Automations/limit-monitoring/src/levmet_risk/data/Limits Overlay - F Staal.xlsx | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:53` |
| `LEVMET_MAREX_DIR` | {oneDriveRoot}/Documents/Mark/Marex Risk Reporting Automation | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:31` |
| `LEVMET_ONEDRIVE_ROOT` | {oneDriveRoot} | `Mark Automations/power-var/src/levmet_power_var/settings.py:126` |
| `LEVMET_OUTPUT_DIR` | {codeRoot}/Mark Automations/limit-monitoring/output | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:46` |
| `LEVMET_POWER_VAR_CACHE` | {localAppData}/levmet_power_var/cache | `Mark Automations/power-var/src/levmet_power_var/settings.py:222` |
| `LEVMET_PRICES_DIR` | {riskRoot}/FTP files/prices | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:62` |
| `LEVMET_PRICE_ARCHIVE_DIR` | {riskRoot}/FTP files/prices | `Mark Automations/power-var/src/levmet_power_var/settings.py:152` |
| `LEVMET_RISK_PATHS` | {riskRoot} | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:30` |
| `LEVMET_TEMPLATE` | {codeRoot}/Mark Automations/limit-monitoring/src/levmet_risk/data/Levmet Risk Pack Template.xlsx | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:43` |
| `LEVMET_TRADERS_DICT` | {riskRoot}/Traders Dict/traders_dictionary.csv | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:64` |
| `LEVMET_TRADERS_DICT_DIR` | {riskRoot}/Traders Dict | `Mark Automations/IM-VaR-Plots/im_graph_by_trader.py:202` |
| `LEVMET_USER_ROOT` | {userProfile} | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:28` |

## Credentials: encrypted transfer or masked entry

| Variable | Handling | Example source |
| --- | --- | --- |
| `LEVMET_BROKER_SFTP_PASSWORD` | Present values only; report missing values | `Tools/Data_Marex.py:44` |
| `LEVMET_EMAIL_PASSWORD` | Present values only; report missing values | `risk_limits_reports/config.py:22` |
| `LEVMET_LEVGAS_EMAIL_PASSWORD` | Present values only; report missing values | `Tools/Data_Sucden_backup/Tools/T-2/PnLwAdj_new_test_t-2.py:1527` |
| `LEVMET_POSMON_EMAIL_PASSWORD` | Present values only; report missing values | `risk_limits_reports/Grouped Positions/positionmon_jn.py:154` |
| `SENDGRID_API_KEY` | Present values only; report missing values | `Tools/sendgrid_test.py:73` |

## Other settings: preserve configured values; otherwise retain code defaults

| Variable | Handling | Example source |
| --- | --- | --- |
| `LEVMET_EMAIL_FROM` | Existing/configured override or application default | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:136` |
| `LEVMET_EMAIL_RECIPIENTS` | Existing/configured override or application default | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:137` |
| `LEVMET_EMAIL_TEST_TO` | Existing/configured override or application default | `shared-email/src/levmet_email.py:251` |
| `LEVMET_INCLUDE_PHYSICAL` | Existing/configured override or application default | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:95` |
| `LEVMET_RBT_LIMITS_BOOKS_ONLY` | Existing/configured override or application default | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:87` |
| `LEVMET_STRESS_REDUCED` | Existing/configured override or application default | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:106` |
| `MORNING_LIMITS_PORT` | Existing/configured override or application default | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:114` |
| `MORNING_LIMITS_WARN_PCT` | Existing/configured override or application default | `Mark Automations/limit-monitoring/src/levmet_risk/settings.py:113` |
| `MS_GRAPH_CLIENT_ID` | Existing/configured override or application default | `ms_graph_mail.py:9` |
| `MS_GRAPH_SECRET_SERVICE` | Existing/configured override or application default | `ms_graph_mail.py:10` |
| `MS_GRAPH_SECRET_USER` | Existing/configured override or application default | `ms_graph_mail.py:11` |
| `MS_GRAPH_TENANT_ID` | Existing/configured override or application default | `ms_graph_mail.py:8` |
| `POSITION_CARDS_EMAIL_FROM` | Existing/configured override or application default | `Mark Automations/position-cards/position_cards/config.py:245` |
| `POSITION_CARDS_EMAIL_RECIPIENTS` | Existing/configured override or application default | `Mark Automations/position-cards/position_cards/config.py:250` |
| `PRICES_MAILER_ALERT_RECIPIENTS` | Existing/configured override or application default | `Mark Automations/prices-mailer/prices_mailer/config.py:142` |
| `PRICES_MAILER_EMAIL_FROM` | Existing/configured override or application default | `Mark Automations/prices-mailer/prices_mailer/config.py:132` |
| `PRICES_MAILER_EMAIL_RECIPIENTS` | Existing/configured override or application default | `Mark Automations/prices-mailer/prices_mailer/config.py:137` |

## Per-run options: do not persist during machine setup

| Variable | Handling | Example source |
| --- | --- | --- |
| `COMEX_173_OVERRIDE` | Caller chooses for each run | `Mark Automations/Spike Delta Arb/spike_broker_arb_morning_report.py:61` |
| `FORCE_MAREX` | Caller chooses for each run | `Mark Automations/Greeks/GG_options_scenarios.py:125` |
| `GREEKS_REPORT_DATE` | Caller chooses for each run | `Mark Automations/Greeks/options_greeks_engine.py:89` |
| `LEVGAS_WRITE_YTD` | Caller chooses for each run | `Trader Reports YTD-SQL-DB-Migration/traders/Levgas_automatic_report.py:614` |
| `MARGIN_REPORT_OVERRIDE_RECIPIENTS` | Caller chooses for each run | `Mark Automations/Margin Monitoring/margin_report_common.py:22` |
| `MARGIN_REPORT_SEND_EMAIL` | Caller chooses for each run | `Mark Automations/Margin Monitoring/margin_report_common.py:44` |
| `REPORT_DRY_RUN` | Caller chooses for each run | `Trader Reports YTD-SQL-DB-Migration/core/report_email.py:34` |
| `SPARK_DRY_RUN` | Caller chooses for each run | `Mark Automations/spark-report/src/spark_report/report.py:468` |
| `SPIKE_FORCE_MAREX` | Caller chooses for each run | `Mark Automations/Greeks/options_greeks_engine.py:417` |

## Windows and launcher variables: not machine configuration for this skill

| Variable | Handling | Example source |
| --- | --- | --- |
| `DATE` | OS or launcher owns this value | `Mark Automations/SHFE Arb Scraper/run_scraper.bat:3` |
| `ERRORLEVEL` | OS or launcher owns this value | `Mark Automations/Alex Fernandes FTP/run_alex_fernandes_ftp.bat:16` |
| `EXPECTED_USER` | OS or launcher owns this value | `Mark Automations/limit-monitoring/_venv_bootstrap.bat:25` |
| `INSTALL` | OS or launcher owns this value | `Mark Automations/limit-monitoring/_venv_bootstrap.bat:23` |
| `LOCALAPPDATA` | OS or launcher owns this value | `Mark Automations/power-var/src/levmet_power_var/settings.py:226` |
| `MACHINE_LABEL` | OS or launcher owns this value | `Mark Automations/limit-monitoring/_venv_bootstrap.bat:26` |
| `PYCMD` | OS or launcher owns this value | `Mark Automations/limit-monitoring/_venv_bootstrap.bat:60` |
| `PYTHONPATH` | OS or launcher owns this value | `Mark Automations/spark-report/run_spark_ingest.bat:8` |
| `PYTHONUTF8` | OS or launcher owns this value | `Mark Automations/Dalian Scraper/dalian_scraper.bat:3` |
| `P_DAYS` | OS or launcher owns this value | `Mark Automations/Spike Delta Arb/spike_broker_arb_morning_report.py:54` |
| `P_DAYS_HOLIDAY_ADJ` | OS or launcher owns this value | `Mark Automations/Spike Delta Arb/spike_broker_arb_morning_report.py:60` |
| `RC` | OS or launcher owns this value | `Mark Automations/Alex Fernandes FTP/run_alex_fernandes_ftp.bat:28` |
| `REBUILD` | OS or launcher owns this value | `Mark Automations/limit-monitoring/_venv_bootstrap.bat:22` |
| `REPO` | OS or launcher owns this value | `Mark Automations/limit-monitoring/_venv_bootstrap.bat:21` |
| `RES_HOLIDAY_ADJ` | OS or launcher owns this value | `Mark Automations/Spike Delta Arb/spike_broker_arb_morning_report.py:59` |
| `SCRIPT` | OS or launcher owns this value | `Mark Automations/Alex Fernandes FTP/run_alex_fernandes_ftp.bat:9` |
| `SUM_CM` | OS or launcher owns this value | `Mark Automations/Spike Delta Arb/spike_broker_arb_morning_report.py:55` |
| `TIME` | OS or launcher owns this value | `Mark Automations/SHFE Arb Scraper/run_scraper.bat:3` |
| `USERNAME` | OS or launcher owns this value | `Futures Prices Levgas Argus .py:515` |
| `VENV` | OS or launcher owns this value | `Mark Automations/limit-monitoring/_venv_bootstrap.bat:31` |
| `VENV_DIR` | OS or launcher owns this value | `Mark Automations/limit-monitoring/_venv_bootstrap.bat:21` |

## Application-local options: do not set globally

| Variable | Handling | Example source |
| --- | --- | --- |
| `DASH_BASE_PATH` | Application-local config/launch environment | `Mark Automations/power-var/src/levmet_power_var/dashboards/power_var_monitor/base_path.py:26` |
| `DB_URL` | Application-local config/launch environment | `Temp - RISK DASH APP/src/risk_dashboard/config/settings.py:55` |
| `ENVIRONMENT` | Application-local config/launch environment | `Temp - RISK DASH APP/src/risk_dashboard/config/settings.py:54` |
| `LOGGING` | Application-local config/launch environment | `Temp - RISK DASH APP/src/risk_dashboard/config/settings.py:61` |
| `PATHS` | Application-local config/launch environment | `Temp - RISK DASH APP/src/risk_dashboard/config/settings.py:59` |
| `PORT` | Application-local config/launch environment | `Mark Automations/power-var/src/levmet_power_var/dashboards/power_var_monitor/app.py:123` |
| `UI` | Application-local config/launch environment | `Temp - RISK DASH APP/src/risk_dashboard/config/settings.py:60` |

## Test-only options

| Variable | Handling | Example source |
| --- | --- | --- |
| `COPPER_MONITOR_REQUIRE_DATA` | Test fixture only | `copper_spread_monitor/tests/conftest.py:65` |

## Boundaries and unresolved source issues

- `LEVMET_DOCS_ROOT` means the same risk data root as `LEVMET_RISK_PATHS` in the spark package, not the Windows Documents folder.
- `LEVMET_ONEDRIVE_ROOT` has old-layout semantics. Do not set it to the Marex library and assume the Monaco/ICE subfolders exist. Use individual path overrides where necessary.
- `LEVMET_ICE_CREDENTIALS_JSON` is a file path; the file contents are outside this credential export.
- The temporary risk dashboard supports generic JSON env fields (`PATHS`, `UI`, `LOGGING`), a deployment label (`ENVIRONMENT`), and a `DB_URL` field alias. Those belong in that app's local config/launch environment. Its `RISK_DB_URL` is managed centrally.
- Python/SDK setup is separate from the reporting packages' dependencies, Excel/Bloomberg, permissions, and scheduled task configuration.
- The scan found a parse error in `Grandreport_split_metals_energy-LEV-MON-WKS-01.py:53`; literal accesses were still scanned. It also found a dynamic test helper in `shared-email/tests/test_mailer.py:27`.
- Audit records hardcoded legacy path locations for review. Environment setup cannot redirect a path that the source never reads from the environment.
