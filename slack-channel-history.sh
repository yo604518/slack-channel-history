#!/bin/bash

# usage
function usage(){
    echo "USAGE: $0 -u SLACK_URL -t SLACK_TOKEN -c SLACK_CHANNEL or SLACK_GROUP"
    exit 1
}

# 引数チェック
while getopts :u:t:c: OPT
do
    case $OPT in
        u)    URL="$OPTARG"
              ;;
        t)    SLACK_TOKEN="$OPTARG"
              ;;
        c)    CHANNEL_NAME="$OPTARG"
              ;;

        :|\?) usage
              ;;
    esac
done
if [ $# -ne 6 ]; then
    usage
fi


# SlackAPIのグローバル変数
API_URL="${URL}/api"
CHANNEL_HISTORY_URL="${API_URL}/channels.history"
CHANNEL_INFO_URL="${API_URL}/channels.info"
CHANNEL_LIST_URL="${API_URL}/channels.list"
GROUP_HISTORY_URL="${API_URL}/groups.history"
GROUP_INFO_URL="${API_URL}/groups.info"
GROUP_LIST_URL="${API_URL}/groups.list"
USER_LIST_URL="${API_URL}/users.list"

# FUNCTION PART ###################################################################################################

# 対象チャンネルかパブリックかプライベートか判定
function is_public_or_private(){
    channel_id=$(
        curl -s -d "token=${SLACK_TOKEN}" ${CHANNEL_LIST_URL} \
            | jq -r ".channels[] | select(.name=="\"${CHANNEL_NAME}\"") | .id " 2>/dev/null
    )
    group_id=$(
        curl -s -d "token=${SLACK_TOKEN}" ${GROUP_LIST_URL} \
            | jq -r ".groups[] | select(.name=="\"${CHANNEL_NAME}\"") | .id " 2>/dev/null
    )
    if [ -n "${channel_id}" ];then
        echo "public"
    elif [ -n "${group_id}" ];then
        echo "private"
    fi
}

# パブリックチャンネル履歴の取得(最大1000件)
function get_channel_history(){
    channel_id=$(
        curl -s -d "token=${SLACK_TOKEN}" ${CHANNEL_LIST_URL} \
            | jq -r ".channels[] | select(.name=="\"${CHANNEL_NAME}\"") | .id " 
    )
    channel_history=$(
        curl -s -d "token=${SLACK_TOKEN}" -d "channel=${channel_id}" -d "count=1000" ${CHANNEL_HISTORY_URL} 
    )
    echo "${channel_history}"
}

# プライベートチャンネル履歴の取得(最大1000件)
function get_group_history(){
    group_id=$(
        curl -s -d "token=${SLACK_TOKEN}" ${GROUP_LIST_URL} \
            | jq -r ".groups[] | select(.name=="\"${CHANNEL_NAME}\"") | .id "
    )
    group_history=$(
        curl -s -d "token=${SLACK_TOKEN}" -d "channel=${group_id}" -d "count=1000" ${GROUP_HISTORY_URL} 
    )
    echo "${group_history}"
}

# チーム内の全ユーザー一覧の取得
function get_team_user_list(){
    user_list=$(curl -s -d "token=${SLACK_TOKEN}" ${USER_LIST_URL})
    while :; do
        if ! echo "${user_list}" | grep 'You are sending too many requests' >/dev/null 2>&1; then
            break
        fi
        sleep 1
        user_list=$(curl -s -d "token=${SLACK_TOKEN}" ${USER_LIST_URL})
    done
    echo "${user_list}"
}

# MAIN PROCESSING PART ###################################################################################################

# jqコマンドの存在確認
type -a 'jq' >/dev/null 2>&1
if [ ! $? -eq 0 ] ;then
    echo "jq comannd is not found!!"
    exit 1
fi

# チームの全ユーザー一覧を取得
team_user_json=$(get_team_user_list)
team_user_count=$(echo "${team_user_json}" | jq -r '.members | length')

# ユーザーID、ユーザー名を各配列に格納
team_user_id_array=()
while read -r t_user_id; do
    team_user_id_array+=("$t_user_id")
done < <(echo "${team_user_json}" | jq -r '.members[].id')

team_username_array=()
while read -r t_username; do
    team_username_array+=("$t_username")
done < <(echo "${team_user_json}" | jq -r '.members[].name')

# ユーザーID:ユーザー名の連想配列を作成
n=0
declare -A user
while [ ${n} -le ${team_user_count} ] ; do
    user[$(echo $team_user_id_array[$n])]="$(echo $team_username_array[$n])"
    let n++
done

# チャンネル履歴を取得
channel_type=$(is_public_or_private)
if [ "${channel_type}" = "public" ]; then
    history_json=$(get_channel_history)
elif [ "${channel_type}" = "private" ]; then
    history_json=$(get_group_history)
else
    echo "channel is not found!!"
    exit 1
fi

#　チャンネル履歴上のメンション(@ユーザー)を置換
l=$((${team_user_count}-1))
while [ ${l} -ge 0 ] ; do
    history_json=$(
        echo "${history_json}" \
            | sed s/"<@${team_user_id_array[${l}]}>"/"@${team_username_array[${l}]}"/g
    )
    let l--
done

# HTML特殊文字">","<"を置換
history_json=$(
    echo "${history_json}" \
        | sed s/'&gt;'/'>'/g
)
history_json=$(
    echo "${history_json}" \
        | sed s/'&lt;'/'<'/g
)

# チャンネル履歴を要素毎に各要素配列に格納
history_ts_array=()
while read -r timestamp; do
    history_ts_array+=("$timestamp")
done < <(echo "${history_json}" | jq -r '.messages[].ts' | xargs -I ts date -d "@ts" +"%Y/%m/%d %T")

history_user_array=()
while read -r huser; do
    history_user_array+=("$huser")
done < <(echo "${history_json}" | jq -r '.messages[].user')

history_username_array=()
while read -r husername; do
    history_username_array+=("$husername")
done < <(echo "${history_json}" | jq -r '.messages[].username')

history_text_array=()
while read -r htext; do
    history_text_array+=("$htext")
done < <(echo "${history_json}" | jq '.messages[].text')

# メッセージ履歴を標準出力へ
history_length=$(echo ${history_json} | jq '.messages|length')

m=$((${history_length}-1))
while [ ${m} -ge 0 ] ; do
    timestamp=$(echo "${history_ts_array[${m}]}")
    user_id=$(echo "${history_user_array[${m}]}")
    if [ "${user_id}" = "null" ]; then
        username=$(echo "${history_username_array[${m}]}")
    else
        username=$(echo ${user[${user_id}]})
    fi
    text=$(
        echo "${history_text_array[${m}]}" \
            | jq -r . \
            | sed s/^/'        '/g
    )

    echo "${timestamp}   =====  ${username}  ====="
    echo -e "${text}\n"

    let m--
done
