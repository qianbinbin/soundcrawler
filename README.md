# SoundCrawler

SoundCrawler is a shell script to download tracks from SoundCloud.

## Dependencies

- curl
- jq
- ffmpeg (if you want to write metadata/cover art to media files or to download HLS tracks)

## Usage

```
Usage: soundcrawler.sh [<options>] <url>...
Download tracks from SoundCloud.

    -i                    print media information instead of downloading media files (implies -M and -C)
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

To specify the transcoding of Opus and HLS and download multiple tracks:

```sh
$ soundcrawler.sh -t opus-hls https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt https://soundcloud.com/vardenbeats/when-the-sun-sets-rework
```

To download all tracks in a set:

```sh
$ soundcrawler.sh https://soundcloud.com/dabootlegboy/sets/its-2am-and-i-still-miss-you
```

To download tracks with URLs in a file:

```sh
$ cat input.txt
https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
https://soundcloud.com/dabootlegboy/sets/its-2am-and-i-still-miss-you
$ soundcrawler.sh -I input.txt
```

To print media information of the track(s) instead of downloading:

```sh
$ soundcrawler.sh -i https://soundcloud.com/takeotakeo/heated-blanket-w-spencer-hunt
```

## License

[MIT](LICENSE)