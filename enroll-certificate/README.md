# SCEPman certificate renewal and enrolment scripts (beta)

Bash scripts enabling renewal and enrolment of certificates on linux machines using SCEPman.

## Enrolment script

To be documented

## Renewal script

Parameters:
1. SCEPman instance URL
2. Certificate to be renewed
3. Private key of certificate to be renewed
4. Root certificate
5. CSR config file
6. Renewal threshold: certificate will only renew if expiring in this many days

Example command:
```
sh renewcertificate.sh https://your-scepman-domain.net/ cert.pem cert.key root.pem opensslconf.config 10
```