# Third-party software

Third-party files remain under their original licenses. The setup scripts do not
relicense them. Distribution archives retain their bundled license files; JARs
retain their original `META-INF` license/notice resources.

| Component | Included version | Source and license information |
| --- | --- | --- |
| Google Cloud CLI and bundled Python | 583.0.0 | [Google Cloud SDK](https://cloud.google.com/sdk); bundled `LICENSE` and component licenses |
| Cloud SQL Auth Proxy | 2.26.0 | [GoogleCloudPlatform/cloud-sql-proxy](https://github.com/GoogleCloudPlatform/cloud-sql-proxy), Apache-2.0 |
| DBeaver Community and JRE | 26.2.0 | [dbeaver/dbeaver](https://github.com/dbeaver/dbeaver), Apache-2.0 and bundled dependency/JRE licenses |
| Codex CLI and companion tools | 0.155.0-alpha.16.3 | [openai/codex](https://github.com/openai/codex), Apache-2.0; CLI binaries from the installed official extension, with Apache license included |
| ripgrep (Codex companion) | Included with Codex | [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep), MIT/Unlicense |
| PostgreSQL JDBC | 42.7.11 | [pgjdbc](https://github.com/pgjdbc/pgjdbc), BSD-2-Clause |
| PostGIS JDBC / geometry | 2.5.0 | [postgis-java](https://github.com/postgis/postgis-java), LGPL-2.1-or-later |
| Waffle JNA | 3.5.1 | [waffle](https://github.com/Waffle/waffle), EPL-1.0 |
| JNA / JNA platform | 5.16.0 | [jna](https://github.com/java-native-access/jna), LGPL-2.1-or-later / Apache-2.0 |
| SLF4J API / JCL bridge | 2.0.16 | [slf4j](https://github.com/qos-ch/slf4j), MIT |
| Caffeine | 3.1.8 | [caffeine](https://github.com/ben-manes/caffeine), Apache-2.0 |
| Checker annotations | 3.48.3 | [checker-framework](https://github.com/typetools/checker-framework), annotation licenses in the original JAR |
| Error Prone annotations | 2.21.1 | [error-prone](https://github.com/google/error-prone), Apache-2.0 |

`assets/certificates/MarexRootAndTrustedSites.cer` is the IT-supplied public CA
bundle used by the working Marex/Levmet setup. It contains public certificates
only, no private key. Keep its distribution within the authorized team and obtain
updates from IT.
