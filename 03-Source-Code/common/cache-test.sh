#!/bin/bash
# Task F / demo step 7: show Cache-Control + ETag, then a conditional request that returns 304.
source "$(dirname "$0")/../lib.sh"

URL="https://app.$DOMAIN/api/cached"
OUT="$EVIDENCE/taskF-caching.txt"
{
  echo "### 1) Full request — server sends the body plus Cache-Control and ETag"
  echo "\$ curl -sI $URL"
  curl -sI "$URL"

  ETAG=$(curl -sI "$URL" | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')

  echo "### 2) Conditional request — 'I already have version $ETAG, has it changed?'"
  echo "\$ curl -sI -H 'If-None-Match: $ETAG' $URL"
  curl -sI -H "If-None-Match: $ETAG" "$URL"
  echo "-> 304 Not Modified: headers only, no body. The client reuses its saved copy."
  echo
  echo "### 3) The load-balancing endpoint is deliberately NOT cacheable:"
  curl -sI "https://app.$DOMAIN/api/status" | grep -i -E '^(HTTP|cache-control|x-backend)'
} | tee "$OUT"
echo
echo "Saved to $OUT"
echo "Browser version: open https://app.$DOMAIN/api/cached, DevTools -> Network, reload:"
echo "  within 60s = '(disk cache)'/'(memory cache)'  (fresh hit, no request sent)"
echo "  after 60s  = 304                            (revalidated using If-None-Match)"
