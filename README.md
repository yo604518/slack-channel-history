# slack-channel-history

## Slackのログを標準出力に出力するスクリプト
====

## 前提
jqコマンドを(https://github.com/stedolan/jq)インストールしておいて下さい。

## 使い方
```
/bin/bash slack-channel-history.sh -u "SlackURL" -t "SlackToken" -c "Channel or Group"

SlackURL - SlackTeamのURL(ex. https://team.slack.com/)
SlackToken - Slackのトークン(ex. xoxp-****************-**********-*************-*******)
Channel or Group - ログ取得したいチャンネル名 or グループ名
``` 
