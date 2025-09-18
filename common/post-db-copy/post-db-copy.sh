#!/bin/bash

# Abort if anything goes wrong.
set -e

# Flush drupal cache.
drush cr

# Run database updates.
drush updb --no-interaction

# Import configuration (twice).
drush cim --no-interaction
drush cim --no-interaction

# Sanitize the database (non-production only).
if [[ -v $AH_NON_PRODUCTION ]]; then
  drush sql-sanitize \
    --sanitize-email=%name@example.com \
    --sanitize-password=no
fi

# Flush drupal cache.
drush cr

# Get the current domain.
domain=$(drush php:eval "echo \Drupal::service('settings')->get('current_fqdn');")

# Flush varnish cache.
drush p:invalidate everything --uri="$domain" --no-interaction

# Read the API credentials from disk.
# @TODO: Refactor to jq when we don't have to support cloud classic.
cf_credentials="/mnt/gfs/$AH_SITE_NAME/nobackup/.cloudflare/credentials.json"

zone=$(python3 -c '
import json
import sys
with open("'"$cf_credentials"'", "r") as f:
  data = json.load(f)
sys.stdout.write(data.get("zoneid"))
'
)
email=$(python3 -c '
import json
import sys
with open("'"$cf_credentials"'", "r") as f:
  data = json.load(f)
sys.stdout.write(data.get("email"))'
)

apikey=$(python3 -c '
import json
import sys
with open("'"$cf_credentials"'", "r") as f:
  data = json.load(f)
sys.stdout.write(data.get("apikey"))'
)

# Flush CDN cache.
raw_result=$(curl -sX POST "https://api.cloudflare.com/client/v4/zones/$zone/purge_cache" \
  -H "X-Auth-Email: $email" \
  -H "X-Auth-Key: $apikey" \
  -H "Content-Type: application/json" \
  -d "{\"hosts\": [\"$domain\"]}")

result=$(python3 -c '
import json
import sys
data = json.loads('\'"$raw_result"\'')
sys.stdout.write(str(data.get("success")).lower())
')

[[ "$result" == "true" ]]