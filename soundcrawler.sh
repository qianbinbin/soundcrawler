#!/usr/bin/env sh

INFO=false
METADATA=true
COVER=true
INPUT_FILE=
OUT_DIR=$(realpath .)
TRANSCODING=mp3

URL_LIST=
CLIENT_ID=

THIN_LINE=$(printf '%.s-' $(seq 1 80))
THICK_LINE=$(printf '%.s=' $(seq 1 80))

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
    -t <transcoding>      specify a transcoding to download
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

curl_with_retry() {
  curl --retry 5 "$@"
}

error "==> Fetching client_id..."
CLIENT_ID=$(
  js_url=$(curl_with_retry -fsSL https://soundcloud.com | grep '<script crossorigin src=.\+></script>' | grep -o 'https.\+\.js' | tail -n 1)
  curl_with_retry -fsSL "$js_url" | grep -o '[^_]client_id:"[^"]\+' | head -n 1 | cut -c13-
)
if [ -z "$CLIENT_ID" ]; then
  error "client_id not found."
  exit 1
fi

TMP_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP_DIR"' EXIT

mime_to_ext() {
  if [ ! -f "$TMP_DIR/mime" ]; then
    curl_with_retry -fsSL https://raw.githubusercontent.com/mdn/content/main/files/en-us/web/http/basics_of_http/mime_types/common_types/index.md |
      grep '^| `' >"$TMP_DIR/mime"
  fi
  grep "$1" "$TMP_DIR/mime" | grep -o "\`\.[^\`]\+" | cut -c2-
}

download_track() {
  json=$1
  permalink=$(printf "%s\n" "$json" | jq -r '.permalink_url')
  _path=${permalink#*soundcloud.com}
  workdir="$TMP_DIR$_path"
  mkdir -p "$workdir"

  cover_url=$(printf "%s\n" "$json" | jq -r '.artwork_url // empty')
  _cover_url=$(printf "%s\n" "$cover_url" | sed 's/-large\.\(.\+\)$/-t500x500\.\1/')
  if curl_with_retry -fsSL -I "$_cover_url" | grep -i '^content-type:' | awk '{ print $2 }' | grep -qs '^image/'; then
    cover_url="$_cover_url"
  fi
  id=$(printf "%s\n" "$json" | jq -r '.id')
  title=$(printf "%s\n" "$json" | jq -r 'if .publisher_metadata.release_title then .publisher_metadata.release_title else .title // empty end')
  artist=$(printf "%s\n" "$json" | jq -r 'if .publisher_metadata.artist then .publisher_metadata.artist else .user.username // empty end')
  album=$(printf "%s\n" "$json" | jq -r '.publisher_metadata.album_title // empty')
  transcodings=$(printf "%s\n" "$json" | jq '.media.transcodings')

  if [ "$INFO" = true ]; then
    printf "%s\n" "$THICK_LINE"
    printf "  %-18s  %s\n" "Permalink" "$permalink"
    printf "  %-18s  %s\n" "ID" "$id"
    printf "  %-18s  %s\n" "Title" "$title"
    printf "  %-18s  %s\n" "Artist" "$artist"
    printf "  %-18s  %s\n" "Album" "$album"
    printf "  %-18s  %s\n" "Cover" "$cover_url"
    printf "%s\n" "$THIN_LINE"
    printf "  %-18s  %s\n" "Transcodings" "# Available formats and qualities"
    t_size=$(printf "%s\n" "$transcodings" | jq 'length')
    for i in $(seq 0 $((t_size - 1))); do
      t=$(printf "%s\n" "$transcodings" | jq ".[$i]")
      printf "%s\n" "$THIN_LINE"
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
    return 0
  fi

  error "$THICK_LINE"
  transcoding=$(
    _codec=$(printf "%s\n" "$TRANSCODING" | cut -d- -f1)
    _protocol=$(printf "%s\n" "$TRANSCODING" | awk -F- '{ print $2 }')
    [ -z "$_protocol" ] && _protocol=progressive
    printf "%s\n" "$transcodings" |
      jq ".[] | select((.preset | startswith(\"$_codec\")) and .format.protocol == \"$_protocol\")"
  )
  if [ -z "$transcoding" ]; then
    error "Transcoding not found, using default..."
    transcoding=$(printf "%s\n" "$transcodings" | jq '.[0]')
  fi

  auth=$(printf "%s\n" "$json" | jq -r '.track_authorization')
  dl_url=$(printf "%s\n" "$transcoding" | jq -r '.url')
  dl_url=$(curl_with_retry -fsSL "$dl_url?client_id=$CLIENT_ID&track_authorization=$auth\n" | jq -r '.url // empty')
  [ -z "$dl_url" ] && return 1
  filename=$(printf "%s\n" "$_path" | sed 's|^/||; s|-|_|g; s|/|-|g')
  codec=$(printf "%s\n" "$transcoding" | jq -r '.preset' | sed 's/_[0-9]\+_[0-9]\+$//')
  filename="$filename.$codec"
  protocol=$(printf "%s\n" "$transcoding" | jq -r '.format.protocol')

  error "==> Downloading '$filename'..."
  if [ "$protocol" = progressive ]; then
    curl_with_retry -fL -o "$workdir/$filename" "$dl_url" || return 1
  elif [ "$protocol" = hls ]; then
    curl_with_retry -fsSL "$dl_url" >"$workdir/m3u8" || return 1
    url_list=$(grep '^https\?://.\+$' "$workdir/m3u8")
    total=$(printf "%s\n" "$url_list" | wc -l | awk '{ print $1 }')
    part=0
    file_list=
    for u in $url_list; do
      curl_with_retry -fsSL -o "$workdir/$filename.$part" "$u" || return 1
      file_list="$file_list|$workdir/$filename.$part"
      : $((part += 1))
      printf "\r==> Downloading audio parts: %s/%s" "$part" "$total" >&2
    done
    printf "\n" >&2
    file_list=$(printf "%s\n" "$file_list" | cut -c2-)
    error "==> Merging audio parts..."
    ffmpeg -i "concat:$file_list" -c copy "$workdir/$filename" >/dev/null 2>&1 || return 1
  else
    error "Unknown protocol: '$protocol'"
    return 1
  fi

  if [ "$METADATA" = true ]; then
    error "==> Writing metadata..."
    ffmpeg -i "$workdir/$filename" \
      -metadata title="$title" -metadata artist="$artist" -metadata album="$album" \
      -c copy "$workdir/tmp.$filename" >/dev/null 2>&1 || return 1
    mv "$workdir/tmp.$filename" "$workdir/$filename"
  fi

  if [ "$COVER" = true ]; then
    error "==> Fetching cover art..."
    if [ "$codec" = opus ]; then
      error "Cover art for Opus not supported by ffmpeg, skipping..."
      error "See https://trac.ffmpeg.org/ticket/4448"
    else
      curl_with_retry -fsSL -o "$workdir/cover" "$cover_url" || return 1
      error "==> Writing cover art..."
      ffmpeg -i "$workdir/$filename" -i "$workdir/cover" -map 0 -map 1 \
        -c copy "$workdir/tmp.$filename" >/dev/null 2>&1 || return 1
      mv "$workdir/tmp.$filename" "$workdir/$filename"
    fi
  fi

  mv "$workdir/$filename" "$OUT_DIR"
  if [ -s "$OUT_DIR/$filename" ]; then
    error "$OUT_DIR/$filename"
  else
    error "Error happened when downloading '$filename'."
    return 1
  fi
  unset json
  rm -rf "$workdir"
}

for url in $URL_LIST; do
  url=${url%%#*}
  url=${url%%\?*}
  _p=${url#*soundcloud.com}
  if printf "%s\n" "$_p" | grep -qs '^/[^/]\+/[^/]\+$'; then
    error "==> Fetching track '$url'..."
    track_json=$(
      curl_with_retry -fsSL "$url" | grep -o '^<script>window\.__sc_hydration = .\+;</script>$' |
        grep -o '\[.\+\]' | jq '.[-1].data // empty'
    )
    if [ -z "$track_json" ]; then
      error "Cannot extract JSON, skipping..."
      continue
    fi
    download_track "$track_json"
    unset track_json
  elif printf "%s\n" "$_p" | grep -qs '^/[^/]\+/sets/[^/]\+$'; then
    error "==> Fetching set '$url'..."
    html=$(curl_with_retry -fsSL "$url")
    app_version=$(printf "%s\n" "$html" | grep -o '^<script>window.__sc_version="[[:digit:]]\+"</script>$' | grep -o '[[:digit:]]\+')
    set_json=$(printf "%s\n" "$html" | grep -o '^<script>window\.__sc_hydration = .\+;</script>$' | grep -o '\[.\+\]' | jq '.[-1].data // empty')
    unset html
    error "==> Fetching $(printf "%s\n" "$set_json" | jq -r '.track_count') track(s)..."

    initial_tracks=$(printf "%s\n" "$set_json" | jq '[.tracks[] | select(has("artwork_url"))]')
    id_list=$(printf "%s\n" "$set_json" | jq '.tracks[] | select(has("artwork_url") | not) | .id' | xargs -n 50 | tr ' ' ',')
    unset set_json
    # Do not use buggy `while read`
    # jq -c '.[]' | while IFS= read -r track
    # or for some reason you may lose first two characters: {"
    i_size=$(printf "%s\n" "$initial_tracks" | jq 'length')
    for i in $(seq 0 $((i_size - 1))); do
      download_track "$(printf "%s\n" "$initial_tracks" | jq ".[$i]")"
    done
    unset initial_tracks

    for ids in $id_list; do
      api_url="https://api-v2.soundcloud.com/tracks?ids=$ids&client_id=$CLIENT_ID&[object Object]=&app_version=$app_version&app_locale=en"
      additional_tracks=$(curl_with_retry -fsSL -g "$api_url")
      a_size=$(printf "%s\n" "$additional_tracks" | jq 'length')
      for i in $(seq 0 $((a_size - 1))); do
        download_track "$(printf "%s\n" "$additional_tracks" | jq ".[$i]")"
      done
      unset additional_tracks
    done
    unset id_list
  else
    error "Unknown URL: '$url', skipping..."
  fi
done

rm -rf "$TMP_DIR"
