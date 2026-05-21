import json
import re
from datetime import datetime
from pathlib import Path

import requests
import yt_dlp
from ytmusicapi import YTMusic


def add(a, b):
    return a + b


def _client():
    return YTMusic(language="en")


def _safe_filename(name, max_len=160):
    name = str(name or "")
    name = re.sub(r'[\\/*?:"<>|]', "_", name)
    name = re.sub(r"\s+", " ", name).strip()
    return (name[:max_len] if len(name) > max_len else name) or "download"


def _duration_seconds(value):
    if value is None:
        return 0
    if isinstance(value, (int, float)):
        seconds = int(value)
        return seconds if seconds > 0 else 0

    text = str(value).strip()
    if not text or text.lower() == "none":
        return 0
    if text.isdigit():
        number = int(text)
        return number // 1000 if number > 10000 else number
    if ":" in text:
        parts = text.split(":")
        if 2 <= len(parts) <= 3 and all(part.strip().isdigit() for part in parts):
            total = 0
            for part in parts:
                total = (total * 60) + int(part.strip())
            return total
    return 0


def _extract_duration_seconds(*items):
    keys = ("duration", "durationSeconds", "lengthSeconds", "approxDurationMs", "duration_ms")
    for item in items:
        if not isinstance(item, dict):
            continue
        for key in keys:
            seconds = _duration_seconds(item.get(key))
            if seconds > 0:
                return seconds
        video_details = item.get("videoDetails")
        if isinstance(video_details, dict):
            for key in keys:
                seconds = _duration_seconds(video_details.get(key))
                if seconds > 0:
                    return seconds
    return 0


def _unique_stem(path):
    suffixes = (".mp3", ".m4a", ".webm", ".opus", ".ogg", ".aac")
    temp_suffixes = tuple(f".temp{suffix}" for suffix in suffixes) + (".part",)

    def is_free(candidate):
        return not any(candidate.with_suffix(suffix).exists() for suffix in suffixes + temp_suffixes)

    if is_free(path):
        return path

    index = 1
    while True:
        candidate = path.with_name(f"{path.name} ({index})")
        if is_free(candidate):
            return candidate
        index += 1


def _delete_stale_outputs(stem):
    for suffix in (".temp.mp3", ".temp.m4a", ".temp.webm", ".temp.opus", ".temp.ogg", ".temp.aac", ".part"):
        try:
            candidate = stem.with_suffix(suffix)
            if candidate.exists():
                candidate.unlink()
        except Exception:
            pass


def _artist_text(item):
    artists = item.get("artists") or []
    names = [artist.get("name", "") for artist in artists if artist.get("name")]
    if names:
        return ", ".join(names)
    author = item.get("author")
    return author if isinstance(author, str) else ""


def _thumbnail_candidates(*items):
    thumbs = []

    def collect(value):
        if isinstance(value, list):
            for child in value:
                collect(child)
        elif isinstance(value, dict):
            if value.get("url"):
                thumbs.append(value)
            for key in ("thumbnails", "thumbnail"):
                if key in value:
                    collect(value[key])

    for item in items:
        if isinstance(item, dict):
            collect(item)

    thumbs.sort(key=lambda thumb: (thumb.get("width", 0) or 0) * (thumb.get("height", 0) or 0), reverse=True)
    urls = []
    seen = set()
    for thumb in thumbs:
        url = thumb.get("url", "")
        if url and url not in seen:
            urls.append(url)
            seen.add(url)
    return urls


def _high_quality_thumbnail_urls(url):
    urls = []

    def add(candidate):
        if candidate and candidate not in urls:
            urls.append(candidate)

    clean = str(url or "").split("?")[0]
    match = re.search(r"(https?://[^/]+/(?:vi|vi_webp)/([^/]+)/)", clean)
    if match:
        prefix = match.group(1).replace("/vi_webp/", "/vi/")
        for name in ("maxresdefault.jpg", "sddefault.jpg", "hq720.jpg", "hqdefault.jpg", "mqdefault.jpg"):
            add(prefix + name)
    add(url)
    add(clean)
    return urls


