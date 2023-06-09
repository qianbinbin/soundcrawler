#!/usr/bin/env sh

INFO=false
METADATA=true
COVER=true
INPUT_FILE=
INPUT_FILE_SET=false
OUT_DIR=$(realpath .)
TRANSCODING=mp3
TRANSCODING_SET=false

URL_LIST=
CLIENT_ID=

THIN_LINE=$(printf '%.s-' $(seq 1 80))
THICK_LINE=$(printf '%.s=' $(seq 1 80))

error() { printf "%s\n" "$@" >&2; }

USAGE=$(
  cat <<-END
Usage: $0 [<options>] <url>...
Download tracks from SoundCloud.

    -i                    print media information instead of downloading the files
    -M                    do NOT write metadata to media files
    -C                    do NOT write cover art to media files
    -I <file>             read URLs from file
    -o <dir>              set the output directory
    -t <transcoding>      specify a transcoding to use when downloading
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
  I)
    INPUT_FILE="$OPTARG"
    INPUT_FILE_SET=true
    ;;
  o) OUT_DIR=$(realpath "$OPTARG") ;;
  t)
    TRANSCODING="$OPTARG"
    TRANSCODING_SET=true
    ;;
  h) error "$USAGE" && exit ;;
  *) _exit ;;
  esac
done

shift $((OPTIND - 1))

