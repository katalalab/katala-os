#!/usr/bin/env bash

cli_dev_team_clean_detail() {
  tr '\n' ' ' \
    | sed -E 's#https://accounts\.google\.com/[^[:space:]]+#<redacted-google-oauth-url>#g; s#https?://[^[:space:]]*(access_token|refresh_token|id_token|code|session|auth)[^[:space:]]*#<redacted-auth-url>#Ig; s/(Bearer|Basic)[[:space:]]+[A-Za-z0-9._~+\/=-]+/\1 <redacted>/Ig; s/([A-Za-z_]*(TOKEN|KEY|SECRET|COOKIE|SESSION)[A-Za-z_]*=)[^[:space:]]+/\1<redacted>/Ig; s/code_challenge=[^&[:space:]]+/code_challenge=<redacted>/g; s/state=[^&[:space:]]+/state=<redacted>/g; s/[[:space:]]+/ /g; s/[[:cntrl:]]//g' \
    | cut -c 1-"${CLI_DEV_TEAM_REDACT_MAX_CHARS:-320}"
}

clean_detail() {
  cli_dev_team_clean_detail
}

cli_dev_team_sanitize_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  perl -0pi -e 's#https://accounts\.google\.com/\S+#<redacted-google-oauth-url>#g; s#https?://\S*(access_token|refresh_token|id_token|code|session|auth)\S*#<redacted-auth-url>#gi; s/(Bearer|Basic)\s+[A-Za-z0-9._~+\/=-]+/$1 <redacted>/gi; s/([A-Za-z_]*(TOKEN|KEY|SECRET|COOKIE|SESSION)[A-Za-z_]*=)\S+/$1<redacted>/gi; s/code_challenge=[^&\s]+/code_challenge=<redacted>/g; s/state=[^&\s]+/state=<redacted>/g' "$path"
}

sanitize_role_output() {
  cli_dev_team_sanitize_file "$@"
}