def _detect_image_mime(data, fallback_url=""):
    if data.startswith(b"\xff\xd8"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    extension = Path(str(fallback_url or "").split("?")[0]).suffix.lower()
    if extension in (".jpg", ".jpeg"):
        return "image/jpeg"
    if extension == ".png":
        return "image/png"
    return ""


def _best_thumbnail(item):
    candidates = _thumbnail_candidates(item)
    return candidates[0] if candidates else ""


def _cover_bytes(*items):
    for url in _thumbnail_candidates(*items):
        for candidate in _high_quality_thumbnail_urls(url):
            try:
                response = requests.get(candidate, timeout=20)
                response.raise_for_status()
                data = response.content
                mime = _detect_image_mime(data, candidate)
                if mime:
                    return data, mime
            except Exception:
                continue
    return None


def _preview_thumbnail_url(*items):
    for url in _thumbnail_candidates(*items):
        for candidate in _high_quality_thumbnail_urls(url):
            try:
                with requests.get(candidate, stream=True, timeout=8) as response:
                    response.raise_for_status()
                    content_type = (response.headers.get("content-type") or "").lower()
                    chunk = next(response.iter_content(16), b"")
                    if "image/" in content_type or _detect_image_mime(chunk, candidate):
                        return candidate
            except Exception:
                continue
    return ""


def _delete_sidecar_images(media_path):
    for suffix in (".webp", ".jpg", ".jpeg", ".png"):
        for candidate in (
            media_path.with_suffix(suffix),
            media_path.with_name(f"{media_path.stem}.cover{suffix}"),
        ):
            try:
                if candidate.exists():
                    candidate.unlink()
            except Exception:
                pass


def _write_media_tags(media_path, title, artist, album, video_id, cover=None, track_no=None, total_tracks=None):
    suffix = media_path.suffix.lower()
    if suffix == ".mp3":
        from mutagen.id3 import APIC, COMM, ID3, TALB, TIT2, TPE1, TLEN, TRCK
        from mutagen.mp3 import MP3

        audio = MP3(str(media_path), ID3=ID3)
        if audio.tags is None:
            audio.add_tags()
        tags = audio.tags
        for frame in ("TIT2", "TPE1", "TALB", "TRCK", "TLEN", "COMM", "APIC"):
            try:
                tags.delall(frame)
            except Exception:
                pass
        tags.add(TIT2(encoding=3, text=title))
        tags.add(TPE1(encoding=3, text=artist))
        if album:
            tags.add(TALB(encoding=3, text=album))
        if track_no is not None:
            track_text = f"{track_no}/{total_tracks}" if total_tracks is not None else str(track_no)
            tags.add(TRCK(encoding=3, text=track_text))
        audio_duration = getattr(audio.info, "length", 0) or 0
        if audio_duration > 0:
            tags.add(TLEN(encoding=3, text=str(int(audio_duration * 1000))))
        tags.add(COMM(encoding=3, lang="eng", desc="Comment", text=f"Downloaded from YouTube Music. videoId={video_id}"))
        if cover:
            data, mime = cover
            tags.add(APIC(encoding=3, mime=mime, type=3, desc="Cover", data=data))
        audio.save(v2_version=3)
        return

    if suffix in (".m4a", ".mp4"):
        from mutagen.mp4 import MP4, MP4Cover

        audio = MP4(str(media_path))
        audio["\xa9nam"] = [title]
        audio["\xa9ART"] = [artist]
        if album:
            audio["\xa9alb"] = [album]
        if track_no is not None:
            audio["trkn"] = [(int(track_no), int(total_tracks or 0))]
        audio["----:com.apple.iTunes:videoId"] = [str(video_id).encode("utf-8")]
        if cover:
            data, mime = cover
            image_format = MP4Cover.FORMAT_PNG if mime == "image/png" else MP4Cover.FORMAT_JPEG
            audio["covr"] = [MP4Cover(data, imageformat=image_format)]
        audio.save()


def _search_item(item, fallback_type):
    result_type = item.get("resultType") or fallback_type.rstrip("s")
    return {
        "resultType": result_type,
        "title": item.get("title") or "Unknown title",
        "artist": _artist_text(item),
        "duration": item.get("duration") or str(_extract_duration_seconds(item) or ""),
        "videoId": item.get("videoId") or "",
        "browseId": item.get("browseId") or "",
        "thumbnailUrl": _best_thumbnail(item),
        "raw": item,
    }


def search_youtube_music(query, filter_name="songs", limit=20):
    query = str(query or "").strip()
    if not query:
        return "[]"

    filter_name = filter_name if filter_name in ("songs", "videos", "albums", "playlists") else "songs"
    limit = int(limit or 20)
    results = _client().search(query, filter=filter_name, limit=limit)
    payload = [_search_item(item, filter_name) for item in results]
    return json.dumps(payload, ensure_ascii=False)


def _entity_from_item(ytmusic, item):
    result_type = item.get("resultType") or item.get("result_type") or ""
    video_id = item.get("videoId") or item.get("video_id") or ""
    browse_id = item.get("browseId") or item.get("browse_id") or ""
    if not result_type and video_id:
        result_type = "song"

    if result_type in ("song", "video") and video_id:
        return "track", ytmusic.get_song(video_id)
    if result_type == "album" and browse_id:
        return "album", ytmusic.get_album(browse_id)
    if result_type in ("playlist", "featured_playlist", "community_playlist") and browse_id:
        playlist_id = browse_id[2:] if browse_id.startswith("VL") else browse_id
        return "playlist", ytmusic.get_playlist(playlist_id, limit=None, related=False)

    raw = item.get("raw") if isinstance(item.get("raw"), dict) else item
    return "track", raw


def _track_fields(track, fallback_title="", fallback_artist=""):
    video_details = track.get("videoDetails") if isinstance(track.get("videoDetails"), dict) else {}
    title = track.get("title") or track.get("name") or video_details.get("title") or fallback_title or "Unknown title"
    artist = _artist_text(track) or fallback_artist or "Unknown artist"
    if artist == "Unknown artist":
        artist = video_details.get("author") or artist
    album = ""
    raw_album = track.get("album")
    if isinstance(raw_album, dict):
        album = raw_album.get("name") or ""
    elif isinstance(raw_album, str):
        album = raw_album
    return title, artist, album


def _download_track(
    track,
    download_dir,
    index=None,
    total=None,
    fallback_title="",
    fallback_artist="",
    cover=None,
    fallback_cover_entity=None,
):
    video_details = track.get("videoDetails") if isinstance(track.get("videoDetails"), dict) else {}
    video_id = track.get("videoId") or track.get("video_id") or video_details.get("videoId")
    if not video_id:
        return None

    title, artist, album = _track_fields(track, fallback_title=fallback_title, fallback_artist=fallback_artist)
    prefix = f"{str(index).zfill(max(2, len(str(total or 0))))} - " if index is not None and total is not None else ""
    stem = _unique_stem(download_dir / f"{prefix}{_safe_filename(artist)} - {_safe_filename(title)}")
    _delete_stale_outputs(stem)
    outtmpl = str(stem) + ".%(ext)s"

    options = {
        "format": "bestaudio[ext=m4a]/bestaudio/best",
        "outtmpl": outtmpl,
        "noplaylist": True,
        "quiet": True,
        "noprogress": True,
        "no_warnings": True,
        "writethumbnail": False,
    }

    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=True)

    candidates = sorted(stem.parent.glob(stem.name + ".*"), key=lambda p: p.stat().st_mtime, reverse=True)
    media_files = [path for path in candidates if path.suffix.lower() in (".m4a", ".webm", ".opus", ".ogg", ".mp3")]
    if not media_files:
        return None

    media_path = media_files[0]
    _delete_sidecar_images(media_path)
    tag_cover = cover if cover is not None else _cover_bytes(track, fallback_cover_entity, info)
    try:
        _write_media_tags(
            media_path,
            title,
            artist,
            album,
            video_id,
            cover=tag_cover,
            track_no=index,
            total_tracks=total,
        )
    except Exception:
        pass

    return {
        "file": str(media_path),
        "title": title,
        "artist": artist,
        "album": album,
        "videoId": video_id,
        "durationSeconds": _extract_duration_seconds(track, info),
        "extractor": info.get("extractor", ""),
    }


