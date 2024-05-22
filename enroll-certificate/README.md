# SCEPman certificate renewal and enrollment scripts (beta)

Bash scripts enabling renewal and enrollment of certificates on linux machines using SCEPman.

## Enrollment script

Enrolls a certificate using SCEPman's CSR client, and sets up cronjobs to renew certificates.

NOTE: This script is not currently configured properly to be used in production for the following reasons:
1. Renewal script and config file are not stored in a sensible place - cronjobs currently expect the renewal script to stay in whichever directory the enrollment scripts are run from
2. There is not currently a role in SCEPman that allows users to enroll certificates to only themselves - users can either enroll any kind of certificate they wish or cannot enroll certificates at all. The engineering team is aware of this.
3. Generated keys are not encrypted

For testing it would (currently) probably be more straightforward to enroll a certificate from SCEPman Certificate Master and configure your own cronjob to run the renewal script regularly. Feel free to use this script as inspiration for what those cronjobs might look like. You may also want to look at using anacron as a possibility.

Before running you must:
- Create a new app registration in Azure portal. In Authentication, you'll have to add a "Mobile and desktop application" as a platform. This allows you to log on to Entra interactively as the application (when you attempt to enroll the certificate, a browser window will open asking you to authenticate). You will also have to go to the app registration SCEPman-api and visit "Expose an API". Under "Authorized client applications", you must add the client ID of the app registration just created.

Parameters:
1. SCEPman app service URL
2. API scope of SCEPman-api app registration
3. Client ID of the app registration created above
4. Tenant ID (of the tenant hosting SCEPman)
5. Desired name of certificate
6. Directory where certifcate will be installed
7. Directory where key will be installed
8. Root certificate

Example command:
```
sh enrollcertificate.sh https://your-scepman-domain.azurewebsites.net/ api://123guid 123-clientid-123  2323-tenantid-233 cert-name cert-directory key-directory root.pem
```

## Renewal script

Renews certificates using mTLS if they will expire within the threshold number of days.

NOTE: This script also does not encrypt the generated keys (this requires passphrase input)

Before running you must:
- Set the following application settings on the SCEPman app service.
    - AppConfig:DbCSRValidation:Enabled = true
    - AppConfig:DbCSRValidation:AllowRenewals = true
    - AppConfig:DbCSRValidation:ReenrollmentAllowedCertificateTypes = Static
    
Parameters:
1. SCEPman instance URL
2. Certificate to be renewed
3. Private key of certificate to be renewed
4. Root certificate
5. CSR config file
6. Renewal threshold: certificate will only renew if expiring in this (or less) many days

Example command:
```
sh renewcertificate.sh https://your-scepman-domain.net/ cert.pem cert.key root.pem openssl-conf.config 10
```
