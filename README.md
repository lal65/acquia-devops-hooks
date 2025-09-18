# Acquia DevOps Hooks
This repository contains an implementation for the most basic deployment hooks
that are required to automate the various CI/CD operations for an Acquia-hosted
Drupal application.

Acquia also offers a product called
[Cloud Actions](https://docs.acquia.com/acquia-cloud-platform/manage-apps/cloud-actions)
which can usually provide mostly-equivalent functionality, but it has several
issues.

## Requirements
The domain(s) associated with the current Acquia environment are not easily
accessible in the continuous deployment execution environment. These hooks
require a special `$settings.php` element that fills the gap. The
`current_fqdn` setting must be present.  For example:

```php
  // @TODO: Acquia should provide a better way of accessing this information.
  $settings['current_fqdn'] = match($_ENV['AH_SITE_ENVIRONMENT']) {
    'dev' => 'dev.my-site.psu.edu',
    'test' => 'test.my-site.psu.edu',
    'prod' => 'my-site.psu.edu',
  };
```

## Installation
To install these cloud hooks into an application, use Composer to pull in the
repository and add symlinks from `./hooks/common/*/*` to the desired workflows.

For example, to enable the post-code-deploy workflow:

```bash
# Relative to the application project root
mkdir -p hooks/common/post-code-deploy
ln -s \
  ../../../vendor/lal65/acquia-devops-hooks/common/post-code-deploy/post-code-deploy.sh \
   hooks/common/post-code-deploy/000-post-code-deploy.sh
```

## Cloud Actions Limitations
Due to Acquia not recommending use of the Cloudflare module, the "Clear
external caches" Cloud Action cannot be used. Since Cloud Hooks cannot execute
after Cloud Actions, that means that for all intents and purposes,
post-deployment cloud actions cannot be used -- otherwise cache flushing would
happen out of order leading to stale caches.

Cloud Actions also come with a performance cost in that each individual cloud
action seems to take place in a distinct Kubernetes pod. While deployments are
running, the website goes into maintenance mode, so obviously the goal is to
minimize the time deployments take.

## Events that trigger workflows
The following events will invoke CI/CD workflows:
- **Code Deploys** - When a new code reference is deployed to an environment
- **Code Updates** - When a _branch_ is deployed to an environment and a commit is pushed to the branch
- **Database Copies** - When a database is copied into an environment
- **File Copies** - When files are copied into an environment

### Post-code-deploy
On post-code-deploy, the following operations are automatically performed:
- Run database updates
- Perform a configuration synchronization (twice <sup>[1]</sup>)
- Disable maintenance mode <sup>[2]</sup>
- Flush the Drupal cache
- Flush the Varnish cache
- If applicable, flush the CDN cache <sup>[3]</sup>

Note that in this workflow, an initial drupal cache flush is not performed. It
is recommended to utilize a pre-deployment Cloud Action to perform a cache
flush before the post-deploy workflow runs on the new pod.

### Post-code-update
On post-code-deploy, the following operations are automatically performed:
- Flush drupal caches
- Run database updates
- Perform a configuration synchronization (twice <sup>[1]</sup>)
- Flush the Drupal cache
- Flush the Varnish cache
- If applicable, flush the CDN cache <sup>[2]</sup>

### Post-database-copy
- Flush drupal caches
- Run database updates
- Perform a configuration synchronization (twice <sup>[1]</sup>)
- Sanitize the database (if not on a production environment)
- Flush the Drupal cache
- Flush the Varnish cache
- If applicable, flush the CDN cache <sup>[2]</sup>

### Post-files-copy
- Flush drupal caches
- Flush the Varnish cache
- If applicable, flush the CDN cache <sup>[2]</sup>

### Optional CDN Purging
The Cloudflare CDN can be configured to be auto-purged by placing a
configuration file in a specific place on the Acquia environment disk.

[Storing private information in the file system](https://docs.acquia.com/acquia-cloud-platform/storing-private-information-file-system)
outlines how to use the `nobackup` directory to securely store certain
credentials.  To enable CDN purging, simply add a file at
`/mnt/gfs/$AH_SITE_NAME/nobackup/.cloudflare/credentials.json` on each
environment that should have CDN purging enabled on it. The contents of this
configuration file should match this format:

```json
{
  "email": "your-cloudflare-service-account-user@psu.edu",
  "apikey": "your cloudflare service account api key",
  "zoneid": "your cloudflare zone id"
}
```

<sup>[1]</sup> Some configuration changes require two synchronizations.  For
example, if configuration split or ignore settings are modified.

<sup>[2]</sup> The pre-code-deployment Cloud Action may have been configured
to enable maintenance mode before deploying the new Kubernetes pod.

<sup>[3]</sup> At this time only the Cloudflare CDN is supported.