def download_youtube_music(item_json, output_dir):
    item = json.loads(item_json) if isinstance(item_json, str) else dict(item_json or {})
    download_dir = Path(output_dir).expanduser().resolve()
    download_dir.mkdir(parents=True, exist_ok=True)

    ytmusic = _client()
    entity_type, entity = _entity_from_item(ytmusic, item)
    downloaded = []

    if entity_type == "album":
        tracks = [track for track in entity.get("tracks", []) if track.get("videoId")]
        album_title = entity.get("title") or item.get("title") or "Album"
        artist = _artist_text(entity) or item.get("artist") or "Unknown artist"
        folder = download_dir / _safe_filename(f"{artist} - {album_title}")
        folder.mkdir(parents=True, exist_ok=True)
        album_cover = _cover_bytes(entity, item)
        for index, track in enumerate(tracks, start=1):
            if not track.get("album"):
                track["album"] = {"name": album_title}
            result = _download_track(
                track,
                folder,
                index=index,
                total=len(tracks),
                fallback_artist=artist,
                cover=album_cover,
                fallback_cover_entity=entity,
            )
            if result:
                downloaded.append(result)
    elif entity_type == "playlist":
        tracks = [track for track in entity.get("tracks", []) if track.get("videoId")]
        playlist_title = entity.get("title") or item.get("title") or "Playlist"
        author = entity.get("author")
        if isinstance(author, dict):
            author = author.get("name")
        artist = author or item.get("artist") or "YouTube Music"
        folder = download_dir / _safe_filename(f"{artist} - {playlist_title}")
        folder.mkdir(parents=True, exist_ok=True)
        playlist_cover = _cover_bytes(entity, item)
        for index, track in enumerate(tracks, start=1):
            if not track.get("album"):
                track["album"] = {"name": playlist_title}
            result = _download_track(
                track,
                folder,
                index=index,
                total=len(tracks),
                fallback_artist=artist,
                cover=playlist_cover,
                fallback_cover_entity=entity,
            )
            if result:
                downloaded.append(result)
    else:
        raw = entity if isinstance(entity, dict) else item.get("raw", item)
        if item.get("videoId") and not raw.get("videoId"):
            raw["videoId"] = item.get("videoId")
        if item.get("title") and not raw.get("title"):
            raw["title"] = item.get("title")
        if item.get("artist") and not raw.get("author") and not raw.get("artists"):
            raw["author"] = item.get("artist")
        if item.get("thumbnailUrl") and not _best_thumbnail(raw):
            raw["thumbnail"] = [{"url": item.get("thumbnailUrl"), "width": 0, "height": 0}]
        result = _download_track(
            raw,
            download_dir,
            fallback_title=item.get("title", ""),
            fallback_artist=item.get("artist", ""),
            fallback_cover_entity=item,
        )
        if result:
            downloaded.append(result)

    payload = {
        "files": [entry["file"] for entry in downloaded],
        "downloadDir": str(download_dir),
        "message": "Downloaded from YouTube Music",
        "downloadedAt": datetime.now().isoformat(timespec="seconds"),
        "items": downloaded,
    }
    return json.dumps(payload, ensure_ascii=False)


