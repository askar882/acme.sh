#!/bin/bash

_exists() {
  cmd="$1"
  if [ -z "$cmd" ]; then
    _usage "Usage: _exists cmd"
    return 1
  fi

  if eval type type >/dev/null 2>&1; then
    eval type "$cmd" >/dev/null 2>&1
  elif command >/dev/null 2>&1; then
    command -v "$cmd" >/dev/null 2>&1
  else
    which "$cmd" >/dev/null 2>&1
  fi
  ret="$?"
  echo "$cmd exists=$ret"
  return $ret
}
_readaccountconf_mutable() {
  echo
}
_saveaccountconf_mutable() {
  echo
}
_err() {
  echo "$@" >&2
  return 1
}
_info() {
  echo "$@"
}
_debug() {
  echo "$@"
}
_debug2() {
  echo "$@"
}
_contains() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub" >/dev/null 2>&1
}
_math() {
  _m_opts="$@"
  printf "%s" "$(($_m_opts))"
}
# body  url [needbase64] [POST|PUT|DELETE] [ContentType]
_post() {
  body="$1"
  _post_url="$2"
  needbase64="$3"
  httpmethod="POST"
  _postContentType="$5"
  _debug $httpmethod
  _debug "_post_url" "$_post_url"
  _debug2 "body" "$body"

  _debug "_CURL" "$_CURL"
  echo $_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "Content-Type: $_postContentType" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$_post_url"
  response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "Content-Type: $_postContentType" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$_post_url")"
  _ret="$?"
  if [ "$_ret" != "0" ]; then
    _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $_ret"
    if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
      _err "Here is the curl dump log:"
      _err "$(cat "$_CURL_DUMP")"
    fi
  fi
  _debug "_ret" "$_ret"
  printf "%s" "$response"
  return $_ret
}


DP_Id=''
DP_Key=''
txtdomain="_acme-challenge.example.com"
txt="_acme-challenge"
if [[ -f ".env" ]]; then
    source .env
fi

_CURL="curl"
USER_AGENT="acme.sh/3.1.0"
d_api="dnsapi/dns_dp.sh"
echo d_api "$d_api"

if ! . "$d_api"; then
  echo "Error loading file $d_api. Please check your API file and try again." >&2
  exit 1
fi
addcommand="dns_dp_add"
if ! _exists "$addcommand"; then
  echo "It seems that your API file is incorrect. Make sure it has a function named: $addcommand" >&2
  exit 1
fi
echo "Adding TXT value: $txt for domain: $txtdomain"
if ! $addcommand "$txtdomain" "$txt"; then
  echo "Error adding TXT record to domain: $txtdomain" >&2
  exit 1
fi
echo "The TXT record has been successfully added."
