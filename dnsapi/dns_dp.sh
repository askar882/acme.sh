#!/usr/bin/env sh
# shellcheck disable=SC2034,SC2059,SC2181
dns_dp_info='DNSPod.cn
Site: DNSPod.cn
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_dp
Options:
 DP_Id Id
 DP_Key Key
'

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dp_add() {
  fulldomain=$1
  txtvalue=$2

  DP_Id="${DP_Id:-$(_readaccountconf_mutable DP_Id)}"
  DP_Key="${DP_Key:-$(_readaccountconf_mutable DP_Key)}"
  if [ -z "$DP_Id" ] || [ -z "$DP_Key" ]; then
    DP_Id=""
    DP_Key=""
    _err "You don't specify dnspod api key and key id yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable DP_Id "$DP_Id"
  _saveaccountconf_mutable DP_Key "$DP_Key"

  _debug "First detect the root zone."
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain."
    return 1
  fi

  add_record "$txtvalue"
}

#fulldomain txtvalue
dns_dp_rm() {
  fulldomain=$1
  txtvalue=$2

  DP_Id="${DP_Id:-$(_readaccountconf_mutable DP_Id)}"
  DP_Key="${DP_Key:-$(_readaccountconf_mutable DP_Key)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain."
    return 1
  fi

  if ! _rest "DescribeRecordList" "{\"Domain\":\"$_domain\"}"; then
    _err "DescribeRecordList error."
    return 1
  fi

  if _contains "$response" 'ResourceNotFound.NoDataOfRecord'; then
    _info "Don't need to remove."
    return 0
  fi

  record_id=$(echo "$response" | tr "{" "\n" | grep -- "$txtvalue" | _egrep_o "\"RecordId\":[0-9]*" | cut -d : -f 2)
  _debug record_id "$record_id"
  if [ -z "$record_id" ]; then
    _err "Can not get record id."
    return 1
  fi

  if ! _rest "DeleteRecord" "{\"Domain\":\"$_domain\",\"RecordId\":$record_id}"; then
    _err "DeleteRecord error."
    return 1
  fi

  ! _contains "$response" "Error"
}

#add the txt record.
#usage: txtvalue
add_record() {
  txtvalue=$1
  fulldomain="$_sub_domain.$_domain"

  _info "Adding record"

  if ! _rest "CreateTXTRecord" "{\"Domain\":\"$_domain\",\"RecordLine\":\"默认\",\"Value\":\"$txtvalue\",\"SubDomain\":\"$_sub_domain\"}"; then
    _err "CreateTXTRecord error."
    return 1
  fi

  _contains "$response" "RecordId" || _contains "$response" "InvalidParameter.DomainRecordExist"
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=88888888
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _rest "DescribeDomain" "{\"Domain\":\"$h\"}"; then
      return 1
    fi

    if _contains "$response" "DomainInfo"; then
      _domain_id=$(echo "$response" | _egrep_o "\"DomainId\":[0-9]*" | cut -d : -f 2)
      _debug _domain_id "$_domain_id"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf '%s' "$domain" | cut -d . -f 1-"$p")
        _debug _sub_domain "$_sub_domain"
        _domain="$h"
        _debug _domain "$_domain"
        return 0
      fi
      return 1
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage: action  payload
_rest() {
  action="$1"
  payload="$2"
  _debug "$action"

  service="dnspod"
  host="dnspod.tencentcloudapi.com"
  version="2021-03-23"
  algorithm="TC3-HMAC-SHA256"
  timestamp=$(date +%s)
  _debug "timestamp: $timestamp"
  date=$(date -u -d @"$timestamp" +"%Y-%m-%d")
  _debug "date: $date"

  # 1. Splice standard request string.
  http_request_method="POST"
  canonical_uri="/"
  canonical_querystring=""
  canonical_headers="content-type:application/json; charset=utf-8\nhost:$host\nx-tc-action:$(echo "$action" | awk '{print tolower($0)}')\n"
  signed_headers="content-type;host;x-tc-action"
  hashed_request_payload=$(printf "$payload" | openssl sha256 -hex | awk '{print $2}')
  canonical_request="POST\n$canonical_uri\n$canonical_querystring\n$canonical_headers\n$signed_headers\n$hashed_request_payload"
  _debug "canonical_request: $canonical_request"

  # 2. Splice string to be signed.
  credential_scope="$date/$service/tc3_request"
  hashed_canonical_request=$(printf "$canonical_request" | openssl sha256 -hex | awk '{print $2}')
  string_to_sign="$algorithm\n$timestamp\n$credential_scope\n$hashed_canonical_request"
  _debug "string_to_sign: $string_to_sign"

  # 3. Calculate signature.
  secret_date=$(printf "$date" | openssl sha256 -hmac "TC3$DP_Key" | awk '{print $2}')
  secret_service=$(printf $service | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_date" | awk '{print $2}')
  secret_signing=$(printf 'tc3_request' | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_service" | awk '{print $2}')
  signature=$(printf "$string_to_sign" | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_signing" | awk '{print $2}')
  _debug "signature: $signature"

  # 4. Splice Authorization header.
  authorization="$algorithm Credential=$DP_Id/$credential_scope, SignedHeaders=$signed_headers, Signature=$signature"
  _debug "authorization: $authorization"

  # 5. Initiate request.
  _debug2 payload "$payload"
  response="$(_H1="Authorization: $authorization" _H2="Host: $host" _H3="X-TC-Action: $action" _H4="X-TC-Timestamp: $timestamp" _H5="X-TC-Version: $version" _post "$payload" "https://$host" "" "" "application/json; charset=utf-8" | tr -d '\r')"

  if [ "$?" != "0" ]; then
    _err "Error in $action"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
