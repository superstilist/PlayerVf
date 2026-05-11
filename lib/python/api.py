import argparse
import json
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Default directory layout (all relative to this file; callers can override)
# ---------------------------------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "output"
DOWNLOAD_DIR = OUTPUT_DIR / "downloads"
JSON_DIR = OUTPUT_DIR / "metadata"
COVER_DIR = OUTPUT_DIR / "covers"

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

def safe_filename(name: str, max_len: int = 180) -> str:
    """Strip filesystem-unsafe characters and trim length."""
    name = str(name or "")
    name = re.sub(r'[\\/*?:"<>|]', "_", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name[:max_len] if len(name) > max_len else name


def unique_path(path: Path) -> Path:
    """Return *path* unchanged if it does not exist, otherwise append *(n)*."""
    if not path.exists():
        return path
    stem, suffix, parent = path.stem, path.suffix, path.parent
    i = 1
    while True:
        candidate = parent / f"{stem} ({i}){suffix}"
        if not candidate.exists():
            return candidate
        i += 1


def unique_media_stem(stem: Path) -> Path:
    suffixes = (".mp3", ".m4a", ".webm", ".opus", ".ogg", ".aac")
    temp_suffixes = tuple(f".temp{suffix}" for suffix in suffixes) + (".part",)

    def is_free(candidate: Path) -> bool:
        return not any(candidate.with_suffix(suffix).exists() for suffix in suffixes + temp_suffixes)

    if is_free(stem):
        return stem

    index = 1
    while True:
        candidate = stem.with_name(f"{stem.name} ({index})")
        if is_free(candidate):
            return candidate
        index += 1


def download_bytes(url: str, timeout: int = 30) -> bytes:
    """Download *url* and return raw bytes."""
    import requests

    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return r.content


def download_to_file(url: str, path: Path, timeout: int = 30) -> Path:
    """Download *url* and save to *path*, returning *path*."""
    path.write_bytes(download_bytes(url, timeout=timeout))
    return path


def detect_mime(path: Path) -> str:
    """Guess image MIME type from file extension."""
    ext = path.suffix.lower()
    return {"jpg": "image/jpeg", "jpeg": "image/jpeg",
            "png": "image/png", "webp": "image/webp"}.get(ext.lstrip("."), "image/jpeg")


def thumbnail_candidates(*entities: Optional[Dict[str, Any]]) -> List[str]:
    """Return thumbnail URLs from all entities, highest-resolution first."""
    thumbs: List[Dict[str, Any]] = []

    def collect(value: Any) -> None:
        if isinstance(value, list):
            for item in value:
                collect(item)
        elif isinstance(value, dict):
            if value.get("url"):
                thumbs.append(value)
            for key in ("thumbnails", "thumbnail"):
                if key in value:
                    collect(value[key])

    for entity in entities:
        if isinstance(entity, dict):
            collect(entity)

    thumbs.sort(key=lambda t: (t.get("width", 0) or 0) * (t.get("height", 0) or 0), reverse=True)
    urls: List[str] = []
    seen = set()
    for thumb in thumbs:
        url = thumb.get("url")
        if isinstance(url, str) and url and url not in seen:
            urls.append(url)
            seen.add(url)
    return urls


def high_quality_thumbnail_urls(url: str) -> List[str]:
    """Expand a YouTube thumbnail URL into likely higher-quality variants."""
    urls: List[str] = []

    def add(candidate: str) -> None:
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


def detect_image_mime(data: bytes, fallback_url: str = "") -> Optional[str]:
    if data.startswith(b"\xff\xd8"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    ext = Path(fallback_url.split("?")[0]).suffix.lower()
    if ext in (".jpg", ".jpeg"):
        return "image/jpeg"
    if ext == ".png":
        return "image/png"
    return None


def download_best_cover(*entities: Optional[Dict[str, Any]]) -> Optional[Tuple[bytes, str]]:
    """Download the best available JPEG/PNG cover bytes from candidate metadata."""
    for url in thumbnail_candidates(*entities):
        for candidate in high_quality_thumbnail_urls(url):
            try:
                data = download_bytes(candidate, timeout=20)
                mime = detect_image_mime(data, candidate)
                if mime:
                    return data, mime
            except Exception:
                continue
    return None


def best_thumbnail(entity: Dict[str, Any]) -> Optional[str]:
    """Return the highest-resolution thumbnail URL found in *entity*, or None."""
    candidates = thumbnail_candidates(entity)
    return candidates[0] if candidates else None


def format_track_no(index: int, total: int) -> str:
    """Zero-padded track number string, e.g. '03' for index=3, total=12."""
    return str(index).zfill(max(2, len(str(total))))


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class SearchItem:
    """Lightweight representation of a single YTMusic search result."""
    result_type: str
    title: str
    artist: str = ""
    duration: str = ""
    video_id: str = ""
    browse_id: str = ""
    thumbnails: Optional[List[Dict[str, Any]]] = None
    raw: Optional[Dict[str, Any]] = field(default=None, repr=False)

    @property
    def thumbnail_url(self) -> Optional[str]:
        if self.thumbnails:
            best = max(
                self.thumbnails,
                key=lambda t: (t.get("width", 0) or 0) * (t.get("height", 0) or 0),
            )
            return best.get("url")
        return best_thumbnail(self.raw or {})


# ---------------------------------------------------------------------------
# Core downloader
# ---------------------------------------------------------------------------

class MediaDownloader:
    """
    High-level interface for searching YouTube Music and downloading tracks,
    albums, and playlists as tagged MP3 files.

    Parameters
    ----------
    ytmusic : YTMusic
        An authenticated (or anonymous) YTMusic instance.
    download_dir : Path, optional
        Root folder for downloaded MP3s. Defaults to module-level DOWNLOAD_DIR.
    json_dir : Path, optional
        Folder for saved metadata JSON files. Defaults to module-level JSON_DIR.
    cover_dir : Path, optional
        Folder for saved cover-art images. Defaults to module-level COVER_DIR.
    """

    def __init__(
            self,
            ytmusic: Optional[Any] = None,
            download_dir: Path = DOWNLOAD_DIR,
            json_dir: Path = JSON_DIR,
            cover_dir: Path = COVER_DIR,
            progress_cb: Optional[Callable[[Dict[str, Any]], None]] = None,
    ) -> None:
        from ytmusicapi import YTMusic

        self.ytmusic = ytmusic or YTMusic(language="en")
        self.download_dir = download_dir
        self.json_dir = json_dir
        self.cover_dir = cover_dir
        self.progress_cb = progress_cb

        self.download_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Search
    # ------------------------------------------------------------------

    def search(
            self,
            query: str,
            filter_name: str = "songs",
            limit: int = 25,
    ) -> List[SearchItem]:
        """
        Search YouTube Music.

        Parameters
        ----------
        query : str
            Search terms.
        filter_name : str
            One of ``"songs"``, ``"albums"``, ``"playlists"``, ``"videos"``.
        limit : int
            Maximum number of results to return.

        Returns
        -------
        List[SearchItem]
        """
        results = self.ytmusic.search(query, filter=filter_name, limit=limit)
        items: List[SearchItem] = []
        for r in results:
            result_type = r.get(
                "resultType",
                filter_name[:-1] if filter_name.endswith("s") else filter_name,
            )
            artists = r.get("artists") or []
            artist = ", ".join(a.get("name", "") for a in artists if a.get("name"))
            items.append(
                SearchItem(
                    result_type=result_type,
                    title=r.get("title", ""),
                    artist=artist,
                    duration=r.get("duration", ""),
                    video_id=r.get("videoId", ""),
                    browse_id=r.get("browseId", ""),
                    thumbnails=r.get("thumbnails"),
                    raw=r,
                )
            )
        return items

    # ------------------------------------------------------------------
    # Entity detail fetchers
    # ------------------------------------------------------------------

    def get_entity_details(self, item: SearchItem) -> Dict[str, Any]:
        """Fetch full metadata for a SearchItem from the YTMusic API."""
        if item.result_type in ("song", "video") and item.video_id:
            return self.ytmusic.get_song(item.video_id)
        if item.result_type == "album" and item.browse_id:
            return self.ytmusic.get_album(item.browse_id)
        if item.result_type in ("playlist", "featured_playlist", "community_playlist") and item.browse_id:
            pid = item.browse_id[2:] if item.browse_id.startswith("VL") else item.browse_id
            return self.ytmusic.get_playlist(pid, limit=None, related=False)
        return item.raw or {}

    @staticmethod
    def get_album_tracks(album: Dict[str, Any]) -> List[Dict[str, Any]]:
        return album.get("tracks", []) or []

    @staticmethod
    def get_playlist_tracks(playlist: Dict[str, Any]) -> List[Dict[str, Any]]:
        return playlist.get("tracks", []) or []

    # ------------------------------------------------------------------
    # Audio download
    # ------------------------------------------------------------------

    def download_audio_mp3(
            self,
            video_id: str,
            out_stem: Path,
            verbose: bool = False,
    ) -> Tuple[Path, Dict[str, Any]]:
        """
        Download a YouTube video as a 320 kbps MP3 via yt-dlp.

        Parameters
        ----------
        video_id : str
            YouTube video ID.
        out_stem : Path
            Output path *without* extension. yt-dlp appends ``.mp3``.
        verbose : bool
            Pass ``True`` to enable yt-dlp console output.

        Returns
        -------
        Tuple[Path, Dict[str, Any]]
            ``(mp3_path, yt_dlp_info_dict)``
        """
        has_ffmpeg = shutil.which("ffmpeg") is not None
        if not has_ffmpeg:
            raise RuntimeError("FFmpeg is required to save YouTube Music downloads as MP3.")

        self._delete_stale_outputs(out_stem)
        outtmpl = str(out_stem) + ".%(ext)s"
        ydl_opts: Dict[str, Any] = {
            "format": "bestaudio/best",
            "outtmpl": outtmpl,
            "noplaylist": True,
            "quiet": not verbose,
            "noprogress": True,
            "verbose": verbose,
            "writethumbnail": False,
        }

        if self.progress_cb:
            def _hook(status: Dict[str, Any]) -> None:
                total = status.get("total_bytes") or status.get("total_bytes_estimate") or 0
                downloaded = status.get("downloaded_bytes") or 0
                percent = float(downloaded) / float(total) if total else None
                self.progress_cb({
                    "event": "download",
                    "status": status.get("status", ""),
                    "percent": percent,
                    "downloadedBytes": downloaded,
                    "totalBytes": total,
                    "filename": status.get("filename", ""),
                })

            ydl_opts["progress_hooks"] = [_hook]
        ydl_opts["postprocessors"] = [
            {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "320"},
            {"key": "FFmpegMetadata"},
        ]

        import yt_dlp

        url = f"https://www.youtube.com/watch?v={video_id}"
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)

        mp3_path = Path(str(out_stem) + ".mp3")
        if mp3_path.exists():
            self._delete_sidecar_images(mp3_path)
            return mp3_path, info

        candidates = sorted(
            out_stem.parent.glob(out_stem.name + ".*"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        media_candidates = [
            path for path in candidates
            if path.suffix.lower() in (".mp3", ".m4a", ".webm", ".opus", ".ogg", ".aac")
        ]
        if media_candidates:
            mp3_path = media_candidates[0]
        else:
            candidates = sorted(mp3_path.parent.glob(mp3_path.stem + "*.mp3"))
            if candidates:
                mp3_path = candidates[0]
            else:
                raise FileNotFoundError(f"Audio file was not created for video_id={video_id}")

        self._delete_sidecar_images(mp3_path)
        return mp3_path, info

    @staticmethod
    def _delete_stale_outputs(stem: Path) -> None:
        for suffix in (".temp.mp3", ".temp.m4a", ".temp.webm", ".temp.opus", ".temp.ogg", ".temp.aac", ".part"):
            try:
                candidate = stem.with_suffix(suffix)
                if candidate.exists():
                    candidate.unlink()
            except Exception:
                pass

    @staticmethod
    def _delete_sidecar_images(media_path: Path) -> None:
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

    # ------------------------------------------------------------------
    # ID3 tag writing
    # ------------------------------------------------------------------

    def write_mp3_tags(
            self,
            mp3_path: Path,
            title: str,
            artist: str,
            album: str = "",
            date: str = "",
            genre: str = "",
            track_no: Optional[int] = None,
            total_tracks: Optional[int] = None,
            cover_path: Optional[Path] = None,
            comment: str = "",
    ) -> None:
        """Write ID3v2.3 tags (and optional cover art) to an MP3 file."""
        from mutagen.id3 import APIC, COMM, ID3, TALB, TCON, TIT2, TPE1, TDRC, TRCK
        from mutagen.mp3 import MP3

        audio = MP3(str(mp3_path), ID3=ID3)
        if audio.tags is None:
            audio.add_tags()
        tags = audio.tags

        for frame in ("TIT2", "TPE1", "TALB", "TDRC", "TCON", "TRCK", "COMM", "APIC"):
            try:
                tags.delall(frame)
            except Exception:
                pass

        tags.add(TIT2(encoding=3, text=title))
        tags.add(TPE1(encoding=3, text=artist))
        if album:
            tags.add(TALB(encoding=3, text=album))
        if date:
            tags.add(TDRC(encoding=3, text=date))
        if genre:
            tags.add(TCON(encoding=3, text=genre))
        if track_no is not None:
            track_str = f"{track_no}/{total_tracks}" if total_tracks is not None else str(track_no)
            tags.add(TRCK(encoding=3, text=track_str))
        if comment:
            tags.add(COMM(encoding=3, lang="eng", desc="Comment", text=comment))
        if cover_path and cover_path.exists():
            tags.add(
                APIC(
                    encoding=3,
                    mime=detect_mime(cover_path),
                    type=3,
                    desc="Cover",
                    data=cover_path.read_bytes(),
                )
            )

        audio.save(v2_version=3)

    # ------------------------------------------------------------------
    # Helpers: JSON persistence & cover art
    # ------------------------------------------------------------------

    def save_json(
            self,
            data: Dict[str, Any],
            name: str,
            subdir: Optional[Path] = None,
    ) -> Path:
        """Serialise *data* to a uniquely-named JSON file and return its path."""
        folder = subdir if subdir else self.json_dir
        folder.mkdir(parents=True, exist_ok=True)
        path = unique_path(folder / f"{safe_filename(name)}.json")
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        return path

    def save_cover(self, entity: Dict[str, Any], filename_base: str) -> Optional[Path]:
        """
        Download the best thumbnail from *entity* and save it to the covers
        directory. Returns the saved path, or ``None`` on failure.
        """
        thumb_url = best_thumbnail(entity)
        if not thumb_url:
            return None
        suffix = Path(thumb_url.split("?")[0]).suffix or ".jpg"
        cover_path = unique_path(self.cover_dir / f"{safe_filename(filename_base)}{suffix}")
        try:
            download_to_file(thumb_url, cover_path)
            return cover_path
        except Exception:
            return None

    def save_temp_cover(self, entity: Dict[str, Any], fallback_entity: Optional[Dict[str, Any]] = None) -> Optional[Path]:
        """Download the best cover art to a temp file for ID3 embedding."""
        cover = download_best_cover(entity, fallback_entity)
        if not cover:
            return None

        data, mime = cover
        suffix = ".png" if mime == "image/png" else ".jpg"
        try:
            with tempfile.NamedTemporaryFile(prefix="playervf_cover_", suffix=suffix, delete=False) as tmp:
                tmp.write(data)
                return Path(tmp.name)
        except Exception:
            return None

    # ------------------------------------------------------------------
    # Track field extraction
    # ------------------------------------------------------------------

    @staticmethod
    def extract_track_fields(track: Dict[str, Any]) -> Tuple[str, str, str, str]:
        """
        Pull ``(title, artist, album, date)`` strings out of a raw track dict.
        Falls back to sensible defaults when fields are missing.
        """
        video_details = track.get("videoDetails") if isinstance(track.get("videoDetails"), dict) else {}
        title = track.get("title") or track.get("name") or video_details.get("title") or "Unknown Title"

        artists = track.get("artists") or []
        artist = ", ".join(a.get("name", "") for a in artists if a.get("name"))
        if not artist:
            author = track.get("author")
            artist = author if isinstance(author, str) else video_details.get("author") or "Unknown Artist"

        album = ""
        if isinstance(track.get("album"), dict):
            album = track["album"].get("name", "") or ""
        elif isinstance(track.get("album"), str):
            album = track["album"]

        raw_date = str(track.get("year") or track.get("releaseDate") or "")
        date = "" if raw_date == "None" else raw_date

        return title, artist, album, date

    # ------------------------------------------------------------------
    # Single-track download + tag pipeline
    # ------------------------------------------------------------------

    def download_track(
            self,
            track: Dict[str, Any],
            base_dir: Path,
            index: Optional[int] = None,
            total: Optional[int] = None,
            cover_path: Optional[Path] = None,
            verbose: bool = False,
    ) -> Optional[Path]:
        """
        Download a single track dict, write ID3 tags, and save metadata JSON.

        Parameters
        ----------
        track : dict
            Raw track dict from YTMusic (must contain ``"videoId"``).
        base_dir : Path
            Directory in which to save the MP3.
        index : int, optional
            1-based track position within an album/playlist.
        total : int, optional
            Total number of tracks in the collection.
        cover_path : Path, optional
            Pre-downloaded cover image; fetched automatically when ``None``.
        verbose : bool
            Enable yt-dlp verbose output.

        Returns
        -------
        Path or None
            Path to the saved MP3, or ``None`` if the track has no video ID.
        """
        video_details = track.get("videoDetails") if isinstance(track.get("videoDetails"), dict) else {}
        video_id = track.get("videoId") or video_details.get("videoId")
        if not video_id:
            return None

        title, artist, album, date = self.extract_track_fields(track)
        base_dir.mkdir(parents=True, exist_ok=True)

        if index is not None and total is not None:
            stem = base_dir / f"{format_track_no(index, total)} - {safe_filename(title)}"
        else:
            stem = base_dir / f"{safe_filename(artist)} - {safe_filename(title)}"
        stem = unique_media_stem(stem)

        mp3_path, info = self.download_audio_mp3(video_id, stem, verbose=verbose)

        if mp3_path.suffix.lower() == ".mp3":
            temp_cover = None
            tag_cover = cover_path
            if tag_cover is None:
                temp_cover = self.save_temp_cover(track, info if isinstance(info, dict) else None)
                tag_cover = temp_cover
            try:
                self.write_mp3_tags(
                    mp3_path=mp3_path,
                    title=title,
                    artist=artist,
                    album=album,
                    date=date,
                    genre=str(track.get("genre") or ""),
                    track_no=index,
                    total_tracks=total,
                    cover_path=tag_cover,
                    comment=f"Downloaded via yt-dlp from YouTube Music. videoId={video_id}",
                )
            finally:
                if temp_cover:
                    try:
                        temp_cover.unlink(missing_ok=True)
                    except Exception:
                        pass
        return mp3_path

    # ------------------------------------------------------------------
    # High-level entity downloaders
    # ------------------------------------------------------------------

    def download_song(
            self,
            item: SearchItem,
            progress_cb: Optional[Callable[[str], None]] = None,
            verbose: bool = False,
    ) -> List[Path]:
        """Download a single song or video SearchItem. Returns list with one path."""
        entity = self.get_entity_details(item)
        track = entity if isinstance(entity, dict) else item.raw or {}
        video_details = track.get("videoDetails") if isinstance(track.get("videoDetails"), dict) else {}
        if item.video_id and not track.get("videoId") and not video_details.get("videoId"):
            track["videoId"] = item.video_id
        if item.title and not track.get("title") and not video_details.get("title"):
            track["title"] = item.title
        if item.artist and not track.get("author") and not track.get("artists"):
            track["author"] = item.artist
        if item.thumbnail_url and not best_thumbnail(track):
            track["thumbnail"] = [{"url": item.thumbnail_url, "width": 0, "height": 0}]
        if progress_cb:
            progress_cb(f"Downloading: {item.title}")

        mp3 = self.download_track(track, self.download_dir, cover_path=None, verbose=verbose)
        return [mp3] if mp3 else []

    def download_album(
            self,
            item: SearchItem,
            progress_cb: Optional[Callable[[str], None]] = None,
            verbose: bool = False,
    ) -> List[Path]:
        """
        Download every track in an album SearchItem into a dedicated sub-folder.

        Parameters
        ----------
        item : SearchItem
            Must have ``result_type == "album"``.
        progress_cb : callable, optional
            Called with a status string before each track download.
        verbose : bool
            Enable yt-dlp verbose output per track.

        Returns
        -------
        List[Path]
            Paths of all successfully downloaded MP3 files.
        """
        album = self.get_entity_details(item)
        tracks = self.get_album_tracks(album)

        album_title = album.get("title") or item.title or "Album"
        artist = (
                ", ".join(a.get("name", "") for a in album.get("artists", []) if a.get("name"))
                or item.artist
                or "Unknown Artist"
        )
        year = str(album.get("year") or "")

        album_folder = self.download_dir / safe_filename(f"{artist} - {album_title}")
        album_folder.mkdir(parents=True, exist_ok=True)
        cover_path = self.save_temp_cover(album)

        usable = [t for t in tracks if t.get("videoId")]
        total = len(usable)
        downloaded: List[Path] = []
        idx = 0

        try:
            for track in tracks:
                if not track.get("videoId"):
                    continue
                idx += 1
                if progress_cb:
                    progress_cb(f"Album {idx}/{total}: {track.get('title') or 'Unknown'}")

                # Inject album metadata into the track dict when missing
                if not track.get("album"):
                    track["album"] = {"name": album_title}
                elif isinstance(track.get("album"), dict):
                    track["album"]["name"] = track["album"].get("name") or album_title
                track["year"] = track.get("year") or year

                mp3 = self.download_track(
                    track, album_folder,
                    index=idx, total=total,
                    cover_path=cover_path,
                    verbose=verbose,
                )
                if mp3:
                    downloaded.append(mp3)
        finally:
            if cover_path:
                try:
                    cover_path.unlink(missing_ok=True)
                except Exception:
                    pass

        return downloaded

    def download_playlist(
            self,
            item: SearchItem,
            progress_cb: Optional[Callable[[str], None]] = None,
            verbose: bool = False,
    ) -> List[Path]:
        """
        Download every track in a playlist SearchItem into a dedicated sub-folder.

        Parameters
        ----------
        item : SearchItem
            Must have ``result_type`` in
            ``("playlist", "featured_playlist", "community_playlist")``.
        progress_cb : callable, optional
            Called with a status string before each track download.
        verbose : bool
            Enable yt-dlp verbose output per track.

        Returns
        -------
        List[Path]
            Paths of all successfully downloaded MP3 files.
        """
        playlist = self.get_entity_details(item)
        tracks = self.get_playlist_tracks(playlist)

        playlist_title = playlist.get("title") or item.title or "Playlist"
        author_raw = playlist.get("author")
        author = (
                     author_raw.get("name") if isinstance(author_raw, dict) else author_raw
                 ) or item.artist or "Unknown Artist"

        playlist_folder = self.download_dir / safe_filename(f"{author} - {playlist_title}")
        playlist_folder.mkdir(parents=True, exist_ok=True)
        cover_path = self.save_temp_cover(playlist)

        usable = [t for t in tracks if t.get("videoId")]
        total = len(usable)
        downloaded: List[Path] = []
        idx = 0

        try:
            for track in tracks:
                if not track.get("videoId"):
                    continue
                idx += 1
                if progress_cb:
                    progress_cb(f"Playlist {idx}/{total}: {track.get('title') or 'Unknown'}")

                if not track.get("album"):
                    track["album"] = {"name": playlist_title}
                elif isinstance(track.get("album"), dict):
                    track["album"]["name"] = track["album"].get("name") or playlist_title

                mp3 = self.download_track(
                    track, playlist_folder,
                    index=idx, total=total,
                    cover_path=cover_path,
                    verbose=verbose,
                )
                if mp3:
                    downloaded.append(mp3)
        finally:
            if cover_path:
                try:
                    cover_path.unlink(missing_ok=True)
                except Exception:
                    pass

        return downloaded

    def download(
            self,
            item: SearchItem,
            progress_cb: Optional[Callable[[str], None]] = None,
            verbose: bool = False,
    ) -> List[Path]:
        """
        Dispatch to the correct downloader based on ``item.result_type``.

        Supports ``"song"``, ``"video"``, ``"album"``, ``"playlist"``,
        ``"featured_playlist"``, and ``"community_playlist"``.

        Parameters
        ----------
        item : SearchItem
            Any item returned by :meth:`search`.
        progress_cb : callable, optional
            Called with a human-readable progress string before each track.
        verbose : bool
            Enable yt-dlp verbose output.

        Returns
        -------
        List[Path]
            Paths of all downloaded MP3 files.

        Raises
        ------
        ValueError
            If ``item.result_type`` is not recognised.
        """
        if item.result_type in ("song", "video"):
            return self.download_song(item, progress_cb=progress_cb, verbose=verbose)
        if item.result_type == "album":
            return self.download_album(item, progress_cb=progress_cb, verbose=verbose)
        if item.result_type in ("playlist", "featured_playlist", "community_playlist"):
            return self.download_playlist(item, progress_cb=progress_cb, verbose=verbose)
        raise ValueError(f"Unsupported result_type: {item.result_type!r}")


# ---------------------------------------------------------------------------
# Flutter / native bridge helpers
# ---------------------------------------------------------------------------

def add(a: int, b: int) -> int:
    """Tiny bridge smoke-test used by Flutter MethodChannel."""
    return int(a) + int(b)


def _artist_text(entity: Dict[str, Any]) -> str:
    artists = entity.get("artists") or []
    if isinstance(artists, list):
        names = [artist.get("name", "") for artist in artists if isinstance(artist, dict) and artist.get("name")]
        if names:
            return ", ".join(names)

    author = entity.get("author")
    if isinstance(author, dict):
        return author.get("name", "") or ""
    return author if isinstance(author, str) else ""


def _search_item_to_dict(item: SearchItem) -> Dict[str, Any]:
    return {
        "resultType": item.result_type,
        "title": item.title,
        "artist": item.artist,
        "duration": item.duration,
        "videoId": item.video_id,
        "browseId": item.browse_id,
        "thumbnailUrl": item.thumbnail_url or "",
        "raw": item.raw or {},
    }


def _search_item_from_dict(data: Dict[str, Any]) -> SearchItem:
    raw = data.get("raw") if isinstance(data.get("raw"), dict) else data
    result_type = str(data.get("resultType") or data.get("result_type") or raw.get("resultType") or "")
    video_id = str(data.get("videoId") or data.get("video_id") or raw.get("videoId") or "")
    if not result_type and video_id:
        result_type = "song"
    return SearchItem(
        result_type=result_type,
        title=str(data.get("title") or raw.get("title") or "Unknown title"),
        artist=str(data.get("artist") or _artist_text(raw)),
        duration=str(data.get("duration") or raw.get("duration") or ""),
        video_id=video_id,
        browse_id=str(data.get("browseId") or data.get("browse_id") or raw.get("browseId") or ""),
        thumbnails=raw.get("thumbnails") if isinstance(raw.get("thumbnails"), list) else None,
        raw=raw,
    )


def search_youtube_music(query: str, filter_name: str = "songs", limit: int = 20) -> str:
    """Return YouTube Music search results as a JSON string for platform bridges."""
    query = str(query or "").strip()
    if not query:
        return "[]"

    allowed_filters = {"songs", "videos", "albums", "playlists"}
    filter_name = filter_name if filter_name in allowed_filters else "songs"
    downloader = MediaDownloader()
    items = downloader.search(query=query, filter_name=filter_name, limit=int(limit or 20))
    return json.dumps([_search_item_to_dict(item) for item in items], ensure_ascii=True)


def download_youtube_music(item_json: Any, output_dir: Optional[str] = None) -> str:
    """Download a search result and return a JSON payload for Flutter."""
    if isinstance(item_json, str):
        item_data = json.loads(item_json)
    else:
        item_data = dict(item_json or {})

    download_dir = Path(output_dir).expanduser().resolve() if output_dir else DOWNLOAD_DIR
    downloader = MediaDownloader(download_dir=download_dir, progress_cb=_emit_progress)
    item = _search_item_from_dict(item_data)
    files = downloader.download(item)
    payload = {
        "files": [str(path) for path in files],
        "downloadDir": str(download_dir),
        "message": "Downloaded from YouTube Music",
        "downloadedAt": datetime.now().isoformat(timespec="seconds"),
    }
    return json.dumps(payload, ensure_ascii=True)


def stream_youtube_music(item_json: Any) -> str:
    """Resolve a playable audio stream URL for a search result."""
    if isinstance(item_json, str):
        item_data = json.loads(item_json)
    else:
        item_data = dict(item_json or {})

    item = _search_item_from_dict(item_data)
    is_video = item.result_type == "video" or str(item_data.get("resultType") or "").lower() == "video"
    video_id = item.video_id or item.raw.get("videoId")
    if not video_id:
        raise ValueError("This result cannot be streamed because it has no videoId.")

    import yt_dlp

    ydl_opts = {
        "format": "best[ext=mp4][vcodec!=none][acodec!=none]/best[vcodec!=none][acodec!=none]/best" if is_video else "bestaudio[ext=m4a]/bestaudio/best",
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)

    payload = {
        "url": info.get("url", ""),
        "title": item.title or info.get("title", "YouTube Music"),
        "artist": item.artist or info.get("uploader", "YouTube Music"),
        "album": item.raw.get("album", {}).get("name", "") if isinstance(item.raw.get("album"), dict) else "",
        "thumbnailUrl": item.thumbnail_url or info.get("thumbnail", ""),
        "durationSeconds": info.get("duration") or 0,
        "videoId": video_id,
        "isVideo": is_video,
    }
    return json.dumps(payload, ensure_ascii=True)


def _emit_progress(payload: Dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=True), file=sys.stderr, flush=True)


def _main() -> int:
    parser = argparse.ArgumentParser(description="PlayerVf YouTube Music bridge")
    subparsers = parser.add_subparsers(dest="command", required=True)

    add_parser = subparsers.add_parser("add")
    add_parser.add_argument("a", type=int)
    add_parser.add_argument("b", type=int)

    search_parser = subparsers.add_parser("search")
    search_parser.add_argument("--query", required=True)
    search_parser.add_argument("--filter", default="songs")
    search_parser.add_argument("--limit", type=int, default=20)

    download_parser = subparsers.add_parser("download")
    download_parser.add_argument("--item-json", required=True)
    download_parser.add_argument("--output-dir", required=True)

    stream_parser = subparsers.add_parser("stream")
    stream_parser.add_argument("--item-json", required=True)

    args = parser.parse_args()
    if args.command == "add":
        print(add(args.a, args.b))
    elif args.command == "search":
        print(search_youtube_music(args.query, args.filter, args.limit))
    elif args.command == "download":
        print(download_youtube_music(args.item_json, args.output_dir))
    elif args.command == "stream":
        print(stream_youtube_music(args.item_json))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