[ $# -ne 0 ] && URL_LIST=$*

if [ "$INPUT_FILE_SET" = true ] && { [ ! -f "$INPUT_FILE" ] || [ ! -r "$INPUT_FILE" ]; }; then
  error "Cannot access file: '$INPUT_FILE'."
  exit 1
fi

if [ -z "$URL_LIST" ] && [ "$INPUT_FILE_SET" = false ]; then
  error "No URL provided."
  _exit
fi

if [ "$INFO" = false ] && { [ ! -d "$OUT_DIR" ] || [ ! -w "$OUT_DIR" ]; }; then
  error "Cannot write to directory: '$OUT_DIR'."
  exit 1
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

# Run in subshell
# Do NOT call it with 'if', '||', etc. so that 'set -e' can work.
download_track() (
  set -e
  json=$1
  permalink=$(printf "%s\n" "$json" | jq -r '.permalink_url // empty')
  _path=${permalink#*soundcloud.com}
  workdir="$TMP_DIR$_path"
  mkdir -p "$workdir"

  cover_url=$(printf "%s\n" "$json" | jq -r 'if .artwork_url then .artwork_url else .user.avatar_url // empty end')
  if [ -n "$cover_url" ]; then
    _cover_url=$(printf "%s\n" "$cover_url" | sed 's/-large\.\(.\+\)$/-t500x500\.\1/')
    if curl_with_retry -fsSL -I "$_cover_url" | grep -i '^content-type:' | awk '{ print $2 }' | grep -qs '^image/'; then
      cover_url="$_cover_url"
    fi
  fi
  id=$(printf "%s\n" "$json" | jq -r '.id // empty')
  title=$(printf "%s\n" "$json" | jq -r 'if .publisher_metadata.release_title then .publisher_metadata.release_title else .title // empty end')
  artist=$(printf "%s\n" "$json" | jq -r 'if .publisher_metadata.artist then .publisher_metadata.artist else .user.username // empty end')
  album=$(printf "%s\n" "$json" | jq -r '.publisher_metadata.album_title // empty')
  transcodings=$(printf "%s\n" "$json" | jq '.media.transcodings // []')

  if [ "$INFO" = true ]; then
    printf "%s\n" "$THICK_LINE"
    printf "  %-18s  %s\n" "Permalink" "$permalink"
    printf "  %-18s  %s\n" "ID" "$id"
    printf "  %-18s  %s\n" "Title" "$title"
    printf "  %-18s  %s\n" "Artist" "$artist"
    printf "  %-18s  %s\n" "Album" "$album"
    printf "  %-18s  %s\n" "Cover Art" "$cover_url"
    printf "%s\n" "$THIN_LINE"
    printf "  %-18s  %s\n" "Transcodings" "# Available formats and qualities"
    printf "%s\n" "$transcodings" | jq -c '.[]' | while read -r t; do
      printf "%s\n" "$THIN_LINE"
      preset=$(printf "%s\n" "$t" | jq -r '.preset // empty')
      mime=$(printf "%s\n" "$t" | jq -r '.format.mime_type // empty')
      protocol=$(printf "%s\n" "$t" | jq -r '.format.protocol // empty')
      quality=$(printf "%s\n" "$t" | jq -r '.quality // empty')
      printf "  - %-18s%s\n" "Preset" "$preset"
      printf "    %-18s%s\n" "MIME Type" "$mime"
      printf "    %-18s%s\n" "Protocol" "$protocol"
      printf "    %-18s%s\n" "Quality" "$quality"
      transcoding=$(printf "%s\n" "$preset" | sed 's/_.\+$//')
      if [ -n "$transcoding" ]; then
        [ "$protocol" != progressive ] && transcoding="$transcoding-$protocol"
        printf "  # %-18s$0 -t \033[7m%s\033[0m [<options>] <url>...\n" "Download With" "$transcoding"
      fi
    done
    return 0
  fi

  # Assume that for the specific song, all presets of the same codec are the same, e.g.
  # - mp3_0_0 mp3_0_0 opus_0_0
  # - mp3_0_1 mp3_0_1 opus_0_0
  # - mp3_1_0 mp3_1_0 opus_0_0
  # - mp3_standard mp3_standard opus_0_0
  # So we simply get rid of the confusing "_.+" and just take the leading codec string.
  error "$THICK_LINE"
  error "==> Downloading '$permalink'..."
  transcoding=$(
    codec=$(printf "%s\n" "$TRANSCODING" | cut -d- -f1)
    protocol=$(printf "%s\n" "$TRANSCODING" | awk -F- '{ print $2 }')
    [ -z "$protocol" ] && [ "$TRANSCODING_SET" = false ] && protocol=progressive
    # `jq` will return empty string rather than 'null' if no transcoding found
    printf "%s\n" "$transcodings" |
      jq ".[] | select((.preset | startswith(\"$codec\")) and .format.protocol == \"$protocol\")"
  )
  if [ -z "$transcoding" ]; then
    if [ "$TRANSCODING_SET" = true ]; then
      error "Transcoding not found."
      return 1
    else
      error "Transcoding not found, trying default..."
      transcoding=$(printf "%s\n" "$transcodings" | jq '.[0] // empty')
      if [ -z "$transcoding" ]; then
        error "Transcoding not available, track details:"
        error "$(printf "%s\n" "$json" | jq -c)"
        return 1
      fi
    fi
  fi

  auth=$(printf "%s\n" "$json" | jq -r '.track_authorization // empty')
  dl_url=$(printf "%s\n" "$transcoding" | jq -r '.url // empty')
  dl_url=$(curl_with_retry -fsSL "$dl_url?client_id=$CLIENT_ID&track_authorization=$auth" | jq -r '.url // empty')
  [ -n "$dl_url" ]
  filename=$(printf "%s\n" "$_path" | sed 's|^/||; s|-|_|g; s|/|-|g')
  codec=$(printf "%s\n" "$transcoding" | jq -r '.preset // empty' | sed 's/_.\+$//')
  [ -n "$codec" ]
  filename="$filename.$codec"
  protocol=$(printf "%s\n" "$transcoding" | jq -r '.format.protocol // empty')
  [ -n "$protocol" ]

  error "==> Downloading '$filename'..."
  if [ "$protocol" = progressive ]; then
    curl_with_retry -fL -o "$workdir/$filename" "$dl_url"
  elif [ "$protocol" = hls ]; then
    curl_with_retry -fsSL "$dl_url" >"$workdir/m3u8"
    url_list=$(grep '^https\?://.\+$' "$workdir/m3u8")
    total=$(printf "%s\n" "$url_list" | wc -l | awk '{ print $1 }')
    part=0
    file_list=
    for u in $url_list; do
      curl_with_retry -fsSL -o "$workdir/$filename.$part" "$u"
      file_list="$file_list|$workdir/$filename.$part"
      : $((part += 1))
      printf "\r==> Downloading audio parts: %s/%s" "$part" "$total" >&2
    done
    printf "\n" >&2
    file_list=$(printf "%s\n" "$file_list" | cut -c2-)
    error "==> Merging audio parts..."
    ffmpeg -nostdin -loglevel warning -hide_banner -i "concat:$file_list" -c copy "$workdir/$filename"
  else
    error "Unknown protocol: '$protocol'."
    return 1
  fi

  if [ "$METADATA" = true ]; then
    error "==> Writing metadata..."
    ffmpeg -nostdin -loglevel warning -hide_banner -i "$workdir/$filename" \
      -metadata title="$title" -metadata artist="$artist" -metadata album="$album" \
      -c copy "$workdir/tmp.$filename"
    mv "$workdir/tmp.$filename" "$workdir/$filename"
  fi

  if [ "$COVER" = true ]; then
    error "==> Fetching cover art..."
    if [ -z "$cover_url" ]; then
      error "Cover art not found, skipping..."
    elif [ "$codec" = opus ]; then
      error "Cover art for Opus not supported by ffmpeg, skipping..."
      error "See https://trac.ffmpeg.org/ticket/4448"
    else
      curl_with_retry -fsSL -o "$workdir/cover" "$cover_url"
      error "==> Writing cover art..."
      ffmpeg -nostdin -loglevel warning -hide_banner -i "$workdir/$filename" -i "$workdir/cover" \
        -map 0 -map 1 -c copy "$workdir/tmp.$filename"
      mv "$workdir/tmp.$filename" "$workdir/$filename"
    fi
  fi

  mv "$workdir/$filename" "$OUT_DIR"
  rm -rf "$workdir"
  error "$OUT_DIR/$filename"
)

fetch_track() {
  error "==> Fetching track '$1'..."
  track_json=$(
    curl_with_retry -fsSL "$1" | grep -o '^<script>window\.__sc_hydration = .\+;</script>$' |
      grep -o '\[.\+\]' | jq '.[] | select(.hydratable == "sound") | .data // empty'
  )
  if [ -z "$track_json" ]; then
    error "Cannot extract JSON, skipping..."
    return 1
  fi
  download_track "$track_json"
  [ $? -ne 0 ] && error "Cannot fetch the track."
  unset track_json
}

fetch_playlist() {
  error "==> Fetching playlist '$1'..."
  html=$(curl_with_retry -fsSL "$1")
  app_version=$(printf "%s\n" "$html" | grep -o '^<script>window.__sc_version="[[:digit:]]\+"</script>$' | grep -o '[[:digit:]]\+')
  playlist_json=$(
    printf "%s\n" "$html" | grep -o '^<script>window\.__sc_hydration = .\+;</script>$' |
      grep -o '\[.\+\]' | jq '.[] | select(.hydratable == "playlist") | .data // empty'
  )
  unset html
  if [ -z "$playlist_json" ]; then
    error "Cannot extract JSON, skipping..."
    return 1
  fi
  error "==> Fetching $(printf "%s\n" "$playlist_json" | jq -r '.track_count') track(s)..."

  initial_tracks=$(printf "%s\n" "$playlist_json" | jq '[.tracks[] | select(has("artwork_url"))]')
  id_list=$(printf "%s\n" "$playlist_json" | jq '.tracks[] | select(has("artwork_url") | not) | .id' | xargs -n 50 | tr ' ' ',')
  unset playlist_json
  printf "%s\n" "$initial_tracks" | jq -c '.[]' | while read -r track_json; do
    download_track "$track_json"
    [ $? -ne 0 ] && error "Cannot fetch the track."
  done
  unset initial_tracks

  for ids in $id_list; do
    api_url="https://api-v2.soundcloud.com/tracks?ids=$ids&client_id=$CLIENT_ID&[object Object]=&app_version=$app_version&app_locale=en"
    additional_tracks=$(curl_with_retry -fsSL -g "$api_url")
    printf "%s\n" "$additional_tracks" | jq -c '.[]' | while read -r track_json; do
      download_track "$track_json"
      [ $? -ne 0 ] && error "Cannot fetch the track."
    done
    unset additional_tracks
  done
  unset id_list
}

fetch_user_tracks() {
  error "==> Fetching user's tracks '$1'..."
  html=$(curl_with_retry -fsSL "$1")
  app_version=$(printf "%s\n" "$html" | grep -o '^<script>window.__sc_version="[[:digit:]]\+"</script>$' | grep -o '[[:digit:]]\+')
  user_json=$(
    printf "%s\n" "$html" | grep -o '^<script>window\.__sc_hydration = .\+;</script>$' |
      grep -o '\[.\+\]' | jq '.[] | select(.hydratable == "user") | .data // empty'
  )
  unset html
  if [ -z "$user_json" ]; then
    error "Cannot extract JSON, skipping..."
    return 1
  fi
  error "==> Fetching $(printf "%s\n" "$user_json" | jq -r '.track_count') track(s)..."
  user_id=$(printf "%s\n" "$user_json" | jq -r '.id')
  unset user_json
  api_url="https://api-v2.soundcloud.com/users/$user_id/tracks?representation=&client_id=$CLIENT_ID&limit=20&offset=0&linked_partitioning=1&app_version=$app_version&app_locale=en"
  while true; do
    user_tracks=$(curl_with_retry -fsSL -g "$api_url")
    printf "%s\n" "$user_tracks" | jq -c '.collection[]' | while read -r track_json; do
      download_track "$track_json"
      [ $? -ne 0 ] && error "Cannot fetch the track."
    done
    api_url=$(printf "%s\n" "$user_tracks" | jq -r '.next_href // empty')
    [ -z "$api_url" ] && break
    api_url="$api_url&client_id=$CLIENT_ID&app_version=$app_version&app_locale=en"
    unset user_tracks
  done
}

fetch_user_albums() {
  error "==> Fetching user's albums '$1'..."
  html=$(curl_with_retry -fsSL "$1")
  app_version=$(printf "%s\n" "$html" | grep -o '^<script>window.__sc_version="[[:digit:]]\+"</script>$' | grep -o '[[:digit:]]\+')
  user_json=$(
    printf "%s\n" "$html" | grep -o '^<script>window\.__sc_hydration = .\+;</script>$' |
      grep -o '\[.\+\]' | jq '.[] | select(.hydratable == "user") | .data // empty'
  )
  unset html
  if [ -z "$user_json" ]; then
    error "Cannot extract JSON, skipping..."
    return 1
  fi
  # No album count
  # error "==> Fetching $(printf "%s\n" "$user_json" | jq -r '.album_count') album(s)..."
  user_id=$(printf "%s\n" "$user_json" | jq -r '.id')
  unset user_json
  api_url="https://api-v2.soundcloud.com/users/$user_id/albums?client_id=$CLIENT_ID&limit=10&offset=0&linked_partitioning=1&app_version=$app_version&app_locale=en"
  while true; do
    user_albums=$(curl_with_retry -fsSL -g "$api_url")
    api_url=$(printf "%s\n" "$user_albums" | jq -r '.next_href // empty')
    album_urls=$(printf "%s\n" "$user_albums" | jq -r '.collection[].permalink_url // empty')
    unset user_albums
    for pl_url in $album_urls; do
      fetch_playlist "$pl_url"
    done
    [ -z "$api_url" ] && break
    api_url="$api_url&client_id=$CLIENT_ID&app_version=$app_version&app_locale=en"
  done
}

fetch_user_playlists() {
  error "==> Fetching user's playlists '$1'..."
  html=$(curl_with_retry -fsSL "$1")
  app_version=$(printf "%s\n" "$html" | grep -o '^<script>window.__sc_version="[[:digit:]]\+"</script>$' | grep -o '[[:digit:]]\+')
  user_json=$(
    printf "%s\n" "$html" | grep -o '^<script>window\.__sc_hydration = .\+;</script>$' |
      grep -o '\[.\+\]' | jq '.[] | select(.hydratable == "user") | .data // empty'
  )
  unset html
  if [ -z "$user_json" ]; then
    error "Cannot extract JSON, skipping..."
    return 1
  fi
  error "==> Fetching $(printf "%s\n" "$user_json" | jq -r '.playlist_count') playlist(s)..."
  user_id=$(printf "%s\n" "$user_json" | jq -r '.id')
  unset user_json
  api_url="https://api-v2.soundcloud.com/users/$user_id/playlists_without_albums?client_id=$CLIENT_ID&limit=10&offset=0&linked_partitioning=1&app_version=$app_version&app_locale=en"
  while true; do
    user_playlists=$(curl_with_retry -fsSL -g "$api_url")
    api_url=$(printf "%s\n" "$user_playlists" | jq -r '.next_href // empty')
    playlist_urls=$(printf "%s\n" "$user_playlists" | jq -r '.collection[].permalink_url // empty')
    unset user_playlists
    for pl_url in $playlist_urls; do
      fetch_playlist "$pl_url"
    done
    [ -z "$api_url" ] && break
    api_url="$api_url&client_id=$CLIENT_ID&app_version=$app_version&app_locale=en"
  done
}

fetch_url() {
  _url=${1%%#*}
  _url=${_url%%\?*}
  if printf "%s\n" "$_url" | grep -qs '^https://soundcloud.com/[^/]\+/tracks$'; then
    fetch_user_tracks "$_url"
  elif printf "%s\n" "$_url" | grep -qs '^https://soundcloud.com/[^/]\+/albums$'; then
    fetch_user_albums "$_url"
  elif printf "%s\n" "$_url" | grep -qs '^https://soundcloud.com/[^/]\+/sets$'; then
    fetch_user_playlists "$_url"
  elif printf "%s\n" "$_url" | grep -qs '^https://soundcloud.com/[^/]\+/[^/]\+$'; then
    fetch_track "$_url"
  elif printf "%s\n" "$_url" | grep -qs '^https://soundcloud.com/[^/]\+/sets/[^/]\+$'; then
    fetch_playlist "$_url"
  else
    error "Skipping unknown URL: '$1'..."
  fi
}

for url in $URL_LIST; do
  fetch_url "$url"
done

if [ "$INPUT_FILE_SET" = true ]; then
  while read -r url; do
    [ -n "$url" ] && fetch_url "$url"
  done <"$INPUT_FILE"
fi

rm -rf "$TMP_DIR"
