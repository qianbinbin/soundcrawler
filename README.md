# SoundCrawler

SoundCrawler is a shell script that allows you to crawl SoundCloud and download tracks along with their metadata and
cover art.

![](demo.svg)

## Dependencies

- curl
- jq
- ffmpeg (if you want to write metadata/cover art to media files or download HLS tracks)

## Usage

```
Usage: soundcrawler.sh [<options>] <url>...
Download tracks from SoundCloud.

    -i                    print media information instead of downloading the files
    -M                    do NOT write metadata to media files
    -C                    do NOT write cover art to media files
    -I <file>             read URLs from file
    -o <dir>              set the output directory
    -t <transcoding>      specify a transcoding to use when downloading
    -h                    display this help and exit

Home page: <https://github.com/qianbinbin/soundcrawler>
```

### Examples

To download a single track:

```sh
$ soundcrawler.sh https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
```

To download an album/playlist:

```sh
$ soundcrawler.sh https://soundcloud.com/dabootlegboy/sets/its-2am-and-i-still-miss-you
```

To download all the user's tracks/albums/playlists:

```sh
$ soundcrawler.sh https://soundcloud.com/takeotakeo/tracks
$ soundcrawler.sh https://soundcloud.com/takeotakeo/albums
$ soundcrawler.sh https://soundcloud.com/takeotakeo/sets
```

To download in Opus format:

```sh
$ soundcrawler.sh -t opus-hls https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
```

To read multiple URLs:

```sh
$ soundcrawler.sh \
https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt \
https://soundcloud.com/vardenbeats/when-the-sun-sets-rework
$ cat input.txt # or read from file
https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
https://soundcloud.com/vardenbeats/when-the-sun-sets-rework
$ soundcrawler.sh -I input.txt
```

To print media information instead of downloading the files:

```sh
$ soundcrawler.sh -i https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
==> Fetching client_id...
==> Fetching track 'https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt'...
================================================================================
  Permalink           https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
  ID                  967061290
  Title               Heated Blanket
  Artist              tysu & Spencer Hunt
  Album               Cozy Winter
  Cover Art           https://i1.sndcdn.com/artworks-eHM1Jhho6GkSTg2m-jrUWsQ-t500x500.jpg
--------------------------------------------------------------------------------
  Transcodings        # Available formats and qualities
--------------------------------------------------------------------------------
  - Preset            mp3_0_1
    MIME Type         audio/mpeg
    Protocol          hls
    Quality           sq
  # Download With     soundcrawler.sh -t mp3-hls [<options>] <url>...
--------------------------------------------------------------------------------
  - Preset            mp3_0_1
    MIME Type         audio/mpeg
    Protocol          progressive
    Quality           sq
  # Download With     soundcrawler.sh -t mp3 [<options>] <url>...
--------------------------------------------------------------------------------
  - Preset            opus_0_0
    MIME Type         audio/ogg; codecs="opus"
    Protocol          hls
    Quality           sq
  # Download With     soundcrawler.sh -t opus-hls [<options>] <url>...
```

## License

[MIT](LICENSE)