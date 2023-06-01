#!/usr/bin/env sh

INFO=false
METADATA=true
COVER=true
INPUT_FILE=
OUT_DIR=$(realpath .)
TRANSCODING=mp3

URL_LIST=
CLIENT_ID=

error() { printf "%s\n" "$@" >&2; }

USAGE=$(
  cat <<-END
Usage: $0 [<options>] <url>...
Download tracks from SoundCloud.

    -i                    print media information instead of downloading media files (implies -M and -C)
    -M                    do NOT write metadata to media files
    -C                    do NOT write cover art to media files
    -I <file>             read URLs from file
    -o <dir>              set output directory
    -t <transcoding>      select transcoding to download
    -h                    display this help and exit

Home page: <https://github.com/qianbinbin/soundcrawler>
END
)

_exit() {
  error "$USAGE"
  exit 2
}

while getopts "iMCI:o:t:h" c; do
  case $c in
  i) INFO=true ;;
  M) METADATA=false ;;
  C) COVER=false ;;
  I) INPUT_FILE="$OPTARG" ;;
  o) OUT_DIR=$(realpath "$OPTARG") ;;
  t) TRANSCODING="$OPTARG" ;;
  h) error "$USAGE" && exit ;;
  *) _exit ;;
  esac
done

shift $((OPTIND - 1))

