# SCEPman certificate renewal and enrollment scripts (beta)

Bash scripts enabling renewal and enrollment of certificates on linux machines using SCEPman.

## Enrollment script

Enrolls a certificate using SCEPman's CSR client, and sets up cronjobs to renew certificates.

NOTE: This script is not currently configured properly to be used in production for the following reasons:
1. There is not currently a role in SCEPman that allows users to enroll certificates to only themselves - users can either enroll any kind of certificate they wish or cannot enroll certificates at all. The engineering team is aware of this.
2. Generated RSA keys are not encrypted (unclear if there is a reasonable way to go about this)

For testing, it would (currently) probably be more straightforward to enroll a certificate from SCEPman Certificate Master and configure your own cronjob to run the renewal script regularly. Feel free to use this script as inspiration for what those cronjobs might look like. You may also want to look at using anacron as a possibility.

Before running you must:
- Create a new app registration in Azure portal. In Authentication, add a "Mobile and desktop application" as a platform. This allows you to log on to Entra interactively as the application (when you attempt to enroll the certificate, a browser window will open asking you to authenticate).
- Go to the app registration SCEPman-api and visit "Expose an API". Under "Authorized client applications", you must add the client ID of the app registration just created.

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

This script allows for the renewal of SCEPman-issued certificates using mTLS if they will expire within a threshold number of days. If this script were to be run regularly using Linux's Cron or Anacron utilities, it could allow for the automatic renewal of certificates on Linux devices.

Considerations: 
- This script does not encrypt the generated keys (this requires passphrase input, so has encryption has been omitted to allow for automatic renewal.)
- If you are renewing passphrase protected certificates from certificate master, you will need to input this passphrase in order to renew them.

Prerequisites:
- Set the following application settings on the SCEPman app service.
    - AppConfig:DbCSRValidation:Enabled = true
    - AppConfig:DbCSRValidation:AllowRenewals = true
    - AppConfig:DbCSRValidation:ReenrollmentAllowedCertificateTypes = Static
    
Parametetrs for the command:
1. SCEPman instance URL
2. Certificate to be renewed (name of PEM encoded certificate file)
3. Private key of certificate to be renewed (name of PEM encoded key file)
4. Root certificate (name of PEM encoded certificate file)
5. Renewal threshold (# of days): certificate will only renew if expiring in this (or less) many days

Example command:
```
sh renewcertificate.sh https://your-scepman-domain.net/ cert.pem cert.key root.pem 10
```
In order to facilitate automatic certificate renewal, you could use Linux's Cron utility to run this script regularly. This will cause the certificate to be renewed automatically once the current date is within the threshold number of days specified in the command. The below command will set up a cron job run the command daily (if the system is powered on) and a cron job to run the command on reboot. 
```
(crontab -l ; echo @daily renewcertificate.sh https://your-scepman-domain.net/ /path/to/cert.pem /path/to/cert.key /path/to/root.pem 10 ; echo @reboot renewcertificate.sh https://your-scepman-domain.net/ /path/to/cert.pem /path/to/cert.key /path/to/root.pem 10) | crontab -
```
(Since commands run by Cron will not necessarily be run from the directory that your certificates are in, it is important to provide the absolute paths to your certificates)
