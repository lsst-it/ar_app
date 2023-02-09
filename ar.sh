#!/usr/bin/env bash
CREDENTIALS=credentials.ini
if [ -f "$CREDENTIALS" ]
then
  source $CREDENTIALS
else
  printf '%s' "No $CREDENTIALS file found, please check and try again"
  exit 0  
fi
rm -f $IPACOOKIEJAR
if [[ {$(curl -s --max-time 1 -I http://$IPAHOSTNAME) != 28} || {$(curl -s --max-time 1 -I http://$VPNHOSTNAME) != 28} ]]
then
  curl -s \
    -H referer:https://$IPAHOSTNAME/ipa  \
    -H "Content-Type:application/x-www-form-urlencoded" \
    -H "Accept:text/plain"\
    -c $IPACOOKIEJAR -b $IPACOOKIEJAR \
    --cacert $IPACACERT  \
    --data "user=$s_username&password=$s_password" \
    -X POST https://$IPAHOSTNAME/ipa/session/login_password
else
  printf '%s %s' "No connection to $IPAHOSTNAME or $VPNHOSTNAME detected"
  exit 0
fi
case "$1" in
  "ipa")
    case "$2" in
      "list")
        case "$3" in
          "all")
            IPAUSER_ARRAY=$(curl -s \
              -H referer:https://$IPAHOSTNAME/ipa  \
              -H "Content-Type:application/json" \
              -H "Accept:applicaton/json"\
              -c $IPACOOKIEJAR -b $IPACOOKIEJAR \
              --insecure \
              -d '{"id": 0,"method": "user_find/1","params": [[],{}]}' \
              -X POST https://$IPAHOSTNAME/ipa/session/json)
            IPAUSER=$(echo $IPAUSER_ARRAY | jq -r ".result.result[].uid" |sed -r '/[][]/d;s/"//g;s/[[:space:]]//g')
            printf '%s\n' ${IPAUSER[@]}
            ;;
          "block")
            IPAUSER_ARRAY=$(curl -s \
              -H referer:https://$IPAHOSTNAME/ipa  \
              -H "Content-Type:application/json" \
              -H "Accept:applicaton/json"\
              -c $IPACOOKIEJAR -b $IPACOOKIEJAR \
              --insecure \
              -d '{"id": 0,"method": "user_find/1","params": [[],{"nsaccountlock": true}]}' \
              -X POST https://$IPAHOSTNAME/ipa/session/json)
            IPAUSER=$(echo $IPAUSER_ARRAY | jq -r ".result.result[].uid" |sed -r '/[][]/d;s/"//g;s/[[:space:]]//g')
            printf '%s\n' ${IPAUSER[@]}
            ;;
          "active")
            IPAUSER_ARRAY=$(curl -s \
              -H referer:https://$IPAHOSTNAME/ipa  \
              -H "Content-Type:application/json" \
              -H "Accept:applicaton/json"\
              -c $IPACOOKIEJAR -b $IPACOOKIEJAR \
              --insecure \
              -d '{"id": 0,"method": "user_find/1","params": [[],{"nsaccountlock": false}]}' \
              -X POST https://$IPAHOSTNAME/ipa/session/json)
            IPAUSER=$(echo $IPAUSER_ARRAY | jq -r ".result.result[].uid" |sed -r '/[][]/d;s/"//g;s/[[:space:]]//g')
            printf '%s\n' ${IPAUSER[@]}
            ;;
          *)
            echo "Unknown sub-command"
            ;;
        esac
        ;;
    esac
    ;;
  "vpn")
    case "$2" in
      "connected"|"all")
        VPNUSER_ARRAY=$(curl -s -X GET \
          --insecure \
          --header "fauxapi-auth: $fauxapi_auth" \
          --header "Content-Type: application/json" \
          --data "{\"function\": \"openvpn_get_active_servers\"}" \
          "https://$VPNHOSTNAME/fauxapi/v1/?action=function_call") 
        VPNUSER=$(echo $VPNUSER_ARRAY | jq -r ".data.return[].conns[].common_name")
        printf '%s' "${VPNUSER[@]}"
        ;;&
      "blocked"|"all")
        IPAUSER_ARRAY=$(curl -s \
          -H referer:https://$IPAHOSTNAME/ipa  \
          -H "Content-Type:application/json" \
          -H "Accept:applicaton/json"\
          -c $IPACOOKIEJAR -b $IPACOOKIEJAR \
          --insecure \
          -d '{"id": 0,"method": "user_find/1","params": [[],{"nsaccountlock": true}]}' \
          -X POST https://$IPAHOSTNAME/ipa/session/json)
        IPAUSER=$(echo $IPAUSER_ARRAY | jq -r ".result.result | .[] | .uid" | sed -r '/[][]/d;s/"//g;s/[[:space:]]//g')
        for i in ${IPAUSER[@]}
        do
          for j in ${VPNUSER[@]}
          do
            echo $i | grep $j
          done
        done
        ;;
    esac
    ;;
  "block")
    if [ "$2" != "" ]
    then
      USER=$2
      case "$3" in
        "ipa"|"all")
          IPAUSER_BLOCK=$(curl -s \
            -H referer:https://$IPAHOSTNAME/ipa  \
            -H "Content-Type:application/json" \
            -H "Accept:applicaton/json"\
            --insecure \
            -c $IPACOOKIEJAR -b $IPACOOKIEJAR \
            -d "{\"id\": 0,\"method\": \"user_disable/1\", \"params\": [[\"$USER\"],{}]}" \
            -X POST https://$IPAHOSTNAME/ipa/session/json)
          if [[ $(echo $IPAUSER_BLOCK | grep 'AlreadyInactive') ]]
          then
            printf '\n%s\n' "User $USER is already blocked in IPA"
          else
            printf '\n%s\n' "User $USER Blocked from IPA"
          fi
          ;;&
        "vpn"|"all")
          VPNUSER_ARRAY=$(curl -s -X GET \
            --insecure \
            --header "fauxapi-auth: $fauxapi_auth" \
            --header "Content-Type: application/json" \
            --data "{\"function\": \"openvpn_get_active_servers\"}" \
            "https://$VPNHOSTNAME/fauxapi/v1/?action=function_call")
          read ID IP PORT < <(echo $VPNUSER_ARRAY | jq -r ".data.return[].conns[] | select(.common_name == \"$USER\")| \"\(.client_id) \(.remote_host)\"" | sed 's/:/ /g')
          read SERVER < <(echo $VPNUSER_ARRAY | jq -r ".data.return[].mgmt")
          if [[ -z $ID || -z $IP || -z $PORT || -z $SERVER ]]
          then
            printf '%s\n' "User $USER not connected to VPN"
          else
            VPNUSER_KILL=$(curl -s -X POST \
              --insecure \
              --header "fauxapi-auth: $fauxapi_auth" \
              --header "Content-Type: application/json" \
              --data "{\"function\": \"openvpn_kill_client\", \"args\": [\"$SERVER\", \"$IP\", \"$ID\"]}" \
              "https://$VPNHOSTNAME/fauxapi/v1/?action=function_call") 
            if [[ $(echo $VPNUSER_KILL | jq -r ".message") == "ok" ]]
            then
              printf '%s' "User $USER dropped VPN from $VPNHOSTNAME"
            else
              printf '%s' "Failed to drop VPN connection for User $USER"
            fi
          fi
          ;;
        *)
          echo "Unknown or missing sub-command"
          ;;
      esac
    else
      echo "Missing Username  ./bash_ar.sh block <username> vpn|ipa|all"
    fi
    ;;
  "help"|*)
    HELP='
    Usage: ./bash_ar.sh [options]
    
    list all|block|active        List IPA Users or List just the Active/Block ones
    vpn connected|blocked        List VPN Connected Users or the Connected that are Blocked in IPA
    block <username vpn|ipa|all>   Block <username> connection from VPN|IPA|Both '
    printf '%s' "$HELP"
    ;;
esac
