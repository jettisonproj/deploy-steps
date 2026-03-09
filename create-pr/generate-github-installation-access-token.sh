#!/bin/bash
#
# Exposes functions to generate the github installation access token
#
set -o errexit
set -o nounset
set -o pipefail


b64enc() {
  openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'
}


#
# Generate a JWT token
#
# Based off of: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app#example-using-bash-to-generate-a-jwt
generate-jwt() {
  local app_id="$1"
  local key_path="$2"

  pem=$( cat "${key_path}" )

  now=$(date +%s)
  iat=$((${now} - 60)) # Issues 60 seconds in the past
  exp=$((${now} + 600)) # Expires 10 minutes in the future


  # Header encode
  header_json='{ "typ":"JWT", "alg":"RS256" }'
  header=$( echo -n "${header_json}" | b64enc )

  # Payload encode
  payload_json='{ "iat":'"${iat}"', "exp":'"${exp}"', "iss":'"${app_id}"' }'
  payload=$( echo -n "${payload_json}" | b64enc )

  # Signature
  header_payload="${header}"."${payload}"
  signature=$(
    openssl dgst -sha256 -sign <(echo -n "${pem}") <(echo -n "${header_payload}") | b64enc
  )

  # Output JWT
  echo -n "${header_payload}"."${signature}"
}

#
# Generates a GitHub Installation Access Token
#
# Based off of: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app
generate-installation-access-token() {
  local app_id="$1"
  local key_path="$2"
  local repo_short="$3"


  JWT="$(generate-jwt "${app_id}" "${key_path}")"

  installation_id="$(
    curl \
      --silent \
      --show-error \
      --fail \
      --url "https://api.github.com/repos/${repo_short}/installation" \
      --header "Accept: application/vnd.github+json" \
      --header "Authorization: Bearer ${JWT}" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      | jq -re .id
  )"

  if [[ -z "${installation_id}" ]]; then
    echo "No installation id found" 1>&2
    return 1
  fi

  curl \
    --silent \
    --show-error \
    --fail \
    --request POST \
    --url "https://api.github.com/app/installations/${installation_id}/access_tokens" \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${JWT}" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    | jq -re .token
}