[ $# -ne 0 ] && URL_LIST=$*
[ -r "$INPUT_FILE" ] && URL_LIST="$URL_LIST $(cat "$INPUT_FILE")"
URL_LIST=$(
  for u in $URL_LIST; do
    if printf "%s\n" "$u" | grep -qs '^https://soundcloud.com/.\+$'; then
      printf "%s\n" "$u"
    else
      error "Unknown URL: '$u', skipping..."
    fi
  done
)

if [ -z "$URL_LIST" ]; then
  error "No URL provided."
  _exit
fi

if [ "$INFO" = true ]; then
  METADATA=false
  COVER=false
fi

if [ "$INFO" = false ] && { [ ! -d "$OUT_DIR" ] || [ ! -w "$OUT_DIR" ]; }; then
  error "Cannot write to directory: '$OUT_DIR'"
  exit 126
fi

exists() {
  command -v "$1" >/dev/null 2>&1
}

for c in curl jq; do
  if ! exists "$c"; then
    error "'$c' not found."
    exit 127
  fi
done

if [ "$INFO" = false ] && ! exists ffmpeg; then
  if [ "$METADATA" = true ] || [ "$COVER" = true ] || [ "$(printf "%s\n" "$TRANSCODING" | awk -F- '{ print $2 }')" = hls ]; then
    error "'ffmpeg' not found."
    error "Specify '-M -C -t mp3' to download without ffmpeg."
    exit 127
  fi
fi

error "Fetching client_id..."
CLIENT_ID=$(
  js_url=$(curl -fsSL https://soundcloud.com | grep '<script crossorigin src=.\+></script>' | grep -o 'https.\+\.js' | tail -n 1)
  curl -fsSL "$js_url" | grep -o '[^_]client_id:"[^"]\+' | head -n 1 | cut -c13-
)
if [ -z "$CLIENT_ID" ]; then
  error "client_id not found."
  exit 1
fi

TMP_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP_DIR"' EXIT

mime_to_ext() {
  if [ ! -f "$TMP_DIR/mime" ]; then
    curl -fsSL https://raw.githubusercontent.com/mdn/content/main/files/en-us/web/http/basics_of_http/mime_types/common_types/index.md |
      grep '^| `' >"$TMP_DIR/mime"
  fi
  grep "$1" "$TMP_DIR/mime" | grep -o "\`\.[^\`]\+" | cut -c2-
}

download_track() {
  _url=$1
  # Don't use "path", as "PATH" would be corrupted in some shells
  _path=${_url#*soundcloud.com}
  _path=${_path%%#*}
  _path=${_path%%\?*}
  workdir="$TMP_DIR$_path"
  mkdir -p "$workdir"

  curl -fsSL "$_url" >"$workdir/html" || return 1
  cover_url=$(grep -o '<img src=".\+>' "$workdir/html" | grep -o 'https[^"]\+')
  grep -o '^<script>window\.__sc_hydration = .\+;</script>$' "$workdir/html" |
    grep -o '\[.\+\]' | jq '.[-1].data' >"$workdir/json"

  id=$(jq -r '.id' "$workdir/json")
  title=$(jq -r 'if has(".publisher_metadata.release_title") then .publisher_metadata.release_title else .title end // empty' "$workdir/json")
  artist=$(jq -r '.publisher_metadata.artist // empty' "$workdir/json")
  album=$(jq -r '.publisher_metadata.album_title // empty' "$workdir/json")
  transcodings=$(jq '.media.transcodings' "$workdir/json")

  if [ "$INFO" = true ]; then
    printf "%-20s  %s\n" "ID" "$id"
    printf "%-20s  %s\n" "Title" "$title"
    printf "%-20s  %s\n" "Artist" "$artist"
    printf "%-20s  %s\n" "Album" "$album"
    printf "%-20s  %s\n" "Cover" "$cover_url"
    printf "%-20s  %s\n" "Transcodings" "# Available formats and qualities"
    printf "%s\n" "$transcodings" | jq -c '.[]' | while IFS= read -r t; do
      printf "\n"
      preset=$(printf "%s\n" "$t" | jq -r '.preset')
      mime=$(printf "%s\n" "$t" | jq -r '.format.mime_type')
      protocol=$(printf "%s\n" "$t" | jq -r '.format.protocol')
      quality=$(printf "%s\n" "$t" | jq -r '.quality')
      printf "  - %-18s%s\n" "Preset" "$preset"
      printf "    %-18s%s\n" "MIME type" "$mime"
      printf "    %-18s%s\n" "Protocol" "$protocol"
      printf "    %-18s%s\n" "Quality" "$quality"
      _t=$(printf "%s\n" "$preset" | sed 's/_[0-9]\+_[0-9]\+$//')
      [ "$protocol" != progressive ] && _t="$_t-$protocol"
      printf "  # %-18s$0 -t \033[7m%s\033[0m [<options>] <url>...\n" "Download with" "$_t"
    done
    printf "\n"
    return 0
  fi

  transcoding=$(
    _codec=$(printf "%s\n" "$TRANSCODING" | cut -d- -f1)
    _protocol=$(printf "%s\n" "$TRANSCODING" | awk -F- '{ print $2 }')
    [ -z "$_protocol" ] && _protocol=progressive
    printf "%s\n" "$transcodings" |
      jq ".[] | select((.preset | startswith(\"$_codec\")) and .format.protocol == \"$_protocol\")"
  )
  if [ -z "$transcoding" ]; then
    error "Transcoding not found, using default"
    transcoding=$(printf "%s\n" "$transcodings" | jq '.[0]')
  fi

  auth=$(jq -r '.track_authorization' "$workdir/json")
  dl_url=$(printf "%s\n" "$transcoding" | jq -r '.url')
  dl_url=$(curl -fsSL "$dl_url?client_id=$CLIENT_ID&track_authorization=$auth\n" | jq -r '.url')
  [ -z "$dl_url" ] && return 1
  filename=$(printf "%s\n" "$_path" | sed 's|^/||; s|-|_|g; s|/| - |g')
  codec=$(printf "%s\n" "$transcoding" | jq -r '.preset' | sed 's/_[0-9]\+_[0-9]\+$//')
  filename="$filename.$codec"
  protocol=$(printf "%s\n" "$transcoding" | jq -r '.format.protocol')

  error "Downloading '$filename'..."
  if [ "$protocol" = progressive ]; then
    curl -fL -o "$workdir/$filename" "$dl_url" || return 1
  elif [ "$protocol" = hls ]; then
    curl -fsSL "$dl_url" >"$workdir/m3u8" || return 1
    url_list=$(grep '^https\?://.\+$' "$workdir/m3u8")
    total=$(printf "%s\n" "$url_list" | wc -l | awk '{ print $1 }')
    part=0
    file_list=
    for u in $url_list; do
      curl -fsSL -o "$workdir/$filename.$part" "$u" || return 1
      file_list="$file_list|$workdir/$filename.$part"
      : $((part += 1))
      printf "\rDownloading audio parts: %s/%s" "$part" "$total" >&2
    done
    file_list=$(printf "%s\n" "$file_list" | cut -c2-)
    printf "\n" >&2
    error "Merging audio parts..."
    ffmpeg -i "concat:$file_list" -c copy "$workdir/$filename" >/dev/null 2>&1 || return 1
  else
    error "Unknown protocol: '$protocol'"
    return 1
  fi

  if [ "$METADATA" = true ]; then
    error "Writing metadata..."
    ffmpeg -i "$workdir/$filename" \
      -metadata title="$title" -metadata artist="$artist" -metadata album="$album" \
      -c copy "$workdir/tmp.$filename" >/dev/null 2>&1 || return 1
    mv "$workdir/tmp.$filename" "$workdir/$filename"
  fi

  if [ "$COVER" = true ]; then
    error "Writing cover art..."
    if [ "$codec" = opus ]; then
      error "Cover art for Opus not supported by ffmpeg, skipping..."
      error "See https://trac.ffmpeg.org/ticket/4448"
    else
      curl -fsSL -o "$workdir/cover" "$cover_url" || return 1
      ffmpeg -i "$workdir/$filename" -i "$workdir/cover" -map 0 -map 1 \
        -c copy "$workdir/tmp.$filename" >/dev/null 2>&1 || return 1
      mv "$workdir/tmp.$filename" "$workdir/$filename"
    fi
  fi

  mv "$workdir/$filename" "$OUT_DIR"
  rm -rf "$workdir"
}

for url in $URL_LIST; do
  download_track "$url"
done

rm -rf "$TMP_DIR"
