# mysqls3backup

install as:
```
mkdir /backup/bin -p
curl https://raw.githubusercontent.com/panosgeorgantas/mysqls3backup/master/mysqlbackup.sh -o /backup/bin/mysqlbackup.sh; chmod a+x /backup/bin/mysqlbackup.sh
echo `shuf -i 1-30 -n 1` 03 \* \* \* root /backup/bin/mysqlbackup.sh \>/dev/null > /etc/cron.d/mysqlbackup
```

and create the following file, appropriatly filled:
`/backup/bin/mysqlbackup.sh.env`
```
S3UPLOAD_BUCKET=
S3UPLOAD_REGION=
S3UPLOAD_ACCESSKEY=
S3UPLOAD_SECRETKEY=
S3UPLOAD_S3BASEURL=
SLACK_HOOK=
MYSQL_USER=
MYSQL_PASS=
```

# postgress3backup

install as:
```
mkdir /backup/bin -p
curl https://raw.githubusercontent.com/panosgeorgantas/mysqls3backup/master/postbackup.sh -o /backup/bin/postbackup.sh; chmod a+x /backup/bin/postbackup.sh
echo `shuf -i 1-30 -n 1` 03 \* \* \* root /backup/bin/postbackup.sh \>/dev/null > /etc/cron.d/postbackup
```

and create the following file, appropriatly filled:
`/backup/bin/postbackup.sh.env`
```
S3UPLOAD_BUCKET=
S3UPLOAD_REGION=
S3UPLOAD_ACCESSKEY=
S3UPLOAD_SECRETKEY=
S3UPLOAD_S3BASEURL=
SLACK_HOOK=
```
