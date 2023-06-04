# SoundCrawler

SoundCrawler is a shell script that allows you to crawl SoundCloud and download tracks along with their metadata and
cover art.

![](demo.svg)

## Dependencies

- curl
- jq
- ffmpeg (if you want to write metadata/cover art to media files or to download HLS tracks)

## Usage

```
Usage: soundcrawler.sh [<options>] <url>...
Download tracks from SoundCloud.

    -i                    print media information instead of downloading media files
    -M                    do NOT write metadata to media files
    -C                    do NOT write cover art to media files
    -I <file>             read URLs from file
    -o <dir>              set output directory
    -t <transcoding>      specify a transcoding to download
    -h                    display this help and exit

Home page: <https://github.com/qianbinbin/soundcrawler>
```

### Examples

To download a single track:

```sh
$ soundcrawler.sh https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
```

To download multiple tracks in Opus format:

```sh
$ soundcrawler.sh -t opus-hls \
https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt \
https://soundcloud.com/vardenbeats/when-the-sun-sets-rework
```

To download all tracks in a playlist:

```sh
$ soundcrawler.sh https://soundcloud.com/dabootlegboy/sets/its-2am-and-i-still-miss-you
```

To read URLs from a file and download tracks:

```sh
$ cat input.txt
https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
https://soundcloud.com/dabootlegboy/sets/its-2am-and-i-still-miss-you
$ soundcrawler.sh -I input.txt
```

To print media information instead of downloading:

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
  Cover               https://i1.sndcdn.com/artworks-eHM1Jhho6GkSTg2m-jrUWsQ-t500x500.jpg
--------------------------------------------------------------------------------
  Transcodings        # Available formats and qualities
--------------------------------------------------------------------------------
  - Preset            mp3_0_1
    MIME type         audio/mpeg
    Protocol          hls
    Quality           sq
  # Download with     soundcrawler.sh -t mp3-hls [<options>] <url>...
--------------------------------------------------------------------------------
  - Preset            mp3_0_1
    MIME type         audio/mpeg
    Protocol          progressive
    Quality           sq
  # Download with     soundcrawler.sh -t mp3 [<options>] <url>...
--------------------------------------------------------------------------------
  - Preset            opus_0_0
    MIME type         audio/ogg; codecs="opus"
    Protocol          hls
    Quality           sq
  # Download with     soundcrawler.sh -t opus-hls [<options>] <url>...
```

## License

[MIT](LICENSE)