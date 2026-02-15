#!/usr/bin/env python3
"""
Python script for audio metadata and cover art extraction using mutagen.
This script handles all audio formats supported by mutagen and provides
a JSON output for integration with Flutter applications.
"""

import json
import sys
import base64
import logging
from typing import Dict, Any, Optional
import mutagen
from mutagen.id3 import ID3, APIC
from mutagen.mp3 import MP3
from mutagen.flac import FLAC
from mutagen.oggopus import OggOpus
from mutagen.oggvorbis import OggVorbis
from mutagen.mp4 import MP4
from mutagen.wavepack import WavePack
from mutagen.asf import ASF
from mutagen.aiff import AIFF
from mutagen.apev2 import APEv2
from mutagen.easyid3 import EasyID3

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def extract_metadata(file_path: str) -> Optional[Dict[str, Any]]:
    """
    Extract metadata from an audio file using mutagen.
    
    Args:
        file_path: Path to the audio file
        
    Returns:
        Dictionary containing extracted metadata or None if extraction fails
    """
    try:
        # Try to load the file with mutagen
        audio = mutagen.File(file_path)
        
        if audio is None:
            logger.error(f"Could not load audio file: {file_path}")
            return None
            
        # Initialize metadata dictionary
        metadata = {
            'title': 'Unknown Title',
            'artist': 'Unknown Artist',
            'album': 'Unknown Album',
            'genre': None,
            'duration': 0.0,
            'cover_art': None
        }
        
        # Extract basic metadata
        if hasattr(audio, 'tags') and audio.tags:
            tags = audio.tags
            
            # Handle different tag formats
            if isinstance(tags, EasyID3):
                # EasyID3 format (MP3, FLAC, etc.)
                metadata['title'] = tags.get('title', ['Unknown Title'])[0]
                metadata['artist'] = tags.get('artist', ['Unknown Artist'])[0]
                metadata['album'] = tags.get('album', ['Unknown Album'])[0]
                metadata['genre'] = tags.get('genre', [None])[0]
            elif isinstance(tags, dict):
                # Dictionary format (MP4, etc.)
                metadata['title'] = tags.get('\xa9nam', tags.get('title', 'Unknown Title'))
                metadata['artist'] = tags.get('\xa9ART', tags.get('artist', 'Unknown Artist'))
                metadata['album'] = tags.get('\xa9alb', tags.get('album', 'Unknown Album'))
                metadata['genre'] = tags.get('\xa9gen', tags.get('genre', None))
            else:
                # Generic tag access
                metadata['title'] = getattr(tags, 'title', getattr(tags, 'TIT2', 'Unknown Title'))
                metadata['artist'] = getattr(tags, 'artist', getattr(tags, 'TPE1', 'Unknown Artist'))
                metadata['album'] = getattr(tags, 'album', getattr(tags, 'TALB', 'Unknown Album'))
                metadata['genre'] = getattr(tags, 'genre', getattr(tags, 'TCON', None))
        
        # Extract duration
        if hasattr(audio, 'info') and hasattr(audio.info, 'length'):
            metadata['duration'] = float(audio.info.length)
        
        # Extract cover art
        cover_art = extract_cover_art(audio)
        if cover_art:
            metadata['cover_art'] = cover_art
            
        return metadata
        
    except Exception as e:
        logger.error(f"Error extracting metadata from {file_path}: {str(e)}")
        return None


def extract_cover_art(audio) -> Optional[str]:
    """
    Extract cover art from audio file and return as base64 encoded string.
    
    Args:
        audio: Mutagen audio file object
        
    Returns:
        Base64 encoded cover art or None if no cover art found
    """
    try:
        # Handle ID3 tags (MP3)
        if isinstance(audio, MP3) and audio.tags:
            if 'APIC:' in audio.tags:
                apic = audio.tags['APIC:'].data
                return base64.b64encode(apic).decode('utf-8')
            elif 'APIC' in audio.tags:
                apic = audio.tags['APIC'].data
                return base64.b64encode(apic).decode('utf-8')
        
        # Handle FLAC
        elif isinstance(audio, FLAC) and audio.pictures:
            picture = audio.pictures[0].data
            return base64.b64encode(picture).decode('utf-8')
        
        # Handle MP4
        elif isinstance(audio, MP4) and 'covr' in audio.tags:
            covr = audio.tags['covr'][0]
            return base64.b64encode(covr).decode('utf-8')
        
        # Handle Ogg formats
        elif isinstance(audio, (OggOpus, OggVorbis)):
            if 'metadata_block_picture' in audio:
                picture = audio['metadata_block_picture'][0]
                return base64.b64encode(picture).decode('utf-8')
        
        # Handle other formats with generic approach
        elif hasattr(audio, 'tags') and audio.tags:
            for tag in audio.tags.values():
                if hasattr(tag, 'data') and isinstance(tag.data, bytes):
                    return base64.b64encode(tag.data).decode('utf-8')
        
        return None
        
    except Exception as e:
        logger.error(f"Error extracting cover art: {str(e)}")
        return None


def main():
    """
    Main function to handle command line execution.
    Expects file path as command line argument.
    """
    if len(sys.argv) != 2:
        print(json.dumps({'error': 'Usage: python extract_tags.py <audio_file_path>'}))
        sys.exit(1)
    
    file_path = sys.argv[1]
    
    try:
        # Extract metadata
        metadata = extract_metadata(file_path)
        
        if metadata:
            # Convert to JSON and print to stdout
            print(json.dumps(metadata))
        else:
            print(json.dumps({'error': f'Could not extract metadata from {file_path}'}))
            sys.exit(1)
            
    except Exception as e:
        error_msg = f"Error processing file {file_path}: {str(e)}"
        logger.error(error_msg)
        print(json.dumps({'error': error_msg}))
        sys.exit(1)


if __name__ == '__main__':
    main()