def stream_youtube_music(item_json):
    item = json.loads(item_json) if isinstance(item_json, str) else dict(item_json or {})
    video_id = item.get("videoId") or item.get("video_id")
    raw = item.get("raw") if isinstance(item.get("raw"), dict) else item
    video_id = video_id or raw.get("videoId")
    result_type = (item.get("resultType") or raw.get("resultType") or "").lower()
    is_video = result_type == "video"

    if not video_id and result_type in ("album", "playlist", "featured_playlist", "community_playlist"):
        ytmusic = _client()
        entity_type, entity = _entity_from_item(ytmusic, item)
        tracks = entity.get("tracks", []) if isinstance(entity, dict) else []
        first_track = next((track for track in tracks if track.get("videoId")), None)
        if first_track:
            video_id = first_track.get("videoId")
            raw = first_track
            if not item.get("title"):
                item["title"] = first_track.get("title", "")
            if not item.get("artist"):
                item["artist"] = _artist_text(first_track)

    if not video_id:
        raise ValueError("This result cannot be streamed because it has no videoId.")

    options = {
        "format": "best[ext=mp4][vcodec!=none][acodec!=none]/best[vcodec!=none][acodec!=none]/best" if is_video else "bestaudio[ext=m4a]/bestaudio/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
    }
    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)

    album = raw.get("album", {})
    info_thumbnails = {"thumbnails": info.get("thumbnails") or [{"url": info.get("thumbnail", "")}]}
    preview_thumb = (
        item.get("thumbnailUrl")
        or _best_thumbnail(raw)
        or _best_thumbnail(info_thumbnails)
        or info.get("thumbnail", "")
    )
    payload = {
        "url": info.get("url", ""),
        "title": item.get("title") or raw.get("title") or info.get("title") or "YouTube Music",
        "artist": item.get("artist") or _artist_text(raw) or info.get("uploader") or "YouTube Music",
        "album": album.get("name", "") if isinstance(album, dict) else "",
        "thumbnailUrl": preview_thumb,
        "durationSeconds": _extract_duration_seconds(raw, info),
        "videoId": video_id,
        "isVideo": is_video,
    }
    return json.dumps(payload, ensure_ascii=False)
