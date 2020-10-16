#!/bin/bash

. `basename $0`.env

BACKUP_DIR="$(dirname "$0")/../data"
mkdir -p "$BACKUP_DIR"
BACKUP_KEEP_DAYS=7

BACK_LOG=$BACKUP_DIR/_00_dbbackup_all.log
TOTAL_MINS=0

echo `date` > $BACK_LOG

TIMESTAMP=`date +%Y%m%d_%H%M%S`

backupdb()
{
STARTD=`date +%s`

DBNAME=$1
DUMP_LOG=$BACKUP_DIR/_backup_${DBNAME}.log

echo "---------------------------------------------------------" >> $BACK_LOG
echo "`date` -- Starting backup of $DBNAME" >> $BACK_LOG

mkdir -p $BACKUP_DIR/$DBNAME
chown postgres:postgres $BACKUP_DIR/$DBNAME

sudo -u postgres pg_dump -Z 9 -F c $DBNAME > $BACKUP_DIR/$DBNAME/${DBNAME}_${TIMESTAMP}.custom

ENDD=`date +%s`
MINS=$(((($ENDD-$STARTD)/60)+1))
TOTAL_MINS=$(($MINS+$TOTAL_MINS))

find $BACKUP_DIR/$DBNAME/ -type f -ctime +$BACKUP_KEEP_DAYS -exec rm {} \;

echo "`date` - Finished in $MINS minutes:" >> $BACK_LOG
find $BACKUP_DIR/$DBNAME/ -type f -cmin -$MINS -exec du -sh {} \; >> $BACK_LOG
echo "---------------------------------------------------------" >> $BACK_LOG
}



awsStringSign4() {
  kSecret="AWS4$1"
  kDate=$(printf         '%s' "$2" | openssl dgst -sha256 -hex -mac HMAC -macopt "key:${kSecret}"     2>/dev/null | sed 's/^.* //')
  kRegion=$(printf       '%s' "$3" | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kDate}"    2>/dev/null | sed 's/^.* //')
  kService=$(printf      '%s' "$4" | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kRegion}"  2>/dev/null | sed 's/^.* //')
  kSigning=$(printf 'aws4_request' | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kService}" 2>/dev/null | sed 's/^.* //')
  signedString=$(printf  '%s' "$5" | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kSigning}" 2>/dev/null | sed 's/^.* //')
  printf '%s' "${signedString}"
}

s3upload_file() {

fileLocal="$1"
#fileRemote="${fileLocal}"
fileRemote="$2"
bucket="${S3UPLOAD_BUCKET}"
storageClass="STANDARD"  # or 'REDUCED_REDUNDANCY'
region="${S3UPLOAD_REGION}"
awsAccess="${S3UPLOAD_ACCESSKEY}"
awsSecret="${S3UPLOAD_SECRETKEY}"
awsURL="${S3UPLOAD_S3BASEURL}"

# Initialize defaults


#echo "Uploading" "${fileLocal}" "->" "${bucket}" "${region}" "${storageClass}"
#echo "| $(uname) | $(openssl version) | $(sed --version | head -1) |"

# Initialize helper variables

httpReq='PUT'
authType='AWS4-HMAC-SHA256'
service='s3'
baseUrl=".${service}.${awsURL}"
dateValueS=$(date -u +'%Y%m%d')
dateValueL=$(date -u +'%Y%m%dT%H%M%SZ')
if hash file 2>/dev/null; then
  contentType="$(file -b --mime-type "${fileLocal}")"
else
  contentType='application/octet-stream'
fi

# 0. Hash the file to be uploaded

if [ -f "${fileLocal}" ]; then
  payloadHash=$(openssl dgst -sha256 -hex < "${fileLocal}" 2>/dev/null | sed 's/^.* //')
else
  echo "File not found: '${fileLocal}'"
  exit 1
fi

# 1. Create canonical request

# NOTE: order significant in ${headerList} and ${canonicalRequest}

headerList='content-type;host;x-amz-content-sha256;x-amz-date;x-amz-server-side-encryption;x-amz-storage-class'

canonicalRequest="\
${httpReq}
/${fileRemote}

content-type:${contentType}
host:${bucket}${baseUrl}
x-amz-content-sha256:${payloadHash}
x-amz-date:${dateValueL}
x-amz-server-side-encryption:AES256
x-amz-storage-class:${storageClass}

${headerList}
${payloadHash}"

# Hash it

canonicalRequestHash=$(printf '%s' "${canonicalRequest}" | openssl dgst -sha256 -hex 2>/dev/null | sed 's/^.* //')

# 2. Create string to sign

stringToSign="\
${authType}
${dateValueL}
${dateValueS}/${region}/${service}/aws4_request
${canonicalRequestHash}"

# 3. Sign the string

signature=$(awsStringSign4 "${awsSecret}" "${dateValueS}" "${region}" "${service}" "${stringToSign}")

# Upload

curl -s -L --proto-redir =https -X "${httpReq}" -T "${fileLocal}" \
  -H "Content-Type: ${contentType}" \
  -H "Host: ${bucket}${baseUrl}" \
  -H "X-Amz-Content-SHA256: ${payloadHash}" \
  -H "X-Amz-Date: ${dateValueL}" \
  -H "X-Amz-Server-Side-Encryption: AES256" \
  -H "X-Amz-Storage-Class: ${storageClass}" \
  -H "Authorization: ${authType} Credential=${awsAccess}/${dateValueS}/${region}/${service}/aws4_request, SignedHeaders=${headerList}, Signature=${signature}" \
  "https://${bucket}${baseUrl}/${fileRemote}"

}



for db in `sudo -u postgres psql  -t -A -c 'SELECT datname FROM pg_database' | grep -v template`;do
	backupdb $db || curl -s -X POST -H 'Content-type: application/json' --data "{\"text\":\"db backup of $db at `hostname -f` failed\"}" $SLACK_HOOK >/dev/null
	s3upload_file $BACKUP_DIR/${db}/${db}_${TIMESTAMP}.custom `hostname -f`_`dmidecode -t 4 | grep ID | head -n 1 | sed 's/.*ID://;s/ //g'`/${db}/${db}_${TIMESTAMP}.custom || curl -s -X POST -H 'Content-type: application/json' --data "{\"text\":\"s3 upload of db backup of $db at `hostname -f` failed\"}" $SLACK_HOOK >/dev/null

done